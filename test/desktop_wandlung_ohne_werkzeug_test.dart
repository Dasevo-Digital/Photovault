import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/platform/desktop_image_tools.dart';

/// Die Bildwandlung unter Linux und Windows für das, was Dart selbst
/// liest – JPEG, PNG und Verwandte.
///
/// Bis hierher ging auch ein JPEG an dcraw_emu, und das lehnt es ab. Die
/// Wandlung lieferte nichts; der Export in kleinerer Grösse kopierte das
/// Original, der Datenschutzexport scheiterte an jedem gewöhnlichen Foto.
/// Der Weg braucht kein Werkzeug und läuft deshalb auf jeder Plattform.
void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('pv_dartwandlung_'));
  tearDown(() => temp.deleteSync(recursive: true));

  /// Gespeichert quer, links rot und rechts blau – laut EXIF um 90° im
  /// Uhrzeigersinn zu drehen, mit Aufnahmeort.
  img.Image vorlage() {
    final bild = img.Image(width: 300, height: 200);
    for (var y = 0; y < 200; y++) {
      for (var x = 0; x < 300; x++) {
        bild.setPixelRgb(x, y, x < 150 ? 220 : 0, 0, x < 150 ? 0 : 220);
      }
    }
    bild.exif.imageIfd.orientation = 6;
    bild.exif.gpsIfd.gpsLatitude = 52.370216;
    bild.exif.gpsIfd.gpsLongitude = 9.735603;
    return bild;
  }

  test(
    'ein JPEG wird gedreht, verkleinert und verliert seinen Anhang',
    () async {
      final datei = File(p.join(temp.path, 'a.jpg'))
        ..writeAsBytesSync(img.encodeJpg(vorlage(), quality: 95));
      final aus = await DesktopImageTools.convertToJpeg(
        datei,
        maxDimension: 150,
      );
      expect(aus, isNotNull);
      final bild = img.decodeJpg(aus!)!;
      expect(
        [bild.width, bild.height],
        [100, 150],
        reason: 'hoch, verkleinert',
      );
      // Gedreht um 90° im Uhrzeigersinn: Was links war, ist jetzt oben.
      final oben = bild.getPixel(50, 20);
      final unten = bild.getPixel(50, 130);
      expect(oben.r, greaterThan(150), reason: 'rot oben');
      expect(unten.b, greaterThan(150), reason: 'blau unten');
      expect(bild.exif.gpsIfd.gpsLatitude, isNull);
      expect(bild.exif.imageIfd.orientation ?? 1, 1);
    },
  );

  test('ein PNG wird ein JPEG', () async {
    final datei = File(p.join(temp.path, 'b.png'))
      ..writeAsBytesSync(img.encodePng(img.Image(width: 400, height: 300)));
    final aus = await DesktopImageTools.convertToJpeg(datei, maxDimension: 200);
    final bild = img.decodeJpg(aus!)!;
    expect([bild.width, bild.height], [200, 150]);
  });

  test(
    'was sich nicht lesen lässt, ergibt nichts statt eines Fehlers',
    () async {
      final datei = File(p.join(temp.path, 'kaputt.jpg'))
        ..writeAsBytesSync([0xFF, 0xD8, 0, 1, 2, 3]);
      expect(
        await DesktopImageTools.convertToJpeg(datei, maxDimension: 200),
        isNull,
      );
    },
  );
}
