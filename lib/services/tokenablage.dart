import 'dart:io';

import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:path/path.dart' as p;

import 'library_location.dart';

/// Die Tokens verbundener Bibliotheken – im eigenen Datenordner der App
/// statt in `verbindung.json` neben der Bibliothek (Issue #111).
///
/// **Warum nicht der Schlüsselbund.** Die Mac-App ist ad hoc signiert, ohne
/// Team. Einen Schlüsselbund-Eintrag bindet macOS an genau diese Signatur –
/// und die ändert sich mit jedem Bau: Nach jedem Update fragte macOS nach
/// dem Anmeldepasswort, bevor die App ihren Server erreicht. Der
/// Datenordner liegt am Mac im Container der App (Sandkasten), unter Linux
/// und Windows im Profil des Nutzers; die Bibliothek dagegen oft auf einer
/// externen Platte, die man an einen anderen Rechner stecken kann. Mit
/// einer Developer-ID-Signatur gehört hierher der Schlüsselbund – die
/// Verbindungsdatei kennt nur die [Tokenablage].
class AppTokenablage implements Tokenablage {
  AppTokenablage(this.ordner);

  /// Beim Start: der Ordner `tokens` im Datenordner der App.
  static Future<AppTokenablage> imDatenordner() async => AppTokenablage(
    Directory(p.join((await LibraryLocation.datenordner()).path, 'tokens')),
  );

  final Directory ordner;

  /// Nur, was die Verbindungsdatei selbst vergibt: Hexadezimalziffern.
  /// Eine Kennung aus einer fremden Datei kann so keinen Pfad bilden.
  static final _kennung = RegExp(r'^[0-9a-f]{8,64}$');

  File? _datei(String kennung) => _kennung.hasMatch(kennung)
      ? File(p.join(ordner.path, '$kennung.token'))
      : null;

  @override
  Future<String?> lies(String kennung) async {
    final f = _datei(kennung);
    if (f == null || !await f.exists()) return null;
    final token = (await f.readAsString()).trim();
    return token.isEmpty ? null : token;
  }

  @override
  Future<bool> schreibe(String kennung, String token) async {
    final f = _datei(kennung);
    if (f == null) return false;
    try {
      await ordner.create(recursive: true);
      final teil = File('${f.path}.neu');
      await teil.create();
      if (Platform.isMacOS || Platform.isLinux) {
        await Process.run('chmod', ['600', teil.path]);
      }
      await teil.writeAsString(token, flush: true);
      await teil.rename(f.path);
      return true;
    } catch (_) {
      // Die Verbindungsdatei bricht dann ab, statt das Token neben einer
      // womöglich externen Bibliothek abzulegen.
      return false;
    }
  }

  @override
  Future<void> loesche(String kennung) async {
    final f = _datei(kennung);
    if (f != null && await f.exists()) await f.delete();
  }
}
