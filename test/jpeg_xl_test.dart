import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:kern/services/dateikennung.dart';
import 'package:kern/services/dateikopf.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/platform/desktop_image_tools.dart';
import 'package:path/path.dart' as p;

/// JPEG XL (#276): erkennen, Grösse und Angaben aus dem Kopf lesen,
/// wandeln.
///
/// Die Dateien unter `fixtures/jxl` stammen aus libjxl (über
/// `imagecodecs`): drei nackte Datenströme – klein in Achterschritten, eine
/// krumme Grösse, ein festes Seitenverhältnis 16:9 – und zwei im
/// Kastenformat, eine mit EXIF, eine mit geteiltem Datenstrom (`jxlp`).
void main() {
  File probe(String name) => File(p.join('test/fixtures/jxl', name));

  /// Nur der Kopf eines Datenstroms: frei gewählte Grösse und [lage].
  /// libjxl lässt die Lage über `imagecodecs` nicht setzen; der Kopf ist
  /// aber schnell gebaut – das niederwertigste Bit zuerst.
  File kopfMitLage(int breite, int hoehe, int lage) {
    final bits = <int>[];
    void schreib(int v, int n) {
      for (var i = 0; i < n; i++) {
        bits.add((v >> i) & 1);
      }
    }

    schreib(0x0AFF, 16); // FF 0A
    schreib(0, 1); // nicht klein
    schreib(3, 2); // 30 Bit
    schreib(hoehe - 1, 30);
    schreib(0, 3); // Breite frei
    schreib(3, 2);
    schreib(breite - 1, 30);
    schreib(0, 1); // all_default: nein
    schreib(1, 1); // extra_fields: ja
    schreib(lage - 1, 3);
    final bytes = Uint8List((bits.length + 7) ~/ 8 + 8);
    for (var i = 0; i < bits.length; i++) {
      bytes[i >> 3] |= bits[i] << (i & 7);
    }
    final f = File(
      p.join(Directory.systemTemp.createTempSync('pv_jxl_').path, 'k.jxl'),
    )..writeAsBytesSync(bytes);
    addTearDown(() => f.parent.deleteSync(recursive: true));
    return f;
  }

  group('erkennen', () {
    test('nackter Datenstrom und Kastenformat', () {
      expect(kennungAus(probe('klein_40x24.jxl').readAsBytesSync()), '.jxl');
      expect(
        kennungAus(probe('kasten_exif_64x48.jxl').readAsBytesSync()),
        '.jxl',
      );
    });

    test('JPEG bleibt JPEG, ein fremder Kasten ist kein JPEG XL', () {
      expect(kennungAus(const [0xFF, 0xD8, 0xFF, 0xE0]), '.jpg');
      expect(
        kennungAus([0, 0, 0, 0x0C, ...'JXL '.codeUnits, 0, 0, 0, 0]),
        isNull,
      );
    });

    test('wird importiert und gewandelt', () {
      expect(unterstuetzteEndungen, contains('.jxl'));
      expect(heicAndRawExtensions, contains('.jxl'));
    });
  });

  group('Grösse aus dem Kopf', () {
    test('wie libjxl sie schreibt', () {
      expect(leseOriginalmasse(probe('klein_40x24.jxl')), (
        breite: 40,
        hoehe: 24,
      ));
      expect(leseOriginalmasse(probe('gross_1001x777.jxl')), (
        breite: 1001,
        hoehe: 777,
      ));
      expect(leseOriginalmasse(probe('breit_1600x900.jxl')), (
        breite: 1600,
        hoehe: 900,
      ), reason: 'Breite als Seitenverhältnis 16:9');
      expect(leseOriginalmasse(probe('kasten_exif_64x48.jxl')), (
        breite: 64,
        hoehe: 48,
      ));
      expect(leseOriginalmasse(probe('kasten_geteilt_64x48.jxl')), (
        breite: 64,
        hoehe: 48,
      ), reason: 'erster Teil hinter vier Bytes Zählung');
    });

    test('ab Lage 5 sind Breite und Höhe vertauscht', () {
      expect(leseOriginalmasse(kopfMitLage(4000, 3000, 1)), (
        breite: 4000,
        hoehe: 3000,
      ));
      expect(leseOriginalmasse(kopfMitLage(4000, 3000, 3)), (
        breite: 4000,
        hoehe: 3000,
      ));
      expect(leseOriginalmasse(kopfMitLage(4000, 3000, 6)), (
        breite: 3000,
        hoehe: 4000,
      ));
      expect(leseOriginalmasse(kopfMitLage(4000, 3000, 8)), (
        breite: 3000,
        hoehe: 4000,
      ));
    });
  });

  group('EXIF', () {
    test('aus dem Kasten, lesbar für package:exif', () async {
      final tiff = leseJxlExif(probe('kasten_exif_64x48.jxl'));
      expect(tiff, isNotNull);
      final tags = await readExifFromBytes(tiff!);
      expect(tags['Image Make']?.printable, 'Testkamera');
      expect(tags['Image Model']?.printable, 'Modell X');
      expect(tags['EXIF DateTimeOriginal']?.printable, '2019:07:14 16:20:05');
    });

    test('ein nackter Datenstrom hat keine', () {
      expect(leseJxlExif(probe('klein_40x24.jxl')), isNull);
      expect(leseJxlExif(probe('kasten_geteilt_64x48.jxl')), isNull);
    });
  });

  group('wandeln', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('pv_jxl_'));
    tearDown(() {
      DesktopImageTools.vergissWerkzeuge();
      temp.deleteSync(recursive: true);
    });

    /// Ein `djxl`, das ein festes PNG an die Stelle seines zweiten
    /// Arguments legt und notiert, womit es gerufen wurde.
    String djxl(Uint8List png) {
      final antwort = File(p.join(temp.path, 'antwort.png'))
        ..writeAsBytesSync(png);
      final f = File(p.join(temp.path, 'djxl'))
        ..writeAsStringSync('''#!/bin/sh
printf '%s\\n' "\$@" > "${temp.path}/aufruf.txt"
cp "${antwort.path}" "\$2"
''');
      Process.runSync('chmod', ['+x', f.path]);
      return f.path;
    }

    test('ohne libvips über djxl, verkleinert', () async {
      DesktopImageTools.stelleWerkzeuge({
        'djxl': djxl(img.encodePng(img.Image(width: 200, height: 100))),
      });
      final quelle = probe('gross_1001x777.jxl');

      final r = await DesktopImageTools.convertToJpeg(quelle, maxDimension: 50);

      final aus = img.decodeJpg(r!)!;
      expect((aus.width, aus.height), (50, 25));
      final aufruf = File(p.join(temp.path, 'aufruf.txt')).readAsLinesSync();
      expect(aufruf.first, quelle.path);
      expect(p.extension(aufruf[1]), '.png');
    }, skip: Platform.isWindows ? 'Shell-Skript als Werkzeug' : false);

    test('ohne Werkzeug: nichts, und kein Absturz', () async {
      DesktopImageTools.stelleWerkzeuge({});
      expect(
        await DesktopImageTools.convertToJpeg(probe('klein_40x24.jxl')),
        isNull,
      );
    });
  });
}
