import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'backup_service.dart' show VerschluesselteNamen;
import 'vault_crypto.dart';

/// Ein Fortschritt der Wiederherstellungsprobe.
///
/// Die Prüfung importiert bewusst nichts in die geöffnete Bibliothek. Sie
/// liest jede gesicherte Datei, vergleicht ihre SHA-256-Prüfsumme mit dem
/// Sicherungsmanifest und prüft bei verschlüsselten Sicherungen zusätzlich
/// die AES-GCM-Authentifizierung beim Entschlüsseln.
class BackupPrueffortschritt {
  final int erledigt;
  final int gesamt;
  final int gueltig;
  final int fehlend;
  final int beschaedigt;
  final String? datei;
  final bool abgeschlossen;

  const BackupPrueffortschritt({
    required this.erledigt,
    required this.gesamt,
    required this.gueltig,
    required this.fehlend,
    required this.beschaedigt,
    this.datei,
    this.abgeschlossen = false,
  });

  bool get erfolgreich => abgeschlossen && fehlend == 0 && beschaedigt == 0;
}

/// Wird geworfen, wenn ein verschlüsseltes Backup ohne Passphrase geprüft
/// werden soll. Der Bildschirm kann dafür denselben Eingabedialog wie beim
/// Wiederherstellen verwenden.
class BackupPruefungBrauchtPassphrase implements Exception {
  const BackupPruefungBrauchtPassphrase();
}

/// Der gewählte Ordner enthält kein Backup.
///
/// Eigene Klasse statt einer Ausnahme mit deutschem Satz darin: Die
/// Oberfläche übersetzt den Fall, und `keine_festen_texte_test` besteht
/// darauf, dass kein fertiger Satz im Programm steht.
class BackupOrdnerFehlt implements Exception {
  const BackupOrdnerFehlt();
}

/// Prüft, ob ein Backup tatsächlich wiederherstellbare Originaldateien
/// enthält, ohne die geöffnete Bibliothek anzufassen.
class BackupPruefdienst {
  static const _backupOrdner = 'PhotoVault-Backup';
  static const _uuid = Uuid();

  /// Akzeptiert sowohl den eigentlichen Backup-Ordner als auch dessen
  /// übergeordneten Zielordner. Die Dateiauswahl nennt beide Varianten,
  /// deshalb darf die Prüfung nicht von dieser leicht zu verwechselnden
  /// Ordnerstufe abhängen.
  static Future<String> findeBackupWurzel(String ausgewaehlt) async {
    final direkt = Directory(ausgewaehlt);
    if (await File(p.join(direkt.path, 'metadata.json')).exists() ||
        await File(p.join(direkt.path, 'vault.key')).exists() ||
        await Directory(p.join(direkt.path, 'originals')).exists() ||
        await Directory(p.join(direkt.path, VerschluesselteNamen.ordner))
            .exists()) {
      return direkt.path;
    }
    final darunter = Directory(p.join(direkt.path, _backupOrdner));
    if (await darunter.exists()) return darunter.path;
    return direkt.path;
  }

