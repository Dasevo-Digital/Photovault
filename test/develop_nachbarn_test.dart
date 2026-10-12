import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/develop_nachbarn.dart';
import 'package:photo_vault/services/native_image_converter.dart';

/// Die Zahlen hinter Schärfe, Rauschminderung, Klarheit und Vignette des
/// GPU-Wegs. Die Bildtests stehen in develop_render_test.dart.
void main() {
  test('der Klarheitsradius wächst mit dem Bild', () {
    expect(klarheitSigma(1600, 1067), 20);
    expect(klarheitSigma(1067, 1600), 20);
    // Beim Speichern (Kante 4096) dieselbe Fläche wie in der Vorschau.
    expect(klarheitSigma(4096, 2731), closeTo(51.2, 1e-9));
  });

  test('negative Klarheit ist halb so stark wie positive', () {
    expect(klarheitStaerke(1), 1.5);
    expect(klarheitStaerke(-1), -0.5);
    expect(klarheitStaerke(0), 0);
  });

  test('die Vignette trifft die gemessenen Werte von CIVignette', () {
    // Gemessen an einer grauen Fläche: Stärke 2 (Regler 1) ergibt am
    // Rand der kurzen Seite den Faktor 0,625, Stärke 1 den Faktor 0,790.
    expect(vignettenFaktor(1, 1), closeTo(0.625, 0.003));
    expect(vignettenFaktor(1, 0.5), closeTo(0.790, 0.003));
    expect(vignettenFaktor(0, 1), 1);
    // Negativ hellt im selben Mass auf, wie positiv abdunkelt.
    expect(
      vignettenFaktor(0.8, -0.6) * vignettenFaktor(0.8, 0.6),
      closeTo(1, 1e-12),
    );
  });

  test('nur die vier Regler verlangen die Nachbarstufen', () {
    expect(brauchtNachbarn(const DevelopAdjustments()), isFalse);
    expect(
      brauchtNachbarn(const DevelopAdjustments(exposure: 1, contrast: 0.3)),
      isFalse,
    );
    expect(brauchtNachbarn(const DevelopAdjustments(sharpness: 0.1)), isTrue);
    expect(
      brauchtNachbarn(const DevelopAdjustments(noiseReduction: 0.1)),
      isTrue,
    );
    expect(brauchtNachbarn(const DevelopAdjustments(clarity: -0.1)), isTrue);
    expect(brauchtNachbarn(const DevelopAdjustments(vignette: -0.1)), isTrue);
  });
}
