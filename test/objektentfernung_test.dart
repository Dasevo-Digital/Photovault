import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/services/inpainting_service.dart';

/// Die Geometrie der Objektentfernung.
///
/// Das Modell selbst wird unter `integration_test/` am echten Gewicht
/// geprüft – hier geht es um die Rechnung davor, die ohne Plattformkanal
/// auskommt und deshalb bei jedem Testlauf mitläuft.
void main() {
  img.Image maskeMit({required int x, required int y, required int w, required int h,
      int breite = 1000, int hoehe = 800}) {
    final m = img.Image(width: breite, height: hoehe);
    img.fillRect(m, x1: x, y1: y, x2: x + w - 1, y2: y + h - 1,
        color: img.ColorRgb8(255, 255, 255));
    return m;
  }

  group('Umschliessendes Rechteck', () {
    test('findet genau den markierten Bereich', () {
      final k = maskenKasten(maskeMit(x: 100, y: 50, w: 30, h: 20))!;
      expect(k.left, 100);
      expect(k.top, 50);
      expect(k.width, 30);
      expect(k.height, 20);
    });

    test('eine leere Maske ergibt null statt eines Nullrechtecks', () {
      // Sonst liefe die Entfernung auf einem leeren Bereich los.
      expect(maskenKasten(img.Image(width: 50, height: 50)), isNull);
    });

    test('graue Zwischenwerte zählen nicht als markiert', () {
      final m = img.Image(width: 50, height: 50);
      img.fillRect(m, x1: 10, y1: 10, x2: 20, y2: 20, color: img.ColorRgb8(80, 80, 80));
      expect(maskenKasten(m), isNull);
    });
  });

  group('Ausschnitt', () {
    test('ist nie kleiner als das Modell verlangt', () {
      // Der wichtigste Wert der ganzen Datei, gemessen: Ein kleinerer
      // Ausschnitt müsste hochgerechnet werden, und darauf arbeitet das
      // Modell dramatisch schlechter (Fehler 62,8 statt 1,2 von 255).
      final a = quadratischerAusschnitt(
          (left: 400, top: 300, width: 20, height: 20), 48, 1000, 800);
      expect(a.width, greaterThanOrEqualTo(InpaintingService.modellGroesse));
      expect(a.height, a.width);
    });

    test('ist quadratisch', () {
      // Ein längliches Rechteck auf 512x512 zu verzerren staucht das Motiv,
      // und das Modell füllt entsprechend verzerrt.
      final a = quadratischerAusschnitt(
          (left: 100, top: 100, width: 400, height: 40), 60, 1000, 800);
      expect(a.width, a.height);
    });

    test('bleibt im Bild, auch am Rand', () {
      for (final kasten in [
        (left: 0, top: 0, width: 30, height: 30),
        (left: 970, top: 770, width: 30, height: 30),
        (left: 0, top: 770, width: 30, height: 30),
      ]) {
        final a = quadratischerAusschnitt(kasten, 48, 1000, 800);
        expect(a.left, greaterThanOrEqualTo(0));
        expect(a.top, greaterThanOrEqualTo(0));
        expect(a.left + a.width, lessThanOrEqualTo(1000));
        expect(a.top + a.height, lessThanOrEqualTo(800));
      }
    });

    test('enthält den markierten Bereich vollständig', () {
      // Sonst bliebe ein Teil des Objekts stehen.
      const kasten = (left: 300, top: 200, width: 120, height: 90);
      final a = quadratischerAusschnitt(kasten, 60, 1000, 800);
      expect(a.left, lessThanOrEqualTo(kasten.left));
      expect(a.top, lessThanOrEqualTo(kasten.top));
      expect(a.left + a.width, greaterThanOrEqualTo(kasten.left + kasten.width));
      expect(a.top + a.height, greaterThanOrEqualTo(kasten.top + kasten.height));
    });

    test('ein kleines Bild begrenzt den Ausschnitt', () {
      // Bei einem Foto unter 512 Punkten geht nicht mehr als das Bild.
      final a = quadratischerAusschnitt(
          (left: 10, top: 10, width: 20, height: 20), 48, 300, 200);
      expect(a.width, 200);
      expect(a.height, 200);
    });
  });
}
