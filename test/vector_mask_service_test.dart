import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/services/vector_mask_service.dart';

/// Reine Rasterisierungs-Tests je Formtyp (Muster: die maskToOriginalResolution-
/// Tests in segmentation_service_test.dart, hier aber ohne ONNX/Native, da
/// [rasterizeMaskShape] eine reine Geometrie-Funktion ist) sowie JSON-
/// Rundreisen-Tests (Speichern/Wiederherstellen über DevelopMasks.
/// shapeDefinitionJson).
void main() {
  int valueAt(img.Image image, int x, int y) => image.getPixel(x, y).r.toInt();

  group('JSON-Rundreise', () {
    test('FreehandShape übersteht encode/decode unverändert', () {
      const shape = FreehandShape(points: [Offset(0.1, 0.2), Offset(0.5, 0.6)], strokeWidth: 0.05);
      final decoded = MaskShapeDefinition.decode(shape.encode()) as FreehandShape;
      expect(decoded.points, shape.points);
      expect(decoded.strokeWidth, shape.strokeWidth);
    });

    test('EllipseShape übersteht encode/decode unverändert', () {
      const shape = EllipseShape(centerX: 0.3, centerY: 0.4, radiusX: 0.2, radiusY: 0.1, rotation: 0.5, feather: 0.4);
      final decoded = MaskShapeDefinition.decode(shape.encode()) as EllipseShape;
      expect(decoded.centerX, shape.centerX);
      expect(decoded.centerY, shape.centerY);
      expect(decoded.radiusX, shape.radiusX);
      expect(decoded.radiusY, shape.radiusY);
      expect(decoded.rotation, shape.rotation);
      expect(decoded.feather, shape.feather);
    });

    test('GradientShape übersteht encode/decode unverändert', () {
      const shape = GradientShape(startX: 0, startY: 0, endX: 1, endY: 1, feather: 0.2);
      final decoded = MaskShapeDefinition.decode(shape.encode()) as GradientShape;
      expect(decoded.startX, shape.startX);
      expect(decoded.endY, shape.endY);
      expect(decoded.feather, shape.feather);
    });

    test('unbekannter Typ wirft statt still eine falsche Form zurückzugeben', () {
      expect(() => MaskShapeDefinition.decode('{"type":"unbekannt"}'), throwsArgumentError);
    });
  });

  group('rasterizeMaskShape: Ellipse', () {
    test('erzeugt einen weißen Kreis in der Mitte und bleibt an den Ecken schwarz', () {
      const shape = EllipseShape(centerX: 0.5, centerY: 0.5, radiusX: 0.2, radiusY: 0.2, feather: 0);
      final mask = rasterizeMaskShape(shape, 100, 100);

      expect(valueAt(mask, 50, 50), 255); // Mittelpunkt: voll ausgewählt.
      expect(valueAt(mask, 0, 0), 0); // Ecke: weit außerhalb, nicht ausgewählt.
      expect(valueAt(mask, 99, 99), 0);
    });

    test('mit feather=0 ist die Kante hart (kein Zwischenwert)', () {
      const shape = EllipseShape(centerX: 0.5, centerY: 0.5, radiusX: 0.2, radiusY: 0.2, feather: 0);
      final mask = rasterizeMaskShape(shape, 100, 100);
      final values = {for (var x = 0; x < 100; x++) valueAt(mask, x, 50)};
      expect(values, containsAll([0, 255]));
      expect(values.where((v) => v != 0 && v != 255), isEmpty);
    });

    test('mit feather>0 gibt es einen weichen Übergang (Zwischenwerte) am Rand', () {
      const shape = EllipseShape(centerX: 0.5, centerY: 0.5, radiusX: 0.3, radiusY: 0.3, feather: 0.5);
      final mask = rasterizeMaskShape(shape, 100, 100);
      final values = [for (var x = 0; x < 100; x++) valueAt(mask, x, 50)];
      expect(values.any((v) => v > 0 && v < 255), isTrue);
    });

    test('Rotation vertauscht effektiv radiusX/radiusY um 90°', () {
      // Eine breite, flache Ellipse (rx>>ry), um 90° gedreht, wird schmal
      // und hoch – ein Punkt weit rechts von der Mitte (der bei rx=0.4 ohne
      // Rotation ausgewählt wäre) liegt nach der Drehung außerhalb.
      const unrotated = EllipseShape(centerX: 0.5, centerY: 0.5, radiusX: 0.4, radiusY: 0.05, feather: 0);
      const rotated = EllipseShape(
          centerX: 0.5, centerY: 0.5, radiusX: 0.4, radiusY: 0.05, rotation: 3.14159265 / 2, feather: 0);
      final unrotatedMask = rasterizeMaskShape(unrotated, 100, 100);
      final rotatedMask = rasterizeMaskShape(rotated, 100, 100);
      expect(valueAt(unrotatedMask, 85, 50), 255);
      expect(valueAt(rotatedMask, 85, 50), 0);
    });
  });

  group('rasterizeMaskShape: Verlauf', () {
    test('ist am Startpunkt schwarz und am Endpunkt weiß', () {
      const shape = GradientShape(startX: 0, startY: 0.5, endX: 1, endY: 0.5, feather: 0);
      final mask = rasterizeMaskShape(shape, 100, 100);
      expect(valueAt(mask, 0, 50), lessThan(20));
      expect(valueAt(mask, 99, 50), greaterThan(235));
    });

    test('ist entlang der Verlaufsrichtung monoton steigend', () {
      const shape = GradientShape(startX: 0, startY: 0.5, endX: 1, endY: 0.5, feather: 0);
      final mask = rasterizeMaskShape(shape, 100, 100);
      final values = [for (var x = 0; x < 100; x++) valueAt(mask, x, 50)];
      for (var i = 1; i < values.length; i++) {
        expect(values[i], greaterThanOrEqualTo(values[i - 1]));
      }
    });

    test('bei identischem Start-/Endpunkt kein Absturz, sondern eine neutrale Maske', () {
      const shape = GradientShape(startX: 0.5, startY: 0.5, endX: 0.5, endY: 0.5);
      final mask = rasterizeMaskShape(shape, 20, 20);
      expect(valueAt(mask, 0, 0), 127);
      expect(valueAt(mask, 19, 19), 127);
    });
  });

  group('rasterizeMaskShape: Freihand-Pinsel', () {
    test('deckt einen Bereich um die Punktfolge herum ab', () {
      const shape = FreehandShape(points: [Offset(0.2, 0.5), Offset(0.8, 0.5)], strokeWidth: 0.1);
      final mask = rasterizeMaskShape(shape, 100, 100);
      // Entlang der gezeichneten Linie (y=50) sollte die Mitte ausgewählt sein …
      expect(valueAt(mask, 50, 50), 255);
      // … oben/unten weit außerhalb der Strichbreite nicht.
      expect(valueAt(mask, 50, 0), 0);
      expect(valueAt(mask, 50, 99), 0);
    });

    test('ein einzelner Punkt malt eine Scheibe statt gar nichts', () {
      const shape = FreehandShape(points: [Offset(0.5, 0.5)], strokeWidth: 0.2);
      final mask = rasterizeMaskShape(shape, 100, 100);
      expect(valueAt(mask, 50, 50), 255);
    });

    test('leere Punktliste ergibt eine komplett schwarze (leere) Maske', () {
      const shape = FreehandShape(points: []);
      final mask = rasterizeMaskShape(shape, 20, 20);
      expect(valueAt(mask, 10, 10), 0);
    });
  });
}
