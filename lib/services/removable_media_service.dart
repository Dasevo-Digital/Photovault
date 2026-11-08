import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

/// Ein erkannter Wechseldatenträger (Kamera, SD-Karte, o.ä.) mit einem
/// gefundenen DCIM-Ordner.
class DetectedMediaSource {
  final String name;
  final String dcimPath;
  const DetectedMediaSource({required this.name, required this.dcimPath});
}

/// Erkennt angeschlossene Kameras/SD-Kartenleser für "Von Kamera
/// importieren": durchsucht die Orte, an denen das System Datenträger
/// einhängt, nach einem `DCIM`-Ordner – dem von praktisch allen
/// Digitalkameras und SD-Karten nach dem DCF-Standard verwendeten Ordner für
/// Fotos/Videos. Diese Datenträger hängen sich im USB-Massenspeicher-Modus
/// automatisch als normaler, per `dart:io` lesbarer Ordner ein, ganz ohne
/// zusätzlichen Treiber oder natives Plugin.
///
/// **Wo gesucht wird.** macOS hängt unter `/Volumes` ein, Linux unter
/// `/media/<Nutzer>` oder `/run/media/<Nutzer>` (das Flatpak darf beide
/// lesen), Windows vergibt Laufwerksbuchstaben. Bis 3.60 wurde auf allen
/// drei Systemen nur `/Volumes` durchsucht – unter Linux und Windows fand
/// die Erkennung also nie etwas. Unter macOS auch nicht: Die Sandbox liess
/// die App nicht in den Datenträger hineinsehen (#334, siehe
/// `macos/Runner/Release.entitlements`), und der Fehler ging hier im
/// `catch` unter.
///
/// Findet bewusst NUR solche Massenspeicher-Geräte. Ein per USB verbundenes
/// iPhone hängt sich unter macOS NICHT als Dateisystem ein – Zugriff darauf
/// liefe ausschließlich über Apples natives ImageCaptureCore-Framework
/// (dasselbe, das Bildschirmfoto/Fotos-App nutzen), was ein eigenes
/// natives Swift-Plugin erfordern würde und hier bewusst nicht umgesetzt ist.
class RemovableMediaService {
  /// [volumesPath] ist nur zum Testen mit einem temporären Verzeichnis statt
  /// der echten Orte des Systems gedacht; seine Unterordner gelten dann als
  /// die eingehängten Datenträger.
  const RemovableMediaService({this.volumesPath});

  final String? volumesPath;

  Future<List<DetectedMediaSource>> detect() async {
    final sources = <DetectedMediaSource>[];
    final gesehen = <String>{};
    for (final (name, ordner) in await _datentraeger()) {
      if (!gesehen.add(p.normalize(ordner.path))) continue;
      final dcim = await _findDcimFolder(ordner);
      if (dcim != null) {
        sources.add(DetectedMediaSource(name: name, dcimPath: dcim.path));
      }
    }
    return sources;
  }

  /// Alle Kandidaten mit dem Namen, unter dem sie im Dialog stehen.
  Future<List<(String, Directory)>> _datentraeger() async {
    if (volumesPath case final pfad?) return _unterordner(pfad);
    if (Platform.isMacOS) return _unterordner('/Volumes');
    if (Platform.isWindows) {
      return [
        for (var c = 'A'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++)
          if (await _gibtEs('${String.fromCharCode(c)}:\\'))
            (
              '${String.fromCharCode(c)}:',
              Directory('${String.fromCharCode(c)}:\\'),
            ),
      ];
    }
    return linuxKandidaten(const ['/media', '/run/media']);
  }

  /// Linux: Die Desktops hängen unter `/media/<Nutzer>/<Name>` oder
  /// `/run/media/<Nutzer>/<Name>` ein, von Hand Eingehängtes liegt oft
  /// direkt unter `/media`. Eine Ebene tiefer zu schauen deckt alle drei
  /// ab; ein Nutzerordner hat ja selbst keinen DCIM-Ordner.
  @visibleForTesting
  static Future<List<(String, Directory)>> linuxKandidaten(
    List<String> wurzeln,
  ) async {
    final r = <(String, Directory)>[];
    for (final wurzel in wurzeln) {
      for (final eintrag in await _unterordner(wurzel)) {
        r
          ..add(eintrag)
          ..addAll(await _unterordner(eintrag.$2.path));
      }
    }
    return r;
  }

  static Future<bool> _gibtEs(String pfad) async {
    try {
      return await Directory(pfad).exists();
    } on FileSystemException {
      return false;
    }
  }

  static Future<List<(String, Directory)>> _unterordner(String pfad) async {
    final r = <(String, Directory)>[];
    try {
      await for (final e in Directory(pfad).list(followLinks: false)) {
        if (e is Directory) r.add((p.basename(e.path), e));
      }
    } on FileSystemException {
      // Gibt es nicht oder ist nicht lesbar – dann eben keine Quellen von
      // hier, statt die App abstürzen zu lassen.
    }
    return r;
  }

  /// Sucht direkt im Wurzelverzeichnis des Datenträgers nach einem Ordner
  /// namens "DCIM" – case-insensitiv, da unterschiedliche Kamera-Dateisysteme
  /// (FAT32/exFAT) die Groß-/Kleinschreibung unterschiedlich handhaben.
  Future<Directory?> _findDcimFolder(Directory volume) async {
    try {
      await for (final entity in volume.list(followLinks: false)) {
        if (entity is Directory &&
            p.basename(entity.path).toUpperCase() == 'DCIM') {
          return entity;
        }
      }
    } on FileSystemException {
      // Kein Lesezugriff (z.B. das System-Boot-Volume ohne Berechtigung,
      // oder ein Netzlaufwerk, das gerade getrennt wird) – einfach überspringen.
    }
    return null;
  }
}