  Stream<BackupPrueffortschritt> pruefe(
    String ausgewaehlt, {
    String? passphrase,
  }) async* {
    final wurzel = await findeBackupWurzel(ausgewaehlt);
    final backup = Directory(wurzel);
    if (!await backup.exists()) {
      throw const BackupOrdnerFehlt();
    }

    final keyDatei = File(p.join(wurzel, 'vault.key'));
    SecretKey? schluessel;
    if (await keyDatei.exists()) {
      if (passphrase == null) throw const BackupPruefungBrauchtPassphrase();
      final envelope =
          jsonDecode(await keyDatei.readAsString()) as Map<String, dynamic>;
      schluessel = await VaultCrypto.unwrapMasterKey(
        passphrase,
        kdfSalt: base64Decode(envelope['kdfSalt'] as String),
        nonce: base64Decode(envelope['nonce'] as String),
        wrapped: base64Decode(envelope['wrapped'] as String),
      );
    }

    final temp = await Directory.systemTemp.createTemp('pv_backup_pruefung_');
    try {
      final manifest = await _leseManifest(wurzel, schluessel, temp);
      final erwartet = <String, String?>{
        for (final roh in manifest['assets'] as List<dynamic>? ?? const [])
          if (roh is Map &&
              roh['checksum'] is String &&
              (roh['checksum'] as String).isNotEmpty)
            roh['checksum'] as String: roh['backupRelativePath'] as String?,
      };
      if (erwartet.isEmpty) {
        throw const FormatException(
            'Das Backup enthält kein lesbares Dateimanifest.');
      }

      var erledigt = 0;
      var gueltig = 0;
      var fehlend = 0;
      var beschaedigt = 0;
      yield BackupPrueffortschritt(
        erledigt: 0,
        gesamt: erwartet.length,
        gueltig: 0,
        fehlend: 0,
        beschaedigt: 0,
      );

      // Das aktuelle verschlüsselte Format leitet den Dateinamen aus der
      // Prüfsumme ab. So kann jede erwartete Datei direkt gefunden werden,
      // ohne den gesamten Sicherungsdatenträger erst komplett zu hashen.
      final verschluesselteDaten =
          Directory(p.join(wurzel, VerschluesselteNamen.ordner));
      final istVerschluesselt = schluessel != null;
      final alteDateien = istVerschluesselt
          ? const <String, File>{}
          : await _alteDateienNachPruefsumme(wurzel);

      for (final eintrag in erwartet.entries) {
        final checksum = eintrag.key;
        File? datei;
        if (istVerschluesselt && await verschluesselteDaten.exists()) {
          final name =
              await VerschluesselteNamen.fuerPruefsumme(checksum, schluessel);
          datei = File(p.join(verschluesselteDaten.path, name));
        } else if (eintrag.value != null) {
          final relativ =
              eintrag.value!.replaceFirst(RegExp(r'^originals[\\/]'), '');
          datei = File(p.join(wurzel, 'originals', relativ));
        } else {
          datei = alteDateien[checksum];
        }

        if (datei == null || !await datei.exists()) {
          fehlend++;
        } else {
          try {
            final zuPruefen = istVerschluesselt
                ? await _entschluessleKurz(datei, schluessel, temp, erledigt)
                : datei;
            final erhalten =
                (await sha256.bind(zuPruefen.openRead()).first).toString();
            if (erhalten == checksum) {
              gueltig++;
            } else {
              beschaedigt++;
            }
            if (zuPruefen.path.startsWith(temp.path) &&
                await zuPruefen.exists()) {
              await zuPruefen.delete();
            }
          } catch (_) {
            // Eine falsch eingegebene Passphrase oder ein manipulierter
            // GCM-Block ist genau ein nicht wiederherstellbares Original.
            beschaedigt++;
          }
        }
        erledigt++;
        yield BackupPrueffortschritt(
          erledigt: erledigt,
          gesamt: erwartet.length,
          gueltig: gueltig,
          fehlend: fehlend,
          beschaedigt: beschaedigt,
          datei: datei == null ? null : p.basename(datei.path),
        );
      }
      yield BackupPrueffortschritt(
        erledigt: erledigt,
        gesamt: erwartet.length,
        gueltig: gueltig,
        fehlend: fehlend,
        beschaedigt: beschaedigt,
        abgeschlossen: true,
      );
    } finally {
      // Hier können entschlüsselte Metadaten und jeweils ein Original
      // liegen. Der Ordner wird bei Erfolg, Fehler und Stream-Abbruch
      // entfernt; im Sicherungsziel selbst entsteht nie Klartext.
      try {
        await temp.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>> _leseManifest(
      String wurzel, SecretKey? schluessel, Directory temp) async {
    final quelle = File(p.join(wurzel, 'metadata.json'));
    if (!await quelle.exists()) {
      throw const FormatException('metadata.json fehlt im Backup.');
    }
    File zuLesen = quelle;
    if (schluessel != null) {
      zuLesen = File(p.join(temp.path, 'metadata.json'));
      await VaultCrypto.decryptFile(quelle, zuLesen, schluessel);
    }
    final daten = jsonDecode(await zuLesen.readAsString());
    if (daten is! Map<String, dynamic>) {
      throw const FormatException('metadata.json hat kein gültiges Format.');
    }
    return daten;
  }

  Future<Map<String, File>> _alteDateienNachPruefsumme(String wurzel) async {
    final originals = Directory(p.join(wurzel, 'originals'));
    if (!await originals.exists()) return const {};
    final ergebnis = <String, File>{};
    await for (final eintrag
        in originals.list(recursive: true, followLinks: false)) {
      if (eintrag is! File ||
          p.extension(eintrag.path).toLowerCase() == '.xmp') {
        continue;
      }
      try {
        final checksum =
            (await sha256.bind(eintrag.openRead()).first).toString();
        ergebnis.putIfAbsent(checksum, () => eintrag);
      } catch (_) {
        // Nicht lesbare Dateien können keinem Manifest-Eintrag genügen.
        // Sie bleiben deshalb absichtlich außerhalb der Zuordnung.
      }
    }
    return ergebnis;
  }

  Future<File> _entschluessleKurz(
      File quelle, SecretKey schluessel, Directory temp, int nummer) async {
    final ziel = File(p.join(temp.path, '${_uuid.v4()}_$nummer'));
    await VaultCrypto.decryptFile(quelle, ziel, schluessel);
    return ziel;
  }
}
