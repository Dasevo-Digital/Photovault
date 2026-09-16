import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/standort_parser.dart';

/// Gegen die echte Ausgabeform von `pv_standort.exe`, abgenommen am
/// 25.08.2026 auf dem Windows-Testrechner. Gemessen wurden dort 19 m
/// behauptete Genauigkeit bei 15 m tatsächlicher Abweichung gegen die
/// GPS-Daten der Bibliothek.
///
/// **Die Koordinaten in der Musterdatei sind ersetzt** – sie zeigen aufs
/// Brandenburger Tor. Die Form ist echt, der Ort nicht: Dieses Verzeichnis
/// wird öffentlich gespiegelt, und der Wohnort dessen, der die Tests laufen
/// lässt, gehört nicht hinein.
void main() {
  group('Ortungsausgabe, echte Form', () {
    test('WLAN-Position wird übernommen', () {
      final roh =
          File('test/fixtures/werkzeuge/pv_standort_wifi.json').readAsStringSync();
      final ort = parseStandort(roh);
      expect(ort, isNotNull);
      expect(ort!.quelle, 'WiFi');
      expect(ort.genauigkeit, 19.0);
      // Brandenburger Tor - ein offensichtlich erfundener Ort.
      expect(ort.breite, closeTo(52.51627, 1e-5));
      expect(ort.laenge, closeTo(13.3777, 1e-5));
    });

    test('abschliessender Zeilenumbruch stört nicht', () {
      expect(parseStandort('{"breite":52.0,"laenge":10.0,'
          '"genauigkeit":19.0,"quelle":"WiFi"}\r\n'), isNotNull);
    });
  });

  group('was verworfen wird', () {
    // Der eigentliche Grund für diesen Parser. Windows liefert bei
    // fehlender WLAN-Abdeckung eine IP-Position und behauptet dazu eine
    // Genauigkeit, die es nicht einhält: In der Messung waren es 25 km
    // behauptet gegen 271 km tatsächlich. Ein Pin auf der Karte wäre eine
    // Lüge, der der Nutzer glaubt.
    test('IP-Position wird nicht durchgereicht', () {
      expect(
          parseStandort('{"breite":50.1109,"laenge":8.68213,'
              '"genauigkeit":25000.0,"quelle":"IPAddress"}'),
          isNull);
    });

    test('auch eine IP-Position mit schöner Genauigkeit nicht', () {
      // Die Herkunft entscheidet, nicht die behauptete Güte.
      expect(
          parseStandort('{"breite":50.1109,"laenge":8.68213,'
              '"genauigkeit":20.0,"quelle":"IPAddress"}'),
          isNull);
    });

    test('Default und Obfuscated gelten nicht als Messung', () {
      for (final q in ['Default', 'Obfuscated', 'Unknown']) {
        expect(parseStandort('{"breite":52.0,"laenge":10.0,'
            '"genauigkeit":30.0,"quelle":"$q"}'), isNull,
            reason: 'Quelle $q');
      }
    });

    test('WLAN, aber jenseits der Genauigkeitsgrenze', () {
      expect(
          parseStandort('{"breite":52.0,"laenge":10.0,'
              '"genauigkeit":${hoechsteGenauigkeitMeter + 1},"quelle":"WiFi"}'),
          isNull);
      // Genau auf der Grenze zählt noch.
      expect(
          parseStandort('{"breite":52.0,"laenge":10.0,'
              '"genauigkeit":$hoechsteGenauigkeitMeter,"quelle":"WiFi"}'),
          isNotNull);
    });

    test('Genauigkeit null oder negativ ist keine Angabe', () {
      for (final g in ['0', '-1']) {
        expect(parseStandort('{"breite":52.0,"laenge":10.0,'
            '"genauigkeit":$g,"quelle":"WiFi"}'), isNull, reason: 'g=$g');
      }
    });

    test('gemeldete Fehler des Helfers', () {
      for (final f in ['keine_erlaubnis', 'zeitgrenze', '0x80072ee7']) {
        expect(parseStandort('{"fehler":"$f"}'), isNull, reason: f);
      }
    });

    test('unmögliche Koordinaten', () {
      expect(
          parseStandort('{"breite":91.0,"laenge":10.0,'
              '"genauigkeit":19.0,"quelle":"WiFi"}'),
          isNull);
      expect(
          parseStandort('{"breite":52.0,"laenge":181.0,'
              '"genauigkeit":19.0,"quelle":"WiFi"}'),
          isNull);
    });

    test('kaputte oder leere Ausgabe wirft nicht', () {
      for (final t in ['', '   ', 'nicht als Programm erkannt', '[]', '{}',
        '{"breite":52.0}', 'null']) {
        expect(parseStandort(t), isNull, reason: 'Eingabe: "$t"');
      }
    });
  });
}
