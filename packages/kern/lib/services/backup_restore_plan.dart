import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'backup_dateinamen.dart';
import 'backup_manifest.dart';
import 'backup_modelle.dart';
import 'backup_schnappschuss.dart';
import 'import_service.dart';
import 'vault_crypto.dart';

/// Löst vor dem ersten Import genau einen Stand auf und prüft dessen
/// Grenzen. Die Ausführung verändert diesen Plan anschließend nicht mehr.
class RestorePlaner {
  RestorePlaner({required this.schemaVersion, required this.meldeProblem});
  final int schemaVersion;
  final void Function(String, Object) meldeProblem;
  Future<RestorePlan> erstelle(
    String wurzel,
    ImportService importe,
    Directory temp, {
    String? passphrase,
    String? generation,
    SecretKey? schluessel,
    Set<String>? auswahl,
    bool streng = false,
  }) async {
    final speicher = BackupSchnappschussSpeicher();
    // Die Pfadprüfung geschieht vor Entschlüsselung und vor jedem Import.
    final snapshot = await speicher.waehle(wurzel, generation);
    final keyFile = File(p.join(wurzel, 'vault.key'));
    if (schluessel == null && await keyFile.exists()) {
      if (passphrase == null) throw const BackupBrauchtPassphrase();
      final j = jsonDecode(await keyFile.readAsString()) as Map;
      schluessel = await VaultCrypto.unwrapMasterKey(
        passphrase,
        kdfSalt: base64Decode(j['kdfSalt'] as String),
        nonce: base64Decode(j['nonce'] as String),
        wrapped: base64Decode(j['wrapped'] as String),
      );
    }
    File? klarerSnapshot;
    Future<File> leseSnapshot() async {
      final ziel = File(p.join(temp.path, 'schnappschuss.sqlite'));
      if (!await ziel.exists()) {
        if (schluessel == null) {
          throw const FormatException('pv_probe_schluessel');
        }
        await VaultCrypto.decryptFile(snapshot, ziel, schluessel);
      }
      return ziel;
    }

    var manifest = BackupManifest();
    final meta = File(
      p.join(
        generation == null ? wurzel : p.dirname(snapshot.path),
        'metadata.json',
      ),
    );
    if (generation != null) {
      // Auch ältere Punkte ohne eigene Beilage bestimmen ALLE Metadaten
      // aus ihrem Snapshot. Die aktuelle Root-Beilage kommt nie dazu.
      klarerSnapshot = await leseSnapshot();
      manifest = speicher.manifestAusDatei(klarerSnapshot);
    } else {
      if (await meta.exists()) {
        try {
          var datei = meta;
          if (schluessel case final key?) {
            datei = File(p.join(temp.path, 'metadata.json'));
            await VaultCrypto.decryptFile(meta, datei, key);
          }
          manifest = BackupManifest.ausText(
            await datei.readAsString(),
            streng: streng,
          );
        } on Object catch (e) {
          if (streng) rethrow;
          meldeProblem('pv_restore_metadaten', e);
        }
      }
      if (schluessel != null && await snapshot.exists()) {
        try {
          klarerSnapshot = await leseSnapshot();
          if (manifest.aufnahmen.isEmpty) {
            manifest = speicher.manifestAusDatei(klarerSnapshot);
          }
        } on Object catch (e) {
          if (streng) rethrow;
          meldeProblem('pv_restore_schnappschuss', e);
        }
      }
    }
    // Ein falscher oder unlesbarer ausgewählter Punkt darf nicht erst nach
    // dem Import auffallen und niemals auf den aktuellen Stand zurückfallen.
    if (klarerSnapshot != null) {
      final db = sqlite3.open(klarerSnapshot.path, mode: OpenMode.readOnly);
      try {
        if ((db.select('PRAGMA user_version').single.values.single as int) >
                schemaVersion ||
            db.select('PRAGMA integrity_check').single.values.single != 'ok') {
          throw const FormatException('pv_restore_schnappschuss');
        }
      } finally {
        db.close();
      }
    }
    final dateien = <RestoreDatei>[];
    final daten = Directory(p.join(wurzel, VerschluesselteNamen.ordner));
    final originals = Directory(p.join(wurzel, 'originals'));
    final alteOrdnerstruktur =
        generation == null &&
        auswahl == null &&
        (!await daten.exists() || schluessel == null) &&
        manifest.aufnahmen.any((a) => a.ablage == null);
    if (manifest.aufnahmen.isNotEmpty && !alteOrdnerstruktur) {
      final root = p.normalize(p.absolute(wurzel));
      final echt = await Directory(root).resolveSymbolicLinks();
      for (final a in manifest.aufnahmen) {
        if (auswahl != null && !auswahl.contains(a.pruefsumme)) continue;
        final String relativ;
        if (schluessel != null && await daten.exists()) {
          relativ = p.join(
            VerschluesselteNamen.ordner,
            await VerschluesselteNamen.fuerPruefsumme(a.pruefsumme, schluessel),
          );
        } else {
          relativ = a.ablage ?? '';
        }
        final path = p.normalize(p.join(root, relativ));
        if (relativ.isEmpty ||
            p.isAbsolute(relativ) ||
            !p.isWithin(root, path)) {
          if (streng) throw const FormatException('pv_probe_pfad');
          meldeProblem(
            'pv_restore_pfad',
            const FormatException('pv_probe_pfad'),
          );
          continue;
        }
        final f = File(path);
        if (await f.exists() &&
            !p.isWithin(echt, await f.resolveSymbolicLinks())) {
          throw const FormatException('pv_probe_pfad');
        }
        dateien.add(
          RestoreDatei(f, p.extension(a.name), pruefsumme: a.pruefsumme),
        );
      }
    } else if (generation == null) {
      // Alte Sicherungen ohne lesbare Beilage bleiben über ihre Originale
      // zugänglich. Ein beschädigtes Manifest bleibt in der Bilanz sichtbar.
      final dir = await originals.exists() ? originals.path : wurzel;
      for (final f in await importe.collectSupportedFilesInFolder(dir)) {
        dateien.add(RestoreDatei(File(f), p.extension(f)));
      }
    }
    return RestorePlan(
      manifest: manifest,
      dateien: dateien,
      zwischenlager: temp,
      schluessel: schluessel,
      schnappschuss: klarerSnapshot,
    );
  }
}
