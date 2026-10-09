import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/services/kratzersuche.dart';

/// Kratzer und Staub – an gemalten Bildern, bei denen feststeht, wo sie
/// liegen.
void main() {
  /// Ein ruhiger Verlauf mit etwas Rauschen, wie ein gescannter Himmel.
  img.Image grund(int w, int h) {
    final z = math.Random(7);
    final b = img.Image(width: w, height: h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final v = (90 + 60 * y / h + z.nextInt(5)).round();
        b.setPixelRgb(x, y, v, v, v + 10);
      }
    }
    return b;
  }

  bool markiert(img.Image m, int x, int y) => m.getPixel(x, y).r > 0;
  int flaeche(img.Image m) => m.where((p) => p.r > 0).length;

  test('ein langer heller Kratzer wird gefunden, der Rest nicht', () {
    final b = grund(600, 400);
    img.drawLine(
      b,
      x1: 50,
      y1: 40,
      x2: 520,
      y2: 330,
      color: img.ColorRgb8(245, 245, 245),
    );
    final f = sucheKratzer(b);
    expect(f.kratzer, 1);
    expect(markiert(f.maske, 285, 185), isTrue, reason: 'Mitte der Linie');
    expect(markiert(f.maske, 300, 100), isFalse, reason: 'freie Fläche');
    expect(flaeche(f.maske), lessThan(600 * 400 * 0.03));
    expect(f.maske.width, 600);
  });

  test('dunkle Staubkörner auf ruhiger Fläche', () {
    final b = grund(400, 300);
    for (final (x, y) in [(60, 50), (200, 150), (330, 240)]) {
      img.fillCircle(
        b,
        x: x,
        y: y,
        radius: 2,
        color: img.ColorRgb8(20, 20, 20),
      );
    }
    final f = sucheKratzer(b);
    expect(f.staub, 3);
    expect(f.kratzer, 0);
    expect(markiert(f.maske, 200, 150), isTrue);
  });

  test('ein Kreis ist kein Kratzer, eine unruhige Fläche kein Staub', () {
    final b = grund(400, 300);
    img.drawCircle(
      b,
      x: 120,
      y: 150,
      radius: 50,
      color: img.ColorRgb8(240, 240, 240),
    );
    // Grobkörnige Struktur wie Laub: viele helle Punkte dicht an dicht.
    final z = math.Random(3);
    for (var i = 0; i < 400; i++) {
      final x = 260 + z.nextInt(120), y = 60 + z.nextInt(180);
      b.setPixelRgb(x, y, 250, 250, 250);
      b.setPixelRgb(x + 1, y, 10, 10, 10);
    }
    final f = sucheKratzer(b);
    expect(f.kratzer, 0);
    expect(markiert(f.maske, 170, 150), isFalse, reason: 'Kreisrand');
    // Im Laub darf kaum etwas als Staub durchgehen.
    var imLaub = 0;
    for (var y = 60; y < 240; y++) {
      for (var x = 260; x < 380; x++) {
        if (markiert(f.maske, x, y)) imLaub++;
      }
    }
    expect(imLaub, lessThan(120 * 180 * 0.05));
  });

  test(
    'grosse Bilder werden verkleinert gesucht, die Maske hat volle Grösse',
    () {
      final b = grund(3200, 400);
      img.drawLine(
        b,
        x1: 100,
        y1: 200,
        x2: 3100,
        y2: 210,
        color: img.ColorRgb8(250, 250, 250),
        thickness: 2,
      );
      final f = sucheKratzer(b);
      expect(f.maske.width, 3200);
      expect(f.kratzer, 1);
      expect(markiert(f.maske, 1600, 205), isTrue);
    },
  );
}
