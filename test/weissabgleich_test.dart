import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kern/services/weissabgleich.dart';

double _linear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
double _srgb(double c) => c <= 0.0031308
    ? c * 12.92
    : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;

/// Dieselbe Rechnung wie whiteBalanceGain im Shader.
List<double> _gain(double kelvin, double tint) {
  final t = kelvin / 6500;
  return [
    math.pow(1 / t, 0.55).toDouble(),
    1 - tint / 400,
    math.pow(t, 0.55).toDouble(),
  ];
}

List<double> _render(List<double> linear, double kelvin, double tint) {
  final g = _gain(kelvin, tint);
  return [for (var i = 0; i < 3; i++) _srgb(linear[i] * g[i])];
}

void main() {
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
    final vorher = _render(szene, 4800, 20);
    final n = weissabgleichFuer(
      vorher[0],
      vorher[1],
      vorher[2],
      temperatur: 4800,
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

  test('zu warm: höher, zu kalt: tiefer', () {
    expect(weissabgleichFuer(0.7, 0.5, 0.3)!.temperatur, greaterThan(6500));
    expect(weissabgleichFuer(0.3, 0.5, 0.7)!.temperatur, lessThan(6500));
  });

  test('grünstichig heisst ein höherer Farbstich', () {
    expect(weissabgleichFuer(0.45, 0.6, 0.45)!.toenung, greaterThan(0));
  });

  group('alle Renderwege rechnen gleich (#356)', () {
    String lies(String pfad) => File(pfad).readAsStringSync();

    test('Shader, Browser und Mac haben dieselben Faktoren', () {
      final shader = lies('shaders/develop_adjustments.frag');
      final browser = lies('packages/server/web/entwickeln.js');
      final mac = lies('macos/Runner/ImageConverter.swift');
      for (final q in [shader, browser]) {
        expect(q, contains('pow(1.0 / t, 0.55)'));
        expect(q, contains('pow(t, 0.55)'));
        expect(q, contains('/ 400.0'));
      }
      expect(mac, contains('pow(1 / t, 0.55)'));
      expect(mac, contains('pow(t, 0.55)'));
      expect(mac, contains('1 - tint / 400'));
    });

    test('auf dem Mac gilt kein eigener Weissabgleich mehr', () {
      final mac = lies('macos/Runner/ImageConverter.swift');
      expect(mac, isNot(contains('filter.neutralTemperature =')));
      expect(mac, isNot(contains('filter.neutralTint =')));
      expect(mac, isNot(contains('"CITemperatureAndTint"')));
    });
  });

  test('fast schwarz oder ausgebrannt taugt nicht', () {
    expect(weissabgleichFuer(0.01, 0.2, 0.2), isNull);
    expect(weissabgleichFuer(1, 0.9, 0.8), isNull);
  });

  test('bleibt in den Grenzen der Regler', () {
    final n = weissabgleichFuer(0.96, 0.05, 0.04)!;
    expect(n.temperatur, inInclusiveRange(2000, 12000));
    expect(n.toenung, inInclusiveRange(-100, 100));
  });
}
