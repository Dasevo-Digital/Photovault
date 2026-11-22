import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/services/bildzuschnitt.dart';
import 'package:photo_vault/services/vector_mask_service.dart';

/// **Masken und Pipetten bei zugeschnittenem oder gedrehtem Foto (#457).**
///
/// Der Entwickeln-Bildschirm zeigt das Foto mit Zuschnitt und
/// Vierteldrehung, Masken liegen aber über dem ganzen Original. Die
/// Umrechnung zwischen beiden steht in [Bildzuschnitt]; geprüft wird sie
/// hier an der Rechnung, die das Bild tatsächlich schneidet und dreht
/// ([schneideBild]) – nicht an einer zweiten Formel, die sich mit der
/// ersten irren könnte.
void main() {
  // Ein Ausschnitt, der weder mittig noch quadratisch ist: Bei einem
  // symmetrischen fielen vertauschte Achsen nicht auf.
  Bildzuschnitt zuschnitt(int drehungen) => Bildzuschnitt(
    links: 0.1,
    oben: 0.2,
    breite: 0.6,
    hoehe: 0.7,
    drehungen: drehungen,
  );
  const breite = 300, hoehe = 200;

  /// Wo im Bild der eine weisse Punkt steht.
  (int, int) weisserPunkt(img.Image bild) {
    for (var y = 0; y < bild.height; y++) {
      for (var x = 0; x < bild.width; x++) {
        if (bild.getPixel(x, y).r > 127) return (x, y);
      }
    }
    fail('kein weisser Punkt im Bild');
  }

  img.Image mitPunkt(int x, int y) {
    final bild = img.Image(width: breite, height: hoehe);
    bild.setPixelRgb(x, y, 255, 255, 255);
    return bild;
  }

  for (final d in [0, 1, 2, 3]) {
    group('${d * 90}°', () {
      final z = zuschnitt(d);

      test('ein Punkt landet in der Anzeige dort, wo das Bild ihn zeigt', () {
        for (final (px, py) in [(40, 50), (200, 170), (120, 90)]) {
          final angezeigt = schneideBild(mitPunkt(px, py), z);
          final (ax, ay) = weisserPunkt(angezeigt);
          final (u, v) = z.inDieAnzeige(
            (px + 0.5) / breite,
            (py + 0.5) / hoehe,
          );
          expect(u * angezeigt.width, closeTo(ax + 0.5, 1));
          expect(v * angezeigt.height, closeTo(ay + 0.5, 1));
          // Und zurück, ohne Verlust.
          final (x, y) = z.insOriginal(u, v);
          expect(x, closeTo((px + 0.5) / breite, 1e-9));
          expect(y, closeTo((py + 0.5) / hoehe, 1e-9));
        }
      });

      test('das Seitenverhältnis der Anzeige stimmt', () {
        final angezeigt = schneideBild(mitPunkt(40, 50), z);
        final (b, h) = z.masseDerAnzeige(breite.toDouble(), hoehe.toDouble());
        expect(b, closeTo(angezeigt.width, 1));
        expect(h, closeTo(angezeigt.height, 1));
      });

      test('eine Maske auf der Anzeige kommt an ihre Stelle im Original', () {
        // Eine Maske, die genau den angezeigten Punkt trifft – so, wie
        // die KI-Auswahl sie auf der Vorschau liefert.
        final maske = schneideBild(mitPunkt(200, 170), z);
        final zurueck = maskeInsOriginal(maske, z);
        expect(zurueck.width, closeTo(breite, 1));
        expect(zurueck.height, closeTo(hoehe, 1));
        final (x, y) = weisserPunkt(zurueck);
        expect(x, closeTo(200, 1));
        expect(y, closeTo(170, 1));
      });

      test('eine Form bedeckt in der Anzeige, was das Bild zeigt', () {
        const formen = <MaskShapeDefinition>[
          EllipseShape(
            centerX: 0.45,
            centerY: 0.5,
            radiusX: 0.15,
            radiusY: 0.2,
            rotation: 0.5,
            feather: 0,
          ),
          RectangleShape(
            centerX: 0.3,
            centerY: 0.6,
            halfWidth: 0.12,
            halfHeight: 0.08,
            rotation: -0.3,
            feather: 0,
          ),
          GradientShape(
            startX: 0.2,
            startY: 0.3,
            endX: 0.6,
            endY: 0.8,
            feather: 0,
          ),
          FreehandShape(
            points: [Offset(0.2, 0.3), Offset(0.5, 0.4), Offset(0.6, 0.8)],
            strokeWidth: 0.05,
          ),
        ];
        for (final form in formen) {
          // Erwartet: die Maske im Original, so geschnitten und gedreht
          // wie das Foto.
          final erwartet = schneideBild(
            rasterizeMaskShape(form, breite, hoehe),
            z,
          );
          final anzeige = formInDieAnzeige(
            form,
            z,
            bildBreite: breite.toDouble(),
            bildHoehe: hoehe.toDouble(),
          );
          final gezeichnet = rasterizeMaskShape(
            anzeige,
            erwartet.width,
            erwartet.height,
          );
          var abweichend = 0;
          for (var y = 0; y < erwartet.height; y++) {
            for (var x = 0; x < erwartet.width; x++) {
              final a = erwartet.getPixel(x, y).r;
              final b = gezeichnet.getPixel(x, y).r;
              if ((a - b).abs() > 40) abweichend++;
            }
          }
          // Nur Randpunkte dürfen kippen.
          expect(
            abweichend / (erwartet.width * erwartet.height),
            lessThan(0.01),
            reason: '${form.runtimeType}',
          );
          // Und zurück ins Original ergibt wieder dieselbe Form.
          final zurueck = formInsOriginal(
            anzeige,
            z,
            bildBreite: breite.toDouble(),
            bildHoehe: hoehe.toDouble(),
          );
          final a = form.toJson();
          final b = zurueck.toJson();
          for (final schluessel in a.keys) {
            final wa = a[schluessel], wb = b[schluessel];
            if (wa is num && wb is num) {
              expect(wb, closeTo(wa, 1e-9), reason: schluessel);
            }
          }
        }
      });
    });
  }

  test('ohne Zuschnitt bleibt alles, wie es ist', () {
    final z = Bildzuschnitt.ganz;
    expect(z.insOriginal(0.3, 0.7), (0.3, 0.7));
    expect(z.inDieAnzeige(0.3, 0.7), (0.3, 0.7));
    final maske = mitPunkt(10, 20);
    expect(identical(maskeInsOriginal(maske, z), maske), isTrue);
    const form = EllipseShape(
      centerX: 0.4,
      centerY: 0.5,
      radiusX: 0.1,
      radiusY: 0.2,
    );
    expect(
      identical(
        formInsOriginal(form, z, bildBreite: 300, bildHoehe: 200),
        form,
      ),
      isTrue,
    );
  });
}
