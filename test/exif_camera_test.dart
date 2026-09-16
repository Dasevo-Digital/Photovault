import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/exif_camera.dart';

IfdTag _ratiosTag(List<Ratio> ratios) => IfdTag(
      tag: 0,
      tagType: 'Ratio',
      printable: ratios.toString(),
      values: IfdRatios(ratios),
    );

IfdTag _intsTag(List<int> ints) => IfdTag(
      tag: 0,
      tagType: 'Short',
      printable: ints.toString(),
      values: IfdInts(ints),
    );

IfdTag _asciiTag(String value) => IfdTag(
      tag: 0,
      tagType: 'ASCII',
      printable: value,
      values: const IfdNone(),
    );

void main() {
  test('liest Hersteller, Modell und Objektiv als Klartext-Strings', () {
    final tags = {
      'Image Make': _asciiTag('Canon'),
      'Image Model': _asciiTag('Canon EOS R5'),
      'EXIF LensModel': _asciiTag('RF24-105mm F4 L IS USM'),
    };

    final info = parseExifCameraInfo(tags);

    expect(info.make, 'Canon');
    expect(info.model, 'Canon EOS R5');
    expect(info.lensModel, 'RF24-105mm F4 L IS USM');
    expect(info.isEmpty, isFalse);
  });

  test('rechnet Brennweite/Blende aus dem Bruch statt den gekürzten Bruch als Text zu übernehmen', () {
    // f/2.8 wird oft als 28/10 gespeichert, kürzt sich aber auf 14/5 –
    // .printable würde "14/5" liefern statt der Dezimalzahl 2.8.
    final tags = {
      'EXIF FocalLength': _ratiosTag([Ratio(505, 10)]), // 50.5 mm
      'EXIF FNumber': _ratiosTag([Ratio(28, 10)]), // f/2.8, kürzt sich auf 14/5
    };

    final info = parseExifCameraInfo(tags);

    expect(info.focalLengthMm, closeTo(50.5, 1e-9));
    expect(info.fNumber, closeTo(2.8, 1e-9));
  });

  test('liest ISO sowohl aus ISOSpeedRatings (Int) als auch als Fallback aus ISOSpeed', () {
    final infoFromRatings = parseExifCameraInfo({'EXIF ISOSpeedRatings': _intsTag([400])});
    expect(infoFromRatings.iso, 400);

    final infoFromFallback = parseExifCameraInfo({'EXIF ISOSpeed': _intsTag([800])});
    expect(infoFromFallback.iso, 800);
  });

  test('liest die Belichtungszeit als Sekunden-Dezimalzahl', () {
    final tags = {'EXIF ExposureTime': _ratiosTag([Ratio(1, 500)])};
    final info = parseExifCameraInfo(tags);
    expect(info.exposureTimeSeconds, closeTo(1 / 500, 1e-9));
  });

  test('fehlende Tags ergeben eine komplett leere CameraInfo statt eines Fehlers', () {
    final info = parseExifCameraInfo(const {});
    expect(info.isEmpty, isTrue);
    expect(info.make, isNull);
    expect(info.focalLengthMm, isNull);
  });

  test('leere/nur aus Leerzeichen bestehende Strings werden wie fehlend behandelt', () {
    final tags = {'Image Make': _asciiTag('   ')};
    final info = parseExifCameraInfo(tags);
    expect(info.make, isNull);
  });
}
