import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/widgets/bild_zoom_gesten.dart';

/// **Zoomen mit einer Magic Mouse.**
///
/// Aus dem Erstlauf-Bericht (C10): "mit trackpad funktioniert zwei
/// finger zoom, mit magic mouse nicht". Eine Magic Mouse hat kein Rad
/// und keine zwei Finger zum Kneifen - sie kennt nur das Wischen.
void main() {
  group('Die Wischrechnung', () {
    test('nach oben wischen vergroessert', () {
      // In Flutter waechst y nach unten: Ein Wisch nach oben ist negativ.
      final neu = bildWischZoom(
          startZoom: 1, wischWegY: -200, kleinster: 0.1, groesster: 8);
      expect(neu, greaterThan(1));
    });

    test('nach unten wischen verkleinert', () {
      final neu = bildWischZoom(
          startZoom: 2, wischWegY: 200, kleinster: 0.1, groesster: 8);
      expect(neu, lessThan(2));
    });

    test('gleiche Wege ergeben gleiche Spruenge, egal wo man steht', () {
      // Der Zoom ist ein Faktor, keine Stufe. Ein Wisch von 100 Punkten
      // soll bei 1,0 dasselbe Verhaeltnis ergeben wie bei 4,0 - sonst
      // fuehlt sich die Geste weit hineingezoomt zaeh an.
      final vonEins = bildWischZoom(
          startZoom: 1, wischWegY: -100, kleinster: 0.01, groesster: 100);
      final vonVier = bildWischZoom(
          startZoom: 4, wischWegY: -100, kleinster: 0.01, groesster: 100);
      expect(vonVier / 4, closeTo(vonEins / 1, 1e-9));
    });

    test('ein Wisch ohne Weg laesst alles, wie es ist', () {
      expect(
          bildWischZoom(
              startZoom: 1.7, wischWegY: 0, kleinster: 0.1, groesster: 8),
          closeTo(1.7, 1e-9));
    });

    test('die Grenzen halten', () {
      expect(
          bildWischZoom(
              startZoom: 1, wischWegY: -5000, kleinster: 0.1, groesster: 8),
          8);
      expect(
          bildWischZoom(
              startZoom: 1, wischWegY: 5000, kleinster: 0.1, groesster: 8),
          0.1);
    });
  });

  group('Welche Taste den Zoom auslöst', () {
    test('ohne Taste nicht', () {
      expect(zoomtaste(const {}), isFalse);
      expect(zoomtaste({LogicalKeyboardKey.shiftLeft}), isFalse);
    });

    test('Command und Strg beide', () {
      // Beide auf jeder Plattform: Eine externe Tastatur an einem Mac
      // meldet je nach Belegung das eine oder das andere.
      expect(zoomtaste({LogicalKeyboardKey.metaLeft}), isTrue);
      expect(zoomtaste({LogicalKeyboardKey.controlRight}), isTrue);
    });
  });
}
