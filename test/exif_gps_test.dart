import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/exif_gps.dart';

/// Baut ein minimales, aber realistisches Tag-Set nachwie es
/// `readExifFromBytes` für ein Foto mit GPS-Daten liefern würde – ohne eine
/// echte Bilddatei zu benötigen.
IfdTag _ratiosTag(List<Ratio> ratios) => IfdTag(
      tag: 0,
      tagType: 'Ratio',
      printable: ratios.toString(),
      values: IfdRatios(ratios),
    );

IfdTag _asciiTag(String value) => IfdTag(
      tag: 0,
      tagType: 'ASCII',
      printable: value,
      values: const IfdNone(),
    );

void main() {
  test('Nordhalbkugel/Osthalbkugel ergibt positive Dezimalgrade', () {
    // 51° 30' 0" N, 0° 7' 0" E ≈ London
    final tags = {
      'GPS GPSLatitude': _ratiosTag([Ratio(51, 1), Ratio(30, 1), Ratio(0, 1)]),
      'GPS GPSLatitudeRef': _asciiTag('N'),
      'GPS GPSLongitude': _ratiosTag([Ratio(0, 1), Ratio(7, 1), Ratio(0, 1)]),
      'GPS GPSLongitudeRef': _asciiTag('E'),
    };

    final result = parseExifGps(tags);

    expect(result, isNotNull);
    expect(result!.latitude, closeTo(51.5, 1e-9));
    expect(result.longitude, closeTo(0.1166666667, 1e-6));
  });

  test('Südhalbkugel/Westhalbkugel wird korrekt negativ', () {
    // 33° 52' 4" S, 70° 40' 0" W ≈ Santiago de Chile
    final tags = {
      'GPS GPSLatitude': _ratiosTag([Ratio(33, 1), Ratio(52, 1), Ratio(4, 1)]),
      'GPS GPSLatitudeRef': _asciiTag('S'),
      'GPS GPSLongitude': _ratiosTag([Ratio(70, 1), Ratio(40, 1), Ratio(0, 1)]),
      'GPS GPSLongitudeRef': _asciiTag('W'),
    };

    final result = parseExifGps(tags);

    expect(result, isNotNull);
    expect(result!.latitude, lessThan(0));
    expect(result.longitude, lessThan(0));
    expect(result.latitude, closeTo(-33.8677778, 1e-6));
    expect(result.longitude, closeTo(-70.6666667, 1e-6));
  });

  test('fehlende GPS-Tags ergeben null statt eines Fehlers', () {
    expect(parseExifGps(const {}), isNull);
  });

  test('unvollständige Ratios (weniger als 3) ergeben null', () {
    final tags = {
      'GPS GPSLatitude': _ratiosTag([Ratio(51, 1), Ratio(30, 1)]),
      'GPS GPSLatitudeRef': _asciiTag('N'),
      'GPS GPSLongitude': _ratiosTag([Ratio(0, 1), Ratio(7, 1), Ratio(0, 1)]),
      'GPS GPSLongitudeRef': _asciiTag('E'),
    };

    expect(parseExifGps(tags), isNull);
  });

  test('unplausible Koordinaten außerhalb des gültigen Bereichs ergeben null', () {
    // 200° Breite ist geometrisch unmöglich – schützt vor kaputten EXIF-Blöcken.
    final tags = {
      'GPS GPSLatitude': _ratiosTag([Ratio(200, 1), Ratio(0, 1), Ratio(0, 1)]),
      'GPS GPSLatitudeRef': _asciiTag('N'),
      'GPS GPSLongitude': _ratiosTag([Ratio(0, 1), Ratio(7, 1), Ratio(0, 1)]),
      'GPS GPSLongitudeRef': _asciiTag('E'),
    };

    expect(parseExifGps(tags), isNull);
  });
}
