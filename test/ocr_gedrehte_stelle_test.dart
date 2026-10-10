import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/services/ocr_service.dart';

/// Die Lage einer Textzeile aus ihrem Fleck in der Wahrscheinlichkeitskarte
/// und das Ausschneiden entlang dieser Lage – ohne Modell.
void main() {
  /// Die Punkte eines gefüllten Rechtecks der Länge [l] und Höhe [h], um
  /// [grad] gedreht, mit der Mitte bei ([mx], [my]) in einer Karte der
  /// Breite [breite].
  Int32List rechteck(
    double mx,
    double my,
    double l,
    double h,
    double grad,
    int breite,
    int hoehe,
  ) {
    final w = grad * math.pi / 180;
    final punkte = <int>[];
    for (var y = 0; y < hoehe; y++) {
      for (var x = 0; x < breite; x++) {
        final dx = x + 0.5 - mx, dy = y + 0.5 - my;
        final u = dx * math.cos(w) + dy * math.sin(w);
        final v = -dx * math.sin(w) + dy * math.cos(w);
        if (u.abs() <= l / 2 && v.abs() <= h / 2) punkte.add(y * breite + x);
      }
    }
    return Int32List.fromList(punkte);
  }

  test('eine geneigte Zeile behält ihre Neigung und ihre Höhe', () {
    final s = stelleAusFleck(
      rechteck(150, 60, 200, 12, 5, 300, 120),
      300,
      1,
      1,
      0,
    );
    expect(s.neigung, closeTo(5, 0.3));
    expect(s.laenge, closeTo(200, 3));
    expect(s.hoehe, closeTo(12, 2));
    // Achsenparallel wäre der Kasten fast 30 Punkte hoch.
    expect(s.unten(120) - s.oben(120), greaterThan(25));
  });

  test('eine gerade Zeile ergibt denselben Kasten wie bisher', () {
    // 40 × 6 Punkte ab (10, 20); bisher: aufgeweitet um
    // 40·6·1,8 / (2·46) = 4,7 → 5 auf jeder Seite.
    final punkte = Int32List.fromList([
      for (var y = 20; y < 26; y++)
        for (var x = 10; x < 50; x++) y * 100 + x,
    ]);
    final s = stelleAusFleck(punkte, 100, 1, 1, 1.8);
    expect(s.neigung, 0);
    expect(s.links(100), 10 - 5);
    expect(s.rechts(100), 49 + 5);
    expect(s.oben(100), 20 - 5);
    expect(s.unten(100), 25 + 5);
  });

  test('ein fast runder Fleck bekommt keine Richtung', () {
    final s = stelleAusFleck(rechteck(30, 30, 14, 10, 20, 60, 60), 60, 1, 1, 0);
    expect(s.neigung, 0);
  });

  test('steiler als 45° bleibt achsenparallel', () {
    final s = stelleAusFleck(
      rechteck(60, 60, 100, 8, 70, 120, 120),
      120,
      1,
      1,
      0,
    );
    expect(s.neigung, 0);
  });

  test('der Weg zurück aufs Original streckt beide Achsen', () {
    final s = stelleAusFleck(rechteck(50, 30, 80, 8, 4, 100, 60), 100, 3, 3, 0);
    expect(s.laenge, closeTo(240, 9));
    expect(s.neigung, closeTo(4, 0.4));
  });

  test('ausgeschnitten steht eine geneigte Linie waagerecht', () {
    // Weisses Bild, eine dunkle Linie mit 6° Neigung.
    final bild = img.Image(width: 400, height: 200)
      ..clear(img.ColorRgb8(255, 255, 255));
    final w = 6 * math.pi / 180;
    img.drawLine(
      bild,
      x1: 50,
      y1: 80,
      x2: 50 + (300 * math.cos(w)).round(),
      y2: 80 + (300 * math.sin(w)).round(),
      color: img.ColorRgb8(0, 0, 0),
      thickness: 3,
    );
    final s = OcrStelle(
      50 - 10 * math.sin(w) * -1,
      80 - 10 * math.cos(w),
      300 * math.cos(w),
      300 * math.sin(w),
      -20 * math.sin(w),
      20 * math.cos(w),
    );
    final aus = richteStelleAus(bild, s, 300, 20);
    // In jeder Spalte liegt das Dunkelste in derselben Zeile – der Mitte.
    final zeilen = <int>{};
    for (var x = 20; x < 280; x += 10) {
      var dunkel = 0;
      for (var y = 1; y < 20; y++) {
        if (aus.getPixel(x, y).r < aus.getPixel(x, dunkel).r) dunkel = y;
      }
      zeilen.add(dunkel);
    }
    expect(zeilen.reduce(math.max) - zeilen.reduce(math.min), lessThan(3));
    expect(zeilen.first, inInclusiveRange(8, 12));
  });

  group('Stücke einer Zeile', () {
    /// Ein waagerechter Fleck von [x0] bis [x1] und [y0] bis [y1] in einer
    /// Karte der Breite 400.
    Int32List fleck(int x0, int x1, int y0, int y1) => Int32List.fromList([
      for (var y = y0; y < y1; y++)
        for (var x = x0; x < x1; x++) y * 400 + x,
    ]);

    test('eine Lücke von einer Zeilenhöhe verbindet', () {
      final f = fuegeZeilenZusammen([
        fleck(10, 110, 20, 30),
        fleck(120, 160, 20, 30),
      ], 400);
      expect(f, hasLength(1));
      expect(f.single, hasLength(100 * 10 + 40 * 10));
    });

    test('eine weite Lücke trennt – zwei Spalten bleiben zwei', () {
      expect(
        fuegeZeilenZusammen([
          fleck(10, 110, 20, 30),
          fleck(140, 200, 20, 30),
        ], 400),
        hasLength(2),
      );
    });

    test('übereinander liegende Zeilen bleiben getrennt', () {
      expect(
        fuegeZeilenZusammen([
          fleck(10, 110, 20, 30),
          fleck(10, 110, 36, 46),
        ], 400),
        hasLength(2),
      );
    });

    test('eine Überschrift neben kleiner Schrift bleibt getrennt', () {
      expect(
        fuegeZeilenZusammen([
          fleck(10, 110, 20, 40),
          fleck(115, 160, 28, 36),
        ], 400),
        hasLength(2),
      );
    });

    test('auch geneigt wird die Fortsetzung gefunden', () {
      // Zwei Stücke derselben, um 4° geneigten Zeile.
      final w = 4 * math.pi / 180;
      Int32List stueck(double von, double bis) {
        final punkte = <int>{};
        for (var u = von; u <= bis; u += 0.25) {
          for (var v = -5.0; v <= 5; v += 0.25) {
            final x = (20 + u * math.cos(w) - v * math.sin(w)).floor();
            final y = (40 + u * math.sin(w) + v * math.cos(w)).floor();
            punkte.add(y * 400 + x);
          }
        }
        return Int32List.fromList(punkte.toList());
      }

      expect(
        fuegeZeilenZusammen([stueck(0, 200), stueck(212, 300)], 400),
        hasLength(1),
      );
    });
  });
}
