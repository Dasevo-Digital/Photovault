import 'dart:io';

import 'package:path/path.dart' as p;

/// Der Weg zu darktable und zurück (#347).
///
/// **Arbeitskopie statt Bibliothek.** darktable bekommt eine Kopie des
/// Originals in einem eigenen Ordner, daneben die Beilage unter dem Namen,
/// den darktable sucht (`IMG_1234.CR3.xmp`). Die Bibliothek gehört
/// Photo Vault; mit Server liegen die Originale ohnehin nicht hier.
///
/// **Kein Warten im Hintergrund.** Bearbeiten dauert Stunden oder Tage, und
/// ob ein JPEG schon fertig geschrieben ist, sieht man ihm nicht an. Das
/// Ergebnis holt man deshalb von Hand ab. Der Ordner merkt sich dabei, was
/// noch offen ist, über jeden Neustart hinweg.
class DarktableBruecke {
  DarktableBruecke(this.ablage, {Future<bool> Function(String)? starte})
    : _starte = starte ?? starteDarktable;

  /// Unter „Bilder“: Dort darf darktable auch im Flatpak hin.
  factory DarktableBruecke.standard() => DarktableBruecke(
    Directory(
      p.join(
        Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'] ??
            Directory.systemTemp.path,
        'Pictures',
        'PhotoVault-darktable',
      ),
    ),
  );

  final Directory ablage;
  final Future<bool> Function(String) _starte;

  Directory ordner(String id) => Directory(p.join(ablage.path, id));
  bool offen(String id) => ordner(id).existsSync();

  File beilage(String id, String name) =>
      File(p.join(ordner(id).path, '${p.basename(name)}.xmp'));

  /// Legt Kopie und Beilage an und startet darktable. `false`: Das Programm
  /// liess sich nicht starten, die Kopie liegt trotzdem bereit. Ist schon
  /// eine Arbeitskopie da, bleibt sie, mitsamt ihrer Bearbeitung.
  Future<bool> oeffne({
    required String id,
    required String name,
    required File original,
    required String xmp,
  }) async {
    final platz = await ordner(id).create(recursive: true);
    final kopie = File(p.join(platz.path, p.basename(name)));
    if (!await kopie.exists()) {
      final teil = File('${kopie.path}.teil');
      await original.copy(teil.path);
      await teil.rename(kopie.path);
      await beilage(id, name).writeAsString(xmp, flush: true);
    }
    return _starte(kopie.path);
  }

  /// Das zuletzt exportierte JPEG, irgendwo im Ordner (darktable legt es in
  /// `darktable_exported/` ab). Die Arbeitskopie selbst zählt nicht.
  Future<File?> ergebnis(String id, String name) async {
    final platz = ordner(id);
    if (!await platz.exists()) return null;
    final kopie = p.join(platz.path, p.basename(name));
    File? beste;
    DateTime? zeit;
    await for (final e in platz.list(recursive: true, followLinks: false)) {
      if (e is! File || p.equals(e.path, kopie)) continue;
      final endung = p.extension(e.path).toLowerCase();
      if (endung != '.jpg' && endung != '.jpeg') continue;
      final t = await e.lastModified();
      if (zeit == null || t.isAfter(zeit)) {
        beste = e;
        zeit = t;
      }
    }
    return beste;
  }

  /// Räumt die Arbeitskopie weg. Nur unterhalb der [ablage].
  Future<void> schliesse(String id) async {
    final platz = ordner(id);
    if (p.isWithin(ablage.path, platz.path) && await platz.exists()) {
      await platz.delete(recursive: true);
    }
  }
}

/// Startet darktable mit [datei]; `false`, wenn das nicht geht. Aus dem
/// Flatpak kommt man an Programme des Systems nicht heran.
Future<bool> starteDarktable(String datei) async {
  try {
    if (Platform.isMacOS) {
      final r = await Process.run('open', ['-a', 'darktable', datei]);
      return r.exitCode == 0;
    }
    if (Platform.isWindows) {
      final wurzel =
          Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
      final programm = p.join(wurzel, 'darktable', 'bin', 'darktable.exe');
      if (!await File(programm).exists()) return false;
      await Process.start(programm, [datei], mode: ProcessStartMode.detached);
      return true;
    }
    if (Platform.isLinux) {
      if (Platform.environment.containsKey('FLATPAK_ID')) return false;
      await Process.start('darktable', [
        datei,
      ], mode: ProcessStartMode.detached);
      return true;
    }
  } on ProcessException {
    return false;
  }
  return false;
}
