import 'dart:io';

import 'package:path/path.dart' as p;

import 'bearbeitungsbruecke.dart';
import 'fremdprogramme.dart';

/// Der Weg zu darktable und zurück (#347) – eine [Bearbeitungsbruecke]
/// mit den Eigenheiten von darktable.
///
/// **Die Beilage.** darktable bekommt neben der Kopie die Beilage unter
/// dem Namen, den es sucht (`IMG_1234.CR3.xmp`). Darin stehen Sterne und
/// Farbmarke aus der Bibliothek; was darktable dort ändert, kommt beim
/// Übernehmen zurück, und seine Bearbeitung kann der Server rendern
/// (#351).
///
/// **Nur JPEG.** darktable exportiert nach `darktable_exported/`, und sein
/// Hinweis sagt „als JPEG“. Daran ändert #499 nichts: Wer schon einen
/// Arbeitsordner mit einem TIFF-Zwischenstand liegen hat, soll ihn nicht
/// plötzlich als Ergebnis übernommen bekommen.
class DarktableBruecke extends Bearbeitungsbruecke {
  DarktableBruecke(super.ablage, {Future<bool> Function(String)? starte})
    : super(
        starte: starte ?? starteDarktable,
        mitBeilage: true,
        endungen: const {'.jpg', '.jpeg'},
        kopieZaehlt: false,
      );

  /// Unter „Bilder“, dort kommt darktable auch aus dem Flatpak hin. Auf dem
  /// Mac direkt im Container: HOME zeigt in der Sandbox dorthin, und
  /// `Pictures` wäre ein Verweis auf einen Ordner, den die App nicht
  /// beschreiben darf. Der Ort selbst steht seit #499 in
  /// [arbeitsordnerBasis], damit die anderen Programme daneben liegen.
  factory DarktableBruecke.standard() => DarktableBruecke(
    Directory(p.join(arbeitsordnerBasis(), Bekannt.darktable.ordner)),
  );
}

/// Wo die Ordner der Arbeitskopien liegen (siehe [DarktableBruecke.standard]).
String arbeitsordnerBasis() {
  final heim =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.systemTemp.path;
  return Platform.isMacOS ? heim : p.join(heim, 'Pictures');
}

/// Startet darktable mit [datei]; `false`, wenn das nicht geht. Aus dem
/// Flatpak kommt man an Programme des Systems nicht heran.
///
/// Ohne gefundenen Pfad – genau der Weg von vor #499: unter macOS
/// `open -a darktable`, unter Windows der übliche Programmordner, unter
/// Linux `darktable` aus dem PATH (siehe [Programmstarter]).
Future<bool> starteDarktable(String datei) =>
    Programmstarter().starte(Fremdprogramm.bekannt(Bekannt.darktable), datei);
