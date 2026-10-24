import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'library_location.dart';
import 'platform/folder_access.dart';

/// Der Zielordner des automatischen Backups – mit dem Merkmal, das unter
/// macOS den Zugriff über einen Neustart hinweg erhält (#211).
///
/// **Warum.** Gewählt wurde der Ordner bisher mit einem einfachen
/// Ordnerdialog, und gespeichert war nur sein Pfad. Der Sandkasten erlaubt
/// den Zugriff dann bis zum Ende der Sitzung; nach dem nächsten Start
/// scheiterte jedes automatische Backup mit „Operation not permitted“ –
/// wortlos, bis #207 es meldete. Der überwachte Ordner und der Ort der
/// Bibliothek kannten das Problem schon und merken sich dafür ein
/// Security-Scoped Bookmark (siehe [FolderAccess]).
///
/// Der Pfad steht weiter in `backup_settings`; das Merkmal steht daneben in
/// `sicherungsziel.json` im Datenordner der App, wie `location.json`. Es
/// gilt nur auf diesem Rechner und gehört deshalb nicht in die Datenbank,
/// die in jede Sicherung wandert.
abstract final class Sicherungsziel {
  static Future<File> _datei() async => File(
    p.join((await LibraryLocation.datenordner()).path, 'sicherungsziel.json'),
  );

  static Future<Map<String, String>> _merkmale() async {
    try {
      final f = await _datei();
      if (!await f.exists()) return {};
      return (jsonDecode(await f.readAsString()) as Map).cast<String, String>();
    } catch (_) {
      return {};
    }
  }

  /// Merkt sich das Merkmal [token] für den Ordner [pfad]. Ein leeres
  /// Merkmal (Linux, Windows) wird nicht gespeichert.
  static Future<void> merke(String pfad, String token) async {
    if (token.isEmpty) return;
    final alle = await _merkmale()
      ..[pfad] = token;
    final f = await _datei();
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(alle));
  }

  /// Öffnet den Zugriff auf [pfad] und gibt zurück, wohin geschrieben wird:
  /// unter macOS der Ort aus dem gemerkten Merkmal (auch nach einem Umzug
  /// des Ordners), sonst [pfad] selbst. Ohne Merkmal wird [pfad] trotzdem
  /// versucht – liegt der Ordner im eigenen Bereich der App, geht das;
  /// sonst scheitert das Schreiben, und [zugriffVerweigert] erkennt es.
  static Future<String> oeffne(String pfad) async {
    final zugriff = FolderAccess.forCurrentPlatform();
    if (zugriff.usesAccessToken) {
      final token = (await _merkmale())[pfad];
      if (token != null) {
        final offen = await zugriff.resolveRoot(path: pfad, token: token);
        if (offen != null) return offen;
      }
    }
    return pfad;
  }

  /// Ob [fehler] heisst: Das Betriebssystem lässt nicht schreiben – unter
  /// macOS der Sandkasten (`EPERM`), sonst fehlende Rechte (`EACCES`).
  static bool zugriffVerweigert(Object fehler) =>
      fehler is PathAccessException ||
      (fehler is FileSystemException &&
          (fehler.osError?.errorCode == 1 || fehler.osError?.errorCode == 13));
}

/// Das automatische Backup darf nicht in seinen Zielordner schreiben
/// (siehe [Sicherungsziel]).
class BackupZielGesperrt implements Exception {
  const BackupZielGesperrt(this.pfad);
  final String pfad;

  @override
  String toString() => 'BackupZielGesperrt($pfad)';
}
