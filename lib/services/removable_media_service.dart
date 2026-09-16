import 'dart:io';

import 'package:path/path.dart' as p;

/// Ein erkannter Wechseldatenträger (Kamera, SD-Karte, o.ä.) mit einem
/// gefundenen DCIM-Ordner.
class DetectedMediaSource {
  final String name;
  final String dcimPath;
  const DetectedMediaSource({required this.name, required this.dcimPath});
}

/// Erkennt an den Mac angeschlossene Kameras/SD-Kartenleser für "Von Kamera
/// importieren": durchsucht `/Volumes` nach eingehängten Datenträgern mit
/// einem `DCIM`-Ordner – dem von praktisch allen Digitalkameras und
/// SD-Karten nach dem DCF-Standard verwendeten Ordner für Fotos/Videos.
/// Diese Datenträger hängen sich im USB-Massenspeicher-Modus automatisch als
/// normaler, per `dart:io` lesbarer Ordner ein, ganz ohne zusätzlichen
/// Treiber oder natives Plugin.
///
/// Findet bewusst NUR solche Massenspeicher-Geräte. Ein per USB verbundenes
/// iPhone hängt sich unter macOS NICHT als Dateisystem ein – Zugriff darauf
/// liefe ausschließlich über Apples natives ImageCaptureCore-Framework
/// (dasselbe, das Bildschirmfoto/Fotos-App nutzen), was ein eigenes
/// natives Swift-Plugin erfordern würde und hier bewusst nicht umgesetzt ist.
class RemovableMediaService {
  /// [volumesPath] ist nur zum Testen mit einem temporären Verzeichnis statt
  /// dem echten `/Volumes` gedacht (siehe Standardwert für den Normalfall).
  const RemovableMediaService({this.volumesPath = '/Volumes'});

  final String volumesPath;

  Future<List<DetectedMediaSource>> detect() async {
    final volumesDir = Directory(volumesPath);
    if (!await volumesDir.exists()) return [];

    final sources = <DetectedMediaSource>[];
    try {
      await for (final entity in volumesDir.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final dcim = await _findDcimFolder(entity);
        if (dcim != null) {
          sources.add(DetectedMediaSource(name: p.basename(entity.path), dcimPath: dcim.path));
        }
      }
    } catch (_) {
      // /Volumes selbst nicht lesbar (sollte auf macOS praktisch nie vorkommen) –
      // dann einfach keine Quellen anbieten, statt die App abstürzen zu lassen.
    }
    return sources;
  }

  /// Sucht direkt im Wurzelverzeichnis des Datenträgers nach einem Ordner
  /// namens "DCIM" – case-insensitiv, da unterschiedliche Kamera-Dateisysteme
  /// (FAT32/exFAT) die Groß-/Kleinschreibung unterschiedlich handhaben.
  Future<Directory?> _findDcimFolder(Directory volume) async {
    try {
      await for (final entity in volume.list(followLinks: false)) {
        if (entity is Directory && p.basename(entity.path).toUpperCase() == 'DCIM') {
          return entity;
        }
      }
    } catch (_) {
      // Kein Lesezugriff (z.B. das System-Boot-Volume ohne Berechtigung,
      // oder ein Netzlaufwerk, das gerade getrennt wird) – einfach überspringen.
    }
    return null;
  }
}
