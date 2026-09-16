import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/services/face_engine_service.dart';

void main() {
  group('FaceEngineService.alignFace', () {
    test('liefert null ohne Landmarks (Aufrufer fallen dann auf cropFaceImage zurück)', () {
      final decoded = img.Image(width: 200, height: 200);
      final box = DetectedFace(0.25, 0.25, 0.5, 0.5, 0.9);
      expect(FaceEngineService.alignFace(decoded, box), isNull);
    });

    test('liefert bei Landmarks exakt am Referenz-Layout ein unverändertes 112x112-Bild', () {
      // Dieselben Referenzpunkte wie FaceEngineService._sfaceTemplate.
      const size = 112;
      const template = [
        38.2946, 51.6963,
        73.5318, 51.5014,
        56.0252, 71.7366,
        41.5493, 92.3655,
        70.7299, 92.2041,
      ];

      final decoded = img.Image(width: size, height: size);
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          decoded.setPixelRgb(x, y, x * 2, y * 2, 100);
        }
      }

      // Landmarks liegen exakt am Referenz-Layout -> die angepasste
      // Ähnlichkeitstransformation muss die Identität sein (keine Rotation,
      // Skalierung 1, keine Verschiebung), das Ergebnis also pixelgleich
      // zum Original.
      final landmarks = template.map((v) => v / size).toList();
      final box = DetectedFace(0.1, 0.1, 0.8, 0.8, 0.9, landmarks: landmarks);
      final aligned = FaceEngineService.alignFace(decoded, box);

      expect(aligned, isNotNull);
      expect(aligned!.width, size);
      expect(aligned.height, size);

      for (final point in [(0, 0), (56, 56), (111, 111), (30, 80)]) {
        final expected = decoded.getPixel(point.$1, point.$2);
        final actual = aligned.getPixel(point.$1, point.$2);
        expect(actual.r.toDouble(), closeTo(expected.r.toDouble(), 0.5));
        expect(actual.g.toDouble(), closeTo(expected.g.toDouble(), 0.5));
        expect(actual.b.toDouble(), closeTo(expected.b.toDouble(), 0.5));
      }
    });
  });
}
