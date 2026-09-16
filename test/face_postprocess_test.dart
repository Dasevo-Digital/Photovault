import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/face_postprocess.dart';

void main() {
  group('FacePostprocess.iou', () {
    test('identische Boxen haben IoU 1.0', () {
      final box = DetectedFace(0.1, 0.1, 0.2, 0.2, 0.9);
      expect(FacePostprocess.iou(box, box), closeTo(1.0, 1e-9));
    });

    test('nicht überlappende Boxen haben IoU 0.0', () {
      final a = DetectedFace(0.0, 0.0, 0.1, 0.1, 0.9);
      final b = DetectedFace(0.5, 0.5, 0.1, 0.1, 0.9);
      expect(FacePostprocess.iou(a, b), 0.0);
    });

    test('teilweise überlappende Boxen ergeben den erwarteten Wert', () {
      // a: [0,0]..[0.2,0.2], b: [0.1,0.1]..[0.3,0.3] -> Schnitt [0.1,0.1]..[0.2,0.2]
      final a = DetectedFace(0.0, 0.0, 0.2, 0.2, 0.9);
      final b = DetectedFace(0.1, 0.1, 0.2, 0.2, 0.8);
      const interArea = 0.1 * 0.1;
      const unionArea = 0.2 * 0.2 + 0.2 * 0.2 - interArea;
      expect(FacePostprocess.iou(a, b), closeTo(interArea / unionArea, 1e-9));
    });
  });

  group('FacePostprocess.combinedScore', () {
    test('geometrisches Mittel aus Klassifikations- und Objektheits-Score', () {
      expect(FacePostprocess.combinedScore(0.81, 1.0), closeTo(0.9, 1e-9));
      expect(FacePostprocess.combinedScore(0.5, 0.5), closeTo(0.5, 1e-9));
    });

    test('clampt Eingaben außerhalb von [0,1] statt NaN/negative Scores zu produzieren', () {
      expect(FacePostprocess.combinedScore(1.5, 1.0), closeTo(1.0, 1e-9));
      expect(FacePostprocess.combinedScore(-1.0, 1.0), 0.0);
    });
  });

  group('FacePostprocess.decodeBox', () {
    test('decodiert eine Anchor-Zelle in die erwartete normalisierte Box', () {
      // Handgerechnet: cx=(20+0.5)*16=328, cy=(10+0.5)*16=168, w=h=exp(0)*16=16
      // -> x1=320, y1=160 -> normalisiert auf 640: x=0.5, y=0.25, w=h=0.025
      final box = FacePostprocess.decodeBox(
        row: 10,
        col: 20,
        stride: 16,
        dx: 0.5,
        dy: 0.5,
        dw: 0,
        dh: 0,
        inputSize: 640,
        score: 0.9,
      );
      expect(box.x, closeTo(0.5, 1e-9));
      expect(box.y, closeTo(0.25, 1e-9));
      expect(box.width, closeTo(0.025, 1e-9));
      expect(box.height, closeTo(0.025, 1e-9));
      expect(box.score, 0.9);
    });

    test('clampt Boxen, die über den Bildrand hinausragen, auf [0,1]', () {
      // Sehr große Box nahe am Ursprung -> x1/y1 werden negativ, w/h riesig.
      final box = FacePostprocess.decodeBox(
        row: 0,
        col: 0,
        stride: 8,
        dx: 0,
        dy: 0,
        dw: 10,
        dh: 10,
        inputSize: 640,
        score: 0.5,
      );
      expect(box.x, 0.0);
      expect(box.y, 0.0);
      expect(box.width, lessThanOrEqualTo(1.0));
      expect(box.height, lessThanOrEqualTo(1.0));
    });
  });

  group('FacePostprocess.decodeLandmarks', () {
    test('decodiert 5 Punkte mit derselben Zellen-Offset-Logik wie die Box-Mitte', () {
      // Punkt 0 nutzt dieselben dx/dy wie im decodeBox-Test oben:
      // px=(20+0.5)*16=328, py=(10+0.5)*16=168 -> normalisiert auf 640.
      final kps = [
        0.5, 0.5, // Punkt 0
        0.0, 0.0, // Punkt 1
        1.0, 1.0, // Punkt 2
        0.25, 0.75, // Punkt 3
        0.75, 0.25, // Punkt 4
      ];
      final result = FacePostprocess.decodeLandmarks(
        row: 10,
        col: 20,
        stride: 16,
        kps: kps,
        inputSize: 640,
      );
      expect(result.length, 10);
      expect(result[0], closeTo(328 / 640, 1e-9));
      expect(result[1], closeTo(168 / 640, 1e-9));
      expect(result[2], closeTo(320 / 640, 1e-9)); // (20+0)*16=320
      expect(result[3], closeTo(160 / 640, 1e-9)); // (10+0)*16=160
      expect(result[4], closeTo(336 / 640, 1e-9)); // (20+1)*16=336
      expect(result[5], closeTo(176 / 640, 1e-9)); // (10+1)*16=176
    });

    test('klemmt Werte außerhalb des Bildes auf [0,1]', () {
      final kps = List<double>.filled(10, 10.0); // weit außerhalb der Zelle
      final result = FacePostprocess.decodeLandmarks(
        row: 0,
        col: 0,
        stride: 8,
        kps: kps,
        inputSize: 640,
      );
      expect(result.every((v) => v >= 0.0 && v <= 1.0), isTrue);
    });
  });

  group('FacePostprocess.nonMaxSuppression', () {
    test('unterdrückt schwächere, stark überlappende Boxen', () {
      final strong = DetectedFace(0.10, 0.10, 0.20, 0.20, 0.95);
      final weakOverlap = DetectedFace(0.11, 0.11, 0.20, 0.20, 0.60); // fast identisch zu "strong"
      final farAway = DetectedFace(0.70, 0.70, 0.10, 0.10, 0.80);

      final kept = FacePostprocess.nonMaxSuppression(
        [weakOverlap, strong, farAway],
        iouThreshold: 0.3,
      );

      expect(kept, hasLength(2));
      expect(kept, contains(strong));
      expect(kept, contains(farAway));
      expect(kept, isNot(contains(weakOverlap)));
    });

    test('behält getrennte Boxen unterhalb des IoU-Schwellwerts alle', () {
      final a = DetectedFace(0.0, 0.0, 0.1, 0.1, 0.9);
      final b = DetectedFace(0.5, 0.5, 0.1, 0.1, 0.8);
      final c = DetectedFace(0.8, 0.1, 0.1, 0.1, 0.7);

      final kept = FacePostprocess.nonMaxSuppression([a, b, c], iouThreshold: 0.3);

      expect(kept, hasLength(3));
    });

    test('leere Eingabe ergibt leere Ausgabe', () {
      expect(FacePostprocess.nonMaxSuppression([], iouThreshold: 0.3), isEmpty);
    });
  });
}
