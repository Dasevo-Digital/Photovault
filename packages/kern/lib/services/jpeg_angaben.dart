import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../db/database.dart';

/// Schreibt in eine gewandelte JPEG-Datei, was ein anderes Programm über die
/// Aufnahme wissen sollte (#210): den Aufnahmezeitpunkt, die Kamera und die
/// Ausrichtung „oben“ – die Pixel sind beim Wandeln schon gedreht.
///
/// **Warum nachträglich.** Der Wandler streift jeden EXIF-Anhang ab (siehe
/// `DesktopImageTools.convertToJpeg`), weil der Datenschutzexport und das
/// Fotobuch sich darauf verlassen. Wer ein DNG als JPEG herunterlädt, will
/// aber, dass es im nächsten Programm am richtigen Tag steht.
///
/// **Ohne Ort.** Die Datei verlässt die Bibliothek, wird geteilt und
/// weitergeschickt; der Ort steht weiter in der Bibliothek und im Original.
///
/// Gibt [jpeg] unverändert zurück, wenn sich der Anhang nicht einsetzen
/// lässt.
Uint8List mitAufnahmeangaben(Uint8List jpeg, AssetData a) {
  final ort = a.fileCreatedAt.toLocal();
  String zwei(int n) => n.toString().padLeft(2, '0');
  final zeit =
      '${ort.year.toString().padLeft(4, '0')}:${zwei(ort.month)}:'
      '${zwei(ort.day)} ${zwei(ort.hour)}:${zwei(ort.minute)}:'
      '${zwei(ort.second)}';
  try {
    final exif = img.ExifData();
    exif.imageIfd.orientation = 1;
    exif.imageIfd['DateTime'] = img.IfdValueAscii(zeit);
    if (a.cameraMake case final m? when m.trim().isNotEmpty) {
      exif.imageIfd.make = m;
    }
    if (a.cameraModel case final m? when m.trim().isNotEmpty) {
      exif.imageIfd.model = m;
    }
    exif.exifIfd['DateTimeOriginal'] = img.IfdValueAscii(zeit);
    exif.exifIfd['DateTimeDigitized'] = img.IfdValueAscii(zeit);
    return img.injectJpgExif(jpeg, exif) ?? jpeg;
  } catch (_) {
    return jpeg;
  }
}
