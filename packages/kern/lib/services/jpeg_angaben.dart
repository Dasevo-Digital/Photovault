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
/// **Ohne Ort, solange [mitOrt] ihn nicht verlangt.** Die Datei verlässt
/// die Bibliothek, wird geteilt und weitergeschickt; der Ort steht weiter
/// in der Bibliothek und im Original. Mit [mitOrt] kommt er als GPS-Angabe
/// dazu – so, wie die XMP-Beilage desselben Exports ihn trägt (BEA-128).
///
/// Gibt [jpeg] unverändert zurück, wenn sich der Anhang nicht einsetzen
/// lässt.
Uint8List mitAufnahmeangaben(
  Uint8List jpeg,
  AssetData a, {
  bool mitOrt = false,
}) {
  final ort = a.fileCreatedAt.toLocal();
  String zwei(int n) => n.toString().padLeft(2, '0');
  final zeit =
      '${ort.year.toString().padLeft(4, '0')}:${zwei(ort.month)}:'
      '${zwei(ort.day)} ${zwei(ort.hour)}:${zwei(ort.minute)}:'
      '${zwei(ort.second)}';
  try {
    final exif = img.ExifData();
    exif.imageIfd.orientation = 1;
    if (a.datumVon == null) exif.imageIfd['DateTime'] = img.IfdValueAscii(zeit);
    if (a.cameraMake case final m? when m.trim().isNotEmpty) {
      exif.imageIfd.make = m;
    }
    if (a.cameraModel case final m? when m.trim().isNotEmpty) {
      exif.imageIfd.model = m;
    }
    if (a.datumVon == null) {
      exif.exifIfd['DateTimeOriginal'] = img.IfdValueAscii(zeit);
      exif.exifIfd['DateTimeDigitized'] = img.IfdValueAscii(zeit);
    }
    if ((a.latitude, a.longitude) case (final lat?, final lon?) when mitOrt) {
      final gps = exif.gpsIfd;
      gps['GPSLatitudeRef'] = img.IfdValueAscii(lat < 0 ? 'S' : 'N');
      gps['GPSLatitude'] = _gradMinutenSekunden(lat);
      gps['GPSLongitudeRef'] = img.IfdValueAscii(lon < 0 ? 'W' : 'E');
      gps['GPSLongitude'] = _gradMinutenSekunden(lon);
    }
    return img.injectJpgExif(jpeg, exif) ?? jpeg;
  } catch (_) {
    return jpeg;
  }
}

/// Grad, Minuten und Sekunden als drei Brüche – die Form, die EXIF für
/// GPS-Angaben vorschreibt. `setGpsLocation` aus `package:image` schreibt
/// stattdessen eine Kommazahl, die übliche Leser nicht verstehen.
img.IfdValueRational _gradMinutenSekunden(double wert) {
  final a = wert.abs();
  final grad = a.floor();
  final minuten = ((a - grad) * 60).floor();
  final sekunden = ((a - grad) * 60 - minuten) * 60;
  // `package:image` gibt den Bruch selbst nicht heraus, nur Werte, die
  // ihn tragen (wie in der Gastprüfung des Servers).
  return img.IfdValueRational(grad, 1)
    ..value.addAll(img.IfdValueRational(minuten, 1).value)
    ..value.addAll(
      img.IfdValueRational((sekunden * 10000).round(), 10000).value,
    );
}
