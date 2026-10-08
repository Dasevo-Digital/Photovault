import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/services/kolorieren.dart';

/// Das Einfärben ohne Modell: Eingabe und Zusammensetzen.
void main() {
  const n = KolorierService.modellGroesse;

  test('die Eingabe ist ein Graubild in 0..1, alle drei Kanäle gleich', () {
    final bild = img.Image(width: 40, height: 20)
      ..clear(img.ColorRgb8(200, 30, 30));
    final e = koloriereingabe(bild);
    expect(e.length, 3 * n * n);
    expect(e[0], e[n * n]);
    expect(e[0], e[2 * n * n]);
    expect(e[0], inInclusiveRange(0.0, 1.0));
    // Weiss bleibt weiss, Schwarz schwarz.
    final weiss = koloriereingabe(
      img.Image(width: 8, height: 8)..clear(img.ColorRgb8(255, 255, 255)),
    );
    expect(weiss[0], closeTo(1.0, 0.001));
  });

  test('ohne Farbe (a = b = 0) bleibt ein Graubild grau und gleich hell', () {
    final grau = img.Image(width: 30, height: 30)
      ..clear(img.ColorRgb8(120, 120, 120));
    final ergebnis = eingefaerbt(grau, Float32List(2 * n * n));
    final p = ergebnis.getPixel(15, 15);
    expect(p.r, closeTo(120, 1));
    expect(p.g, closeTo(120, 1));
    expect(p.b, closeTo(120, 1));
    expect(ergebnis.width, 30, reason: 'volle Auflösung bleibt');
  });

  test('positives a färbt rötlich, negatives b bläulich', () {
    final grau = img.Image(width: 10, height: 10)
      ..clear(img.ColorRgb8(128, 128, 128));
    final ab = Float32List(2 * n * n);
    for (var i = 0; i < n * n; i++) {
      ab[i] = 40; // a: rot
    }
    final rot = eingefaerbt(grau, ab).getPixel(5, 5);
    expect(rot.r, greaterThan(rot.g + 30));
    final ab2 = Float32List(2 * n * n);
    for (var i = 0; i < n * n; i++) {
      ab2[n * n + i] = -40; // b: blau
    }
    final blau = eingefaerbt(grau, ab2).getPixel(5, 5);
    expect(blau.b, greaterThan(blau.r + 30));
  });
}
