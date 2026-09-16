import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/raw_identify_parser.dart';

/// Gegen die ECHTE Ausgabe von `raw-identify -v`, abgenommen an einer
/// CC0-Musterdatei einer Canon EOS R10 (raw.pixls.us). Ein selbst
/// erfundener Beispieltext würde nur beweisen, dass der Parser die eigenen
/// Annahmen erfüllt.
void main() {
  final echt =
      File('test/fixtures/werkzeuge/raw_identify_eos_r10.txt').readAsStringSync();

  group('raw-identify, echte Ausgabe', () {
    test('Kamera samt Hersteller im Modellnamen', () {
      final d = parseRawIdentify(echt);
      // ImageIO auf macOS liefert für dieselbe Datei „Canon EOS R10".
      // Stünde hier „EOS R10", benännen zwei Plattformen dieselbe Kamera
      // verschieden – Kamera-Presets griffen dann je nach System.
      expect(d.kamera.model, 'Canon EOS R10');
      expect(d.kamera.make, 'Canon');
    });

    test('Objektiv aus dem EXIF-Abschnitt, nicht aus den Makernotes', () {
      // Makernotes führt dieselbe Angabe als „EF 50mm f/1.8 STM".
      expect(parseRawIdentify(echt).kamera.lensModel, 'EF50mm f/1.8 STM');
    });

    test('Aufnahmewerte', () {
      final k = parseRawIdentify(echt).kamera;
      expect(k.iso, 1600);
      expect(k.fNumber, closeTo(1.8, 0.001));
      expect(k.focalLengthMm, closeTo(50.0, 0.001));
      expect(k.exposureTimeSeconds, closeTo(1 / 100, 1e-9));
    });

    test('Zeitstempel', () {
      // „Fri Aug 19 19:19:28 2022" – ImageIO las an derselben Datei
      // 2022:08:19 19:19:28.
      expect(parseRawIdentify(echt).zeitpunkt, DateTime(2022, 8, 19, 19, 19, 28));
    });

    test('FocalLengthIn35mmFormat: 0 heisst „nicht überliefert", nicht 0 mm', () {
      expect(parseRawIdentify(echt).kamera.focalLength35mm, isNull);
    });

    test('Blitzkorrektur wird nicht als Belichtungskorrektur gelesen', () {
      // Die Ausgabe enthält „Flash exposure compensation: 0.00 EV".
      expect(echt, contains('Flash exposure compensation'));
      expect(parseRawIdentify(echt).kamera.exposureBiasEv, isNull);
    });
  });

  group('Randfälle', () {
    test('leere Ausgabe ergibt nichts, statt zu werfen', () {
      expect(parseRawIdentify('').isEmpty, isTrue);
    });

    test('Fehlermeldung statt Werten ergibt nichts', () {
      expect(parseRawIdentify('Cannot open file: No such file').isEmpty, isTrue);
    });

    test('Belichtung auch als Sekundenangabe', () {
      expect(parseRawIdentify('Shutter: 2.0 sec').kamera.exposureTimeSeconds,
          closeTo(2.0, 0.001));
    });

    test('Zeitstempel 1970 gilt als fehlend', () {
      // LibRaw setzt bei fehlendem Datum 0 ein.
      expect(parseRawIdentify('Timestamp: Thu Jan  1 01:00:00 1970').zeitpunkt,
          isNull);
    });

    test('Kamerakennung wird abgeschnitten', () {
      expect(parseRawIdentify('Camera: Nikon Z 6 ID: 0x123').kamera.model,
          'Nikon Z 6');
    });
  });
}
