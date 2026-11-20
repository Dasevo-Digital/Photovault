import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

import 'backup_restore_plan.dart';
import 'vault_crypto.dart';

/// Die Angaben einer Aufnahme aus der gewählten Sicherungsstufe.
class GesicherteAufnahme {
  const GesicherteAufnahme({
    required this.pruefsumme,
    required this.name,
    required this.datum,
    required this.alben,
    required this.liegtVor,
  });

  final String pruefsumme, name;
  final DateTime? datum;
  final List<String> alben;
  final bool liegtVor;

  bool passtZu(String suche) {
    final text = [
      name,
      datum?.toIso8601String() ?? '',
      ...alben,
    ].join(' ').toLowerCase();
    return suche
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .every(text.contains);
  }
}

class AuswahlExportStand {
  const AuswahlExportStand(
    this.erledigt,
    this.gesamt,
    this.ordner,
    this.fehler,
  );
  final int erledigt, gesamt;
  final Directory ordner;
  final List<String> fehler;
}

/// Liest Manifest und Sicherungsstufe wie die Wiederherstellung, exportiert
/// aber Originale direkt. Der Katalog benötigt weder Bibliothek noch Import.
class BackupAuswahl {
  BackupAuswahl._(
    this._wurzel,
    this._schluessel,
    this.aufnahmen,
    this._quellen,
  );
  final String _wurzel;
  String get wurzel => _wurzel;
  final SecretKey? _schluessel;
  final List<GesicherteAufnahme> aufnahmen;
  final Map<String, File> _quellen;

  static Future<BackupAuswahl> oeffne(
    String wurzel, {
    required int schemaVersion,
    String? passphrase,
    String? generation,
    Set<String>? nurPruefsummen,
  }) async {
    final echt = await Directory(wurzel).resolveSymbolicLinks();
    final temp = await Directory.systemTemp.createTemp('pv_auswahl_');
    try {
      final plan =
          await RestorePlaner(
            schemaVersion: schemaVersion,
            meldeProblem: (_, _) {},
          ).erstelle(
            wurzel,
            temp,
            passphrase: passphrase,
            generation: generation,
            streng: true,
            auswahl: nurPruefsummen,
          );
      final quellen = <String, File>{
        for (final datei in plan.dateien) datei.pruefsumme!: datei.quelle,
      };
      final alben = <String, Set<String>>{};
      for (final album in plan.manifest.alben) {
        for (final id in album.aufnahmen) {
          alben.putIfAbsent(id, () => {}).add(album.name);
        }
      }
      final aufnahmen = <GesicherteAufnahme>[];
      for (final a in plan.manifest.aufnahmen) {
        if (nurPruefsummen != null && !nurPruefsummen.contains(a.pruefsumme)) {
          continue;
        }
        if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(a.pruefsumme)) {
          throw const FormatException('pv_restore_manifest');
        }
        aufnahmen.add(
          GesicherteAufnahme(
            pruefsumme: a.pruefsumme,
            name: a.name.replaceAll(r'\', '/').split('/').last,
            datum: DateTime.tryParse('${a.werte['fileCreatedAt']}')?.toLocal(),
            alben: List.unmodifiable(alben[a.pruefsumme] ?? const <String>{}),
            liegtVor: await quellen[a.pruefsumme]?.exists() ?? false,
          ),
        );
      }
      return BackupAuswahl._(
        echt,
        plan.schluessel,
        List.unmodifiable(aufnahmen),
        quellen,
      );
    } finally {
      await temp.delete(recursive: true);
    }
  }

  Stream<AuswahlExportStand> exportiere(
    Set<String> auswahl,
    Directory ziel, {
    Directory? bibliothek,
  }) async* {
    final eintraege = aufnahmen
        .where((a) => auswahl.contains(a.pruefsumme))
        .toList();
    if (eintraege.isEmpty || eintraege.length != auswahl.length) {
      throw const FormatException('pv_restore_manifest');
    }
    final echt = await ziel.resolveSymbolicLinks();
    bool liegtIn(String wurzel) =>
        p.equals(wurzel, echt) || p.isWithin(wurzel, echt);
    if (liegtIn(_wurzel) ||
        (bibliothek != null &&
            liegtIn(await bibliothek.resolveSymbolicLinks()))) {
      throw const FormatException('pv_auswahl_ziel');
    }
    // createTemp legt das Unterverzeichnis exklusiv an. Der Export schreibt
    // nie direkt in einen vorhandenen Benutzerordner.
    final ordner = await Directory(echt).createTemp('PhotoVault-');
    final fehler = <String>[];
    var erledigt = 0;
    try {
      yield AuswahlExportStand(0, eintraege.length, ordner, const []);
      for (final a in eintraege) {
        final teil = File(p.join(ordner.path, '.export-teil'));
        try {
          final quelle = await _quelle(a.pruefsumme);
          if (quelle == null) throw const FormatException('pv_probe_pfad');
          if (_schluessel case final key?) {
            await VaultCrypto.decryptFile(quelle, teil, key);
          } else {
            await quelle.copy(teil.path);
          }
          if ((await sha256.bind(teil.openRead()).first).toString() !=
              a.pruefsumme) {
            throw const FormatException('pv_probe_original');
          }
          await teil.rename(
            p.join(ordner.path, _dateiname(a.name, erledigt + 1)),
          );
        } on Object {
          fehler.add(a.name);
        } finally {
          if (await teil.exists()) await teil.delete();
        }
        yield AuswahlExportStand(
          ++erledigt,
          eintraege.length,
          ordner,
          List.unmodifiable(fehler),
        );
      }
    } finally {
      if (await ordner.list().isEmpty) await ordner.delete();
    }
  }

  /// Prüft die Kopie gegen die importierte Datei. Ein Sicherungsmanifest,
  /// ein Dateiname oder eine passende Größe allein reichen dafür nicht.
  Future<bool> pruefeOriginal(String pruefsumme) async {
    final quelle = await _quelle(pruefsumme);
    if (quelle == null) return false;
    if (_schluessel case final key?) {
      await VaultCrypto.pruefeDatei(
        quelle,
        key,
        erwartetePruefsumme: pruefsumme,
      );
    } else if ((await sha256.bind(quelle.openRead()).first).toString() !=
        pruefsumme) {
      throw const FormatException('pv_probe_original');
    }
    return true;
  }

  Future<File?> _quelle(String pruefsumme) async {
    final quelle = _quellen[pruefsumme];
    if (quelle == null || !await quelle.exists()) return null;
    final pfad = await quelle.resolveSymbolicLinks();
    if (!p.isWithin(_wurzel, pfad)) {
      throw const FormatException('pv_probe_pfad');
    }
    return File(pfad);
  }

  // Fortlaufende Nummern trennen gleiche Namen auch auf Dateisystemen
  // ohne Groß-/Kleinschreibung. Der Präfix entschärft Windows-Gerätenamen.
  static String _dateiname(String name, int nummer) {
    var endung = p.extension(name).replaceAll(RegExp(r'[^a-zA-Z0-9.]'), '');
    if (endung.length > 12) endung = '';
    final basis = p
        .basenameWithoutExtension(name)
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '');
    final kurz = String.fromCharCodes(basis.runes.take(55));
    return '${nummer.toString().padLeft(4, '0')}_$kurz$endung';
  }
}
