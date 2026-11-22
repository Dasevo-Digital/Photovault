import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kern/services/weissabgleich.dart';

double _linear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
double _srgb(double c) => c <= 0.0031308
    ? c * 12.92
    : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;

/// Die Rechnung bis Schema 101 (höher = kühler), wie sie in Shader,
/// Browser und ImageConverter.swift stand – der Bezug für die Umrechnung.
List<double> _alteFaktoren(double kelvin, double tint) {
  final t = kelvin.clamp(2000.0, 12000.0) / 6500;
  return [
    math.pow(1 / t, 0.55).toDouble(),
    1 - tint / 400,
    math.pow(t, 0.55).toDouble(),
  ];
}

List<double> _render(List<double> linear, double kelvin, double tint) {
  final g = weissabgleichFaktoren(kelvin, tint);
  return [
    _srgb(linear[0] * g.r),
    _srgb(linear[1] * g.g),
    _srgb(linear[2] * g.b),
  ];
}

void main() {
  group('Richtung wie in Lightroom (#466)', () {
    test('unter 6500 K blauer, darüber gelber', () {
      final kalt = weissabgleichFaktoren(3000, 0);
      expect(kalt.b, greaterThan(1));
      expect(kalt.r, lessThan(1));
      final warm = weissabgleichFaktoren(10000, 0);
      expect(warm.r, greaterThan(1));
      expect(warm.b, lessThan(1));
      final neutral = weissabgleichFaktoren(neutraleTemperatur, 0);
      expect([neutral.r, neutral.g, neutral.b], [1.0, 1.0, 1.0]);
    });

    test('die Enden wirken gleich stark', () {
      expect(temperaturMin * temperaturMax, neutraleTemperatur * 6500);
      final blau = weissabgleichFaktoren(temperaturMin, 0);
      final gelb = weissabgleichFaktoren(temperaturMax, 0);
      expect(blau.b, closeTo(gelb.r, 1e-12));
      expect(blau.r, closeTo(gelb.b, 1e-12));
    });
  });

  group('Umrechnung gespeicherter Werte', () {
    test('ergibt genau die frühere Wirkung', () {
      for (var alt = 1000.0; alt <= 16000; alt += 37.5) {
        final neu = weissabgleichFaktoren(
          temperaturAusFruehererBedeutung(alt),
          25,
        );
        final vorher = _alteFaktoren(alt, 25);
        expect(neu.r, closeTo(vorher[0], 1e-12), reason: '$alt K');
        expect(neu.g, closeTo(vorher[1], 1e-12), reason: '$alt K');
        expect(neu.b, closeTo(vorher[2], 1e-12), reason: '$alt K');
      }
    });

    test('jeder frühere Wert liegt danach im Reglerbereich', () {
      for (var alt = 0.0; alt <= 30000; alt += 50) {
        expect(
          temperaturAusFruehererBedeutung(alt),
          inInclusiveRange(temperaturMin, temperaturMax),
          reason: '$alt K',
        );
      }
    });

    test('feste Zahlen, auf jedem Gerät dieselben', () {
      // Eine Division in IEEE 754: Server, Rechner und Handy rechnen ihre
      // Kopien getrennt um und müssen bitgleich ankommen.
      expect(temperaturAusFruehererBedeutung(6500), 6500.0);
      expect(temperaturAusFruehererBedeutung(2000), 21125.0);
      expect(temperaturAusFruehererBedeutung(1500), 21125.0);
      expect(temperaturAusFruehererBedeutung(5200), 8125.0);
      expect(temperaturAusFruehererBedeutung(4000), 10562.5);
      expect(temperaturAusFruehererBedeutung(12000), 42250000 / 12000);
      expect(temperaturAusFruehererBedeutung(15000), 42250000 / 12000);
    });
  });

  group('Graupunkt', () {
    test('im Shader wird die Stelle mit einem Klick neutral', () {
      // Eine graue Karte unter warmem Licht, aus der Automatik.
      final szene = [_linear(0.55), _linear(0.5), _linear(0.44)];
      final n = weissabgleichFuer(0.55, 0.5, 0.44)!;
      final c = _render(szene, n.temperatur, n.toenung);
      expect(c[0], closeTo(c[1], 0.002));
      expect(c[1], closeTo(c[2], 0.002));
    });

    test('von einem schon gesetzten Regler aus ebenso', () {
      final szene = [_linear(0.52), _linear(0.48), _linear(0.5)];
      final vorher = _render(szene, 8800, 20);
      final n = weissabgleichFuer(
        vorher[0],
        vorher[1],
        vorher[2],
        temperatur: 8800,
        toenung: 20,
      )!;
      final c = _render(szene, n.temperatur, n.toenung);
      expect(c[0], closeTo(c[1], 0.002));
      expect(c[1], closeTo(c[2], 0.002));
    });

    test('Grau ändert nichts', () {
      final n = weissabgleichFuer(0.5, 0.5, 0.5)!;
      expect(n.temperatur, closeTo(6500, 0.01));
      expect(n.toenung, closeTo(0, 0.01));
    });

    test('zu warm: tiefer (blauer), zu kalt: höher (gelber)', () {
      // Kunstlicht macht die Stelle gelb-rot; ausgeglichen wird es wie in
      // Lightroom mit einer niedrigen Zahl.
      expect(weissabgleichFuer(0.7, 0.5, 0.3)!.temperatur, lessThan(6500));
      expect(weissabgleichFuer(0.3, 0.5, 0.7)!.temperatur, greaterThan(6500));
    });

    test('grünstichig heisst ein höherer Farbstich', () {
      expect(weissabgleichFuer(0.45, 0.6, 0.45)!.toenung, greaterThan(0));
    });

    test('fast schwarz oder ausgebrannt taugt nicht', () {
      expect(weissabgleichFuer(0.01, 0.2, 0.2), isNull);
      expect(weissabgleichFuer(1, 0.9, 0.8), isNull);
    });

    test('bleibt in den Grenzen der Regler', () {
      final n = weissabgleichFuer(0.96, 0.05, 0.04)!;
      expect(n.temperatur, inInclusiveRange(temperaturMin, temperaturMax));
      expect(n.toenung, inInclusiveRange(-100, 100));
      final m = weissabgleichFuer(0.04, 0.05, 0.96)!;
      expect(m.temperatur, inInclusiveRange(temperaturMin, temperaturMax));
    });
  });

  group('alle Renderwege rechnen gleich (#356, #466)', () {
    String lies(String pfad) => File(pfad).readAsStringSync();

    /// Der Rumpf von `whiteBalanceGain`, ohne Kommentare und Leerraum.
    String rumpf(String quelle) {
      final anfang = quelle.indexOf('vec3 whiteBalanceGain(');
      expect(anfang, greaterThanOrEqualTo(0));
      final ende = quelle.indexOf('\n}', anfang);
      return quelle
          .substring(anfang, ende)
          .split('\n')
          .map((z) => z.replaceFirst(RegExp(r'//.*'), ''))
          .join()
          .replaceAll(RegExp(r'\s+'), '');
    }

    final grenze = temperaturMax.toStringAsFixed(1);

    test('Shader: Rot t^0.55, Blau t^-0.55, Grenzen aus dem Kern', () {
      final shader = rumpf(lies('shaders/develop_adjustments.frag'));
      expect(shader, contains('clamp(kelvin,2000.0,$grenze)/6500.0'));
      expect(shader, contains('floatr=pow(t,0.55);'));
      expect(shader, contains('floatb=pow(1.0/t,0.55);'));
      expect(shader, contains('/400.0'));
    });

    test('Browser rechnet wie der Shader', () {
      final browser = rumpf(lies('packages/server/web/entwickeln.js'));
      expect(browser, contains('clamp(kelvin,2000.0,$grenze)/6500.0'));
      expect(
        browser,
        contains(
          'returnvec3(pow(t,0.55),1.0-clamp(tint,-100.0,100.0)/400.0,'
          'pow(1.0/t,0.55));',
        ),
      );
    });

    test('Browser: Reglerbereich wie am Rechner', () {
      final js = lies('packages/server/web/entwickeln.js');
      final zeile = js
          .split('\n')
          .singleWhere((z) => z.contains("spalte: 'temperature'"));
      expect(zeile, contains('min: ${temperaturMin.toInt()},'));
      expect(zeile, contains('max: ${temperaturMax.toInt()},'));
      expect(zeile, contains('vorgabe: 6500'));
      expect(zeile, contains('verlauf: true'));
    });

    test('Mac rechnet wie der Shader', () {
      final mac = lies('macos/Runner/ImageConverter.swift');
      final anfang = mac.indexOf('private static func weissabgleich(');
      final teil = mac.substring(anfang, mac.indexOf('\n    }\n', anfang));
      expect(
        teil,
        contains(
          'min(max(temperature, 2000), ${temperaturMax.toInt()})) / 6500',
        ),
      );
      expect(
        teil,
        contains(
          'CIVector(x: CGFloat(pow(t, 0.55)), y: 0, z: 0, w: 0), '
          'forKey: "inputRVector"',
        ),
      );
      expect(
        teil,
        contains(
          'CIVector(x: 0, y: 0, z: CGFloat(pow(1 / t, 0.55)), w: 0), '
          'forKey: "inputBVector"',
        ),
      );
      expect(teil, contains('1 - tint / 400'));
    });

    test('auf dem Mac gilt kein eigener Weissabgleich mehr', () {
      final mac = lies('macos/Runner/ImageConverter.swift');
      expect(mac, isNot(contains('filter.neutralTemperature =')));
      expect(mac, isNot(contains('filter.neutralTint =')));
      expect(mac, isNot(contains('"CITemperatureAndTint"')));
    });
  });
}
