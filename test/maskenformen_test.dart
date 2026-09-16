import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/services/vector_mask_service.dart';

/// Die beiden neuen Maskenformen: Rechteck und Auswahl nach
/// Farbähnlichkeit.
///
/// Eine Maske ist schwer anzusehen und leicht falsch: Ein vertauschtes
/// Achsenpaar oder eine verkehrte Weichzeichnung fällt am fertigen Bild
/// erst auf, wenn die Korrektur an der falschen Stelle sitzt. Deshalb wird
/// hier an einzelnen Bildpunkten gemessen.
void main() {
  int an(img.Image m, double nx, double ny) {
    final x = (nx * m.width).clamp(0, m.width - 1).toInt();
    final y = (ny * m.height).clamp(0, m.height - 1).toInt();
    return m.getPixel(x, y).r.toInt();
  }

  group('Rechteck', () {
    const mitte = RectangleShape(
      centerX: 0.5,
      centerY: 0.5,
      halfWidth: 0.25,
      halfHeight: 0.25,
      feather: 0,
    );

    test('innen ausgewählt, aussen nicht', () {
      final m = rasterizeMaskShape(mitte, 100, 100);
      expect(an(m, 0.5, 0.5), 255);
      expect(an(m, 0.3, 0.5), 255, reason: 'knapp innerhalb der linken Kante');
      expect(an(m, 0.1, 0.5), 0);
      expect(an(m, 0.5, 0.1), 0);
    });

    test('die Ecken gehören dazu – anders als bei der Ellipse', () {
      // Der eigentliche Unterschied zwischen den beiden Formen. Wäre hier
      // versehentlich die euklidische Norm im Spiel, wären die Ecken leer
      // und es entstünde wieder eine Ellipse.
      final rechteck = rasterizeMaskShape(mitte, 100, 100);
      final ellipse = rasterizeMaskShape(
          const EllipseShape(
              centerX: 0.5, centerY: 0.5, radiusX: 0.25, radiusY: 0.25, feather: 0),
          100,
          100);
      expect(an(rechteck, 0.72, 0.72), 255, reason: 'Ecke des Rechtecks');
      expect(an(ellipse, 0.72, 0.72), 0, reason: 'dort ist die Ellipse schon aussen');
    });

    test('Weichzeichnung läuft von innen nach aussen aus', () {
      final m = rasterizeMaskShape(
          const RectangleShape(
              centerX: 0.5, centerY: 0.5, halfWidth: 0.4, halfHeight: 0.4, feather: 0.5),
          200,
          200);
      final innen = an(m, 0.5, 0.5);
      final mittig = an(m, 0.75, 0.5);
      final aussen = an(m, 0.95, 0.5);
      expect(innen, 255);
      expect(mittig, lessThan(innen));
      expect(aussen, lessThan(mittig));
    });

    test('gedreht wandert die Ecke mit', () {
      final gerade = rasterizeMaskShape(
          const RectangleShape(
              centerX: 0.5, centerY: 0.5, halfWidth: 0.4, halfHeight: 0.1, feather: 0),
          200, 200);
      final quer = rasterizeMaskShape(
          const RectangleShape(
              centerX: 0.5, centerY: 0.5, halfWidth: 0.4, halfHeight: 0.1,
              rotation: 1.5707963, feather: 0),
          200, 200);
      // Der breite Balken liegt einmal waagerecht, einmal senkrecht.
      expect(an(gerade, 0.85, 0.5), 255);
      expect(an(gerade, 0.5, 0.85), 0);
      expect(an(quer, 0.85, 0.5), 0);
      expect(an(quer, 0.5, 0.85), 255);
    });

    test('durch JSON und zurück ohne Verlust', () {
      const original = RectangleShape(
          centerX: 0.3, centerY: 0.7, halfWidth: 0.2, halfHeight: 0.1,
          rotation: 0.5, feather: 0.4);
      final zurueck = MaskShapeDefinition.decode(original.encode()) as RectangleShape;
      expect(zurueck.centerX, original.centerX);
      expect(zurueck.halfWidth, original.halfWidth);
      expect(zurueck.rotation, original.rotation);
      expect(zurueck.feather, original.feather);
    });
  });

  group('Farbauswahl', () {
    /// Ein Bild aus drei senkrechten Streifen: Hellblau, Dunkelblau, Grau.
    img.Image streifen() {
      final bild = img.Image(width: 90, height: 30);
      for (var y = 0; y < 30; y++) {
        for (var x = 0; x < 90; x++) {
          if (x < 30) {
            bild.setPixelRgb(x, y, 120, 170, 230); // hellblau
          } else if (x < 60) {
            bild.setPixelRgb(x, y, 40, 60, 110); // dunkelblau
          } else {
            bild.setPixelRgb(x, y, 150, 150, 150); // grau
          }
        }
      }
      return bild;
    }

    test('Helligkeit zählt weniger als Farbe', () {
      // Der Kern der Sache: Wer den Himmel anklickt, meint auch dessen
      // dunkle Stellen. In reinem RGB gemessen läge Dunkelblau weiter von
      // Hellblau entfernt als Grau – und die Auswahl wäre unbrauchbar.
      final m = rasterizeMaskShape(
        const ColorRangeShape(
            pointX: 0.15, pointY: 0.5,
            red: 120, green: 170, blue: 230,
            tolerance: 0.25, feather: 0),
        90, 30,
        quelle: streifen(),
      );
      expect(an(m, 0.15, 0.5), 255, reason: 'die aufgenommene Farbe selbst');
      expect(an(m, 0.5, 0.5), 255, reason: 'dunkleres Blau gehört dazu');
      expect(an(m, 0.85, 0.5), 0, reason: 'Grau nicht');
    });

    test('eine kleine Toleranz wählt nur die eigene Farbe', () {
      final m = rasterizeMaskShape(
        const ColorRangeShape(
            pointX: 0.15, pointY: 0.5,
            red: 120, green: 170, blue: 230,
            tolerance: 0.05, feather: 0),
        90, 30,
        quelle: streifen(),
      );
      expect(an(m, 0.15, 0.5), 255);
      expect(an(m, 0.5, 0.5), 0);
    });

    test('ohne Quelle bleibt die Maske leer statt zu raten', () {
      // Eine erfundene Auswahl wäre schlimmer als keine: Sie sähe aus wie
      // eine.
      final m = rasterizeMaskShape(
        const ColorRangeShape(
            pointX: 0.5, pointY: 0.5, red: 10, green: 20, blue: 30),
        20, 20,
      );
      for (var y = 0; y < 20; y++) {
        for (var x = 0; x < 20; x++) {
          expect(m.getPixel(x, y).r, 0);
        }
      }
    });

    test('die Quelle darf eine andere Auflösung haben als die Maske', () {
      // Der Regelfall: gerastert wird in Originalgrösse, die Farben kommen
      // aus der viel kleineren Vorschau.
      final m = rasterizeMaskShape(
        const ColorRangeShape(
            pointX: 0.15, pointY: 0.5,
            red: 120, green: 170, blue: 230,
            tolerance: 0.25, feather: 0),
        900, 300,
        quelle: streifen(),
      );
      expect(an(m, 0.15, 0.5), 255);
      expect(an(m, 0.85, 0.5), 0);
    });

    test('Weichzeichnung erzeugt Zwischenwerte', () {
      final hart = rasterizeMaskShape(
        const ColorRangeShape(
            pointX: 0.15, pointY: 0.5, red: 120, green: 170, blue: 230,
            tolerance: 0.3, feather: 0),
        90, 30, quelle: streifen(),
      );
      final weich = rasterizeMaskShape(
        const ColorRangeShape(
            pointX: 0.15, pointY: 0.5, red: 120, green: 170, blue: 230,
            tolerance: 0.3, feather: 1),
        90, 30, quelle: streifen(),
      );
      // Am dunkelblauen Streifen, der knapp innerhalb der Toleranz liegt:
      // hart voll ausgewählt, weich nur teilweise.
      expect(an(hart, 0.5, 0.5), 255);
      expect(an(weich, 0.5, 0.5), lessThan(255));
      expect(an(weich, 0.5, 0.5), greaterThan(0));
    });

    test('durch JSON und zurück ohne Verlust', () {
      const original = ColorRangeShape(
          pointX: 0.2, pointY: 0.8, red: 1, green: 2, blue: 3,
          tolerance: 0.4, feather: 0.6);
      final zurueck = MaskShapeDefinition.decode(original.encode()) as ColorRangeShape;
      expect(zurueck.red, 1);
      expect(zurueck.blue, 3);
      expect(zurueck.tolerance, closeTo(0.4, 1e-9));
      expect(zurueck.pointY, closeTo(0.8, 1e-9));
    });
  });

  test('ein unbekannter Typ wird abgelehnt statt still ignoriert', () {
    expect(() => MaskShapeDefinition.decode('{"type":"dreieck"}'),
        throwsA(isA<ArgumentError>()));
  });

  test('der weiche Saum ist anteilig, nicht in Pixeln', () {
    // Wie bei der Ellipse. Bei einem langgezogenen Rechteck ist der Saum an
    // den langen Seiten dadurch breiter – sichtbar und Absicht, damit zwei
    // Werkzeuge mit gleich benanntem Regler gleich reagieren.
    //
    // Gemessen wird, wo der Wert von innen nach aussen die Hälfte
    // unterschreitet: Bei anteiligem Saum muss das Verhältnis der beiden
    // Halbachsen herauskommen, bei einem Saum in Pixeln wäre es 1:1.
    const hw = 0.4, hh = 0.1;
    final m = rasterizeMaskShape(
        const RectangleShape(
            centerX: 0.5, centerY: 0.5, halfWidth: hw, halfHeight: hh, feather: 0.5),
        400, 400);
    int wert(int x, int y) => m.getPixel(x, y).r.toInt();

    var waagerecht = 200;
    while (waagerecht < 399 && wert(waagerecht, 200) > 128) {
      waagerecht++;
    }
    var senkrecht = 200;
    while (senkrecht < 399 && wert(200, senkrecht) > 128) {
      senkrecht++;
    }

    final breiteHalb = (waagerecht - 200) / 400;
    final hoeheHalb = (senkrecht - 200) / 400;
    expect(breiteHalb / hoeheHalb, closeTo(hw / hh, 0.15),
        reason: 'der Saum skaliert mit der jeweiligen Halbachse');
  });
}
