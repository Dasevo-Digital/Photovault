import 'package:exif/exif.dart';

/// Liest den GPS-Ort aus bereits geparsten EXIF-Tags (siehe
/// `readExifFromBytes` aus `package:exif`). Reine, deterministische Logik –
/// bewusst von [ImportService] getrennt, damit sie ohne echte Bilddateien
/// unit-testbar ist (siehe test/exif_gps_test.dart).
///
/// EXIF speichert GPS-Koordinaten als Grad/Minuten/Sekunden (3 Ratios) plus
/// eine Referenz ('N'/'S' bzw. 'E'/'W'), die bestimmt, ob der Wert südlich/
/// westlich negativ wird. Gibt `null` zurück, wenn keine oder unvollständige
/// GPS-Tags vorhanden sind.
({double latitude, double longitude})? parseExifGps(Map<String, IfdTag> tags) {
  final latValues = tags['GPS GPSLatitude']?.values;
  final lngValues = tags['GPS GPSLongitude']?.values;
  if (latValues is! IfdRatios || lngValues is! IfdRatios) return null;
  if (latValues.ratios.length < 3 || lngValues.ratios.length < 3) return null;

  final latRef = tags['GPS GPSLatitudeRef']?.printable.trim().toUpperCase();
  final lngRef = tags['GPS GPSLongitudeRef']?.printable.trim().toUpperCase();

  var latitude = _dmsToDecimalDegrees(latValues.ratios);
  var longitude = _dmsToDecimalDegrees(lngValues.ratios);
  if (latRef == 'S') latitude = -latitude;
  if (lngRef == 'W') longitude = -longitude;

  // Grobe Plausibilitätsprüfung – schützt vor kaputten/leeren EXIF-Blöcken,
  // die technisch gültige, aber unsinnige Ratios enthalten (z.B. 0/0).
  if (latitude.isNaN || longitude.isNaN) return null;
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return null;

  return (latitude: latitude, longitude: longitude);
}

double _dmsToDecimalDegrees(List<Ratio> dms) {
  final degrees = dms[0].toDouble();
  final minutes = dms[1].toDouble();
  final seconds = dms[2].toDouble();
  return degrees + minutes / 60 + seconds / 3600;
}
