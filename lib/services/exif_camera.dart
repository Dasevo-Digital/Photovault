import 'package:exif/exif.dart';

/// Kamera-/Aufnahme-Metadaten aus den EXIF-Daten eines Fotos – rein
/// informativ, für die Info-Ansicht. Jedes Feld ist einzeln nullable, da
/// Kameras/Apps sehr unterschiedlich viel davon tatsächlich schreiben (ein
/// Screenshot oder ein bearbeitetes Foto hat oft gar keine dieser Tags).
class CameraInfo {
  final String? make;
  final String? model;
  final String? lensModel;
  final double? focalLengthMm;
  final double? fNumber;
  final int? iso;
  final double? exposureTimeSeconds;

  /// Belichtungskorrektur in Blendenstufen – 0 heisst „ohne Korrektur
  /// aufgenommen", `null` heisst „nicht überliefert".
  final double? exposureBiasEv;

  /// Kleinbild-äquivalente Brennweite. Bei Telefonkameras die einzige Zahl,
  /// die dem Nutzer etwas sagt (26 mm statt der echten 5,7 mm).
  final double? focalLength35mm;

  const CameraInfo({
    this.make,
    this.model,
    this.lensModel,
    this.focalLengthMm,
    this.fNumber,
    this.iso,
    this.exposureTimeSeconds,
    this.exposureBiasEv,
    this.focalLength35mm,
  });

  bool get isEmpty =>
      make == null &&
      model == null &&
      lensModel == null &&
      focalLengthMm == null &&
      fNumber == null &&
      iso == null &&
      exposureTimeSeconds == null &&
      exposureBiasEv == null &&
      focalLength35mm == null;
}

/// Liest Kamera-/Objektiv-/Aufnahme-Angaben aus bereits geparsten EXIF-Tags
/// (siehe `readExifFromBytes` aus `package:exif`). Reine, deterministische
/// Logik – bewusst von [ImportService] getrennt, damit sie ohne echte
/// Bilddateien unit-testbar ist (siehe test/exif_camera_test.dart).
///
/// WICHTIG: Für Brennweite/Blende NICHT `IfdTag.printable` verwenden – das
/// gibt bei `package:exif` den gekürzten Bruch zurück (z.B. "14/5" für ein
/// f/2.8-Objektiv, weil 28/10 auf 14/5 gekürzt wird), keine Dezimalzahl.
/// Stattdessen über `.values` als [IfdRatios] gehen und selbst umrechnen.
CameraInfo parseExifCameraInfo(Map<String, IfdTag> tags) {
  String? readString(String key) {
    final value = tags[key]?.printable.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  double? readRatio(String key) {
    final values = tags[key]?.values;
    if (values is IfdRatios && values.ratios.isNotEmpty) {
      return values.ratios.first.toDouble();
    }
    return null;
  }

  int? readInt(String key) {
    final values = tags[key]?.values;
    if (values is IfdInts && values.ints.isNotEmpty) return values.ints.first;
    if (values is IfdRatios && values.ratios.isNotEmpty) return values.ratios.first.toInt();
    return null;
  }

  return CameraInfo(
    make: readString('Image Make'),
    model: readString('Image Model'),
    lensModel: readString('EXIF LensModel'),
    focalLengthMm: readRatio('EXIF FocalLength'),
    fNumber: readRatio('EXIF FNumber'),
    iso: readInt('EXIF ISOSpeedRatings') ?? readInt('EXIF ISOSpeed'),
    exposureTimeSeconds: readRatio('EXIF ExposureTime'),
    // Als Bruch geschrieben (z.B. "-1/3"), deshalb readRatio und nicht
    // readInt: Eine Drittel-Blendenstufe ist der Normalfall am Rad.
    exposureBiasEv: readRatio('EXIF ExposureBiasValue'),
    // Steht in aller Regel als ganze Zahl da, gelegentlich als Bruch –
    // readInt deckt beides ab und liefert Millimeter.
    focalLength35mm: readInt('EXIF FocalLengthIn35mmFilm')?.toDouble(),
  );
}

/// Wandelt einen EXIF-Zeitstempel („yyyy:MM:dd HH:mm:ss") in ein Datum.
///
/// Steht hier und nicht im ImportService, weil inzwischen zwei Wege ihn
/// brauchen: die EXIF-Tags aus `package:exif` und die Antwort des nativen
/// Kanals für Dateien, die `package:exif` nicht lesen kann.
DateTime? exifDatumAusText(String? roh) {
  if (roh == null) return null;
  final teile = roh.trim().split(' ');
  if (teile.length != 2) return null;
  final datum = teile[0].split(':');
  final zeit = teile[1].split(':');
  if (datum.length != 3 || zeit.length != 3) return null;
  try {
    final jahr = int.parse(datum[0]);
    // Kameras schreiben bei ungestellter Uhr „0000:00:00 00:00:00".
    if (jahr < 1990) return null;
    return DateTime(
      jahr,
      int.parse(datum[1]),
      int.parse(datum[2]),
      int.parse(zeit[0]),
      int.parse(zeit[1]),
      int.parse(zeit[2]),
    );
  } catch (_) {
    return null;
  }
}
