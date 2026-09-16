/// Erzeugt lizenzfreie Testbilder zur Laufzeit, statt Beispielfotos ins
/// Repository zu legen.
///
/// Damit sind Formatprüfungen ohne fremdes Bildmaterial möglich – wichtig,
/// weil echte Kameradateien (RAW/HEIC) immer unter einer Lizenz stehen und
/// als Binärdateien das Repository dauerhaft aufblähen würden. Formate, die
/// sich nicht synthetisch erzeugen lassen, deckt stattdessen das Skript
/// `tool/fetch_format_samples.sh` ab (echte Kameradateien, bewusst NICHT
/// versioniert).
///
/// Alle Bilder sind absichtlich klein und deterministisch aufgebaut, damit
/// Tests schnell bleiben und Fehlerbilder reproduzierbar sind.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Formate, die das reine Dart-Paket `image` selbst schreiben kann – nur
/// diese lassen sich synthetisch erzeugen. HEIC/HEIF und alle RAW-Formate
/// fehlen hier bewusst: sie brauchen die native macOS-Schicht
/// (ImageConverter.swift) bzw. echte Kameradateien.
const encodableSampleFormats = <String>['.jpg', '.png', '.tiff', '.bmp', '.gif'];

/// Ein farbiges Testbild mit Verlauf und einem klaren Muster – der Verlauf
/// belegt viele Tonwerte (relevant für Histogramm-/Unschärfeprüfungen), das
/// Muster macht Skalierungs- und Zuschneidefehler sichtbar.
img.Image sampleImage({int width = 64, int height = 48}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final r = (255 * x / (width - 1)).round();
      final g = (255 * y / (height - 1)).round();
      // Schachbrett im Blaukanal – asymmetrisch, damit Spiegelungen auffallen.
      final b = ((x ~/ 8) + (y ~/ 8)) % 2 == 0 ? 40 : 200;
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return image;
}

/// Kodiert [image] in das zu [extension] passende Format.
///
/// Wirft [ArgumentError] für Endungen, die das `image`-Paket nicht schreiben
/// kann – so schlägt ein Test klar fehl, statt still etwas anderes zu prüfen.
Uint8List encodeSample(img.Image image, String extension) {
  switch (extension.toLowerCase()) {
    case '.jpg':
    case '.jpeg':
      return img.encodeJpg(image);
    case '.png':
      return img.encodePng(image);
    case '.tiff':
      return img.encodeTiff(image);
    case '.bmp':
      return img.encodeBmp(image);
    case '.gif':
      return img.encodeGif(image);
    default:
      throw ArgumentError.value(
        extension,
        'extension',
        'Kein synthetisch erzeugbares Format – siehe tool/fetch_format_samples.sh',
      );
  }
}

/// Fertige Beispieldatei-Bytes je Format, bequem für Tests.
Uint8List sampleBytes(String extension, {int width = 64, int height = 48}) =>
    encodeSample(sampleImage(width: width, height: height), extension);
