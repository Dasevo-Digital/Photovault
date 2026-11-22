import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/services/face_engine_service.dart';
import 'package:kern/services/face_postprocess.dart';

/// Ein quadratisches Bild füllt die Eingabe ganz – wie bis #461 jedes.
final _quadrat = Letterbox.fuer(640, 640, seite: 640);

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

    test(
      'clampt Eingaben außerhalb von [0,1] statt NaN/negative Scores zu produzieren',
      () {
        expect(FacePostprocess.combinedScore(1.5, 1.0), closeTo(1.0, 1e-9));
        expect(FacePostprocess.combinedScore(-1.0, 1.0), 0.0);
      },
    );
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
        rahmen: _quadrat,
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
        rahmen: _quadrat,
        score: 0.5,
      );
      expect(box.x, 0.0);
      expect(box.y, 0.0);
      expect(box.width, lessThanOrEqualTo(1.0));
      expect(box.height, lessThanOrEqualTo(1.0));
    });
  });

  group('FacePostprocess.decodeLandmarks', () {
    test(
      'decodiert 5 Punkte mit derselben Zellen-Offset-Logik wie die Box-Mitte',
      () {
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
          rahmen: _quadrat,
        );
        expect(result.length, 10);
        expect(result[0], closeTo(328 / 640, 1e-9));
        expect(result[1], closeTo(168 / 640, 1e-9));
        expect(result[2], closeTo(320 / 640, 1e-9)); // (20+0)*16=320
        expect(result[3], closeTo(160 / 640, 1e-9)); // (10+0)*16=160
        expect(result[4], closeTo(336 / 640, 1e-9)); // (20+1)*16=336
        expect(result[5], closeTo(176 / 640, 1e-9)); // (10+1)*16=176
      },
    );

    test('klemmt Werte außerhalb des Bildes auf [0,1]', () {
      final kps = List<double>.filled(10, 10.0); // weit außerhalb der Zelle
      final result = FacePostprocess.decodeLandmarks(
        row: 0,
        col: 0,
        stride: 8,
        kps: kps,
        rahmen: _quadrat,
      );
      expect(result.every((v) => v >= 0.0 && v <= 1.0), isTrue);
    });
  });

  group('FacePostprocess.nonMaxSuppression', () {
    test('unterdrückt schwächere, stark überlappende Boxen', () {
      final strong = DetectedFace(0.10, 0.10, 0.20, 0.20, 0.95);
      final weakOverlap = DetectedFace(
        0.11,
        0.11,
        0.20,
        0.20,
        0.60,
      ); // fast identisch zu "strong"
      final farAway = DetectedFace(0.70, 0.70, 0.10, 0.10, 0.80);

      final kept = FacePostprocess.nonMaxSuppression([
        weakOverlap,
        strong,
        farAway,
      ], iouThreshold: 0.3);

      expect(kept, hasLength(2));
      expect(kept, contains(strong));
      expect(kept, contains(farAway));
      expect(kept, isNot(contains(weakOverlap)));
    });

    test('behält getrennte Boxen unterhalb des IoU-Schwellwerts alle', () {
      final a = DetectedFace(0.0, 0.0, 0.1, 0.1, 0.9);
      final b = DetectedFace(0.5, 0.5, 0.1, 0.1, 0.8);
      final c = DetectedFace(0.8, 0.1, 0.1, 0.1, 0.7);

      final kept = FacePostprocess.nonMaxSuppression([
        a,
        b,
        c,
      ], iouThreshold: 0.3);

      expect(kept, hasLength(3));
    });

    test('leere Eingabe ergibt leere Ausgabe', () {
      expect(FacePostprocess.nonMaxSuppression([], iouThreshold: 0.3), isEmpty);
    });
  });

  /// #461: Bis hierher wurde jedes Bild auf 640 × 640 gestaucht. Die
  /// Kästen kamen zwar auf die richtige Stelle zurück, aber das Netz sah
  /// in einem Panorama viermal zu schmale Gesichter. Jetzt kommt das Bild
  /// mit Rand in die Eingabe – und die Rückrechnung muss den Rand
  /// herausnehmen.
  group('Letterbox (#461)', () {
    test('ein Panorama liegt oben links, darunter Rand', () {
      final r = Letterbox.fuer(4000, 1000, seite: 640);
      expect([r.breite, r.hoehe], [640, 160]);
      final h = Letterbox.fuer(1000, 4000, seite: 640);
      expect([h.breite, h.hoehe], [160, 640]);
      // Kleine Bilder werden wie bisher auf die Eingabe vergrössert.
      final k = Letterbox.fuer(320, 160, seite: 640);
      expect([k.breite, k.hoehe], [640, 320]);
    });

    test('Kasten und Punkte im Panorama landen an der richtigen Stelle', () {
      // Ein Gesicht von 400 × 400 Punkten in der Mitte eines 4000 × 1000
      // grossen Panoramas liegt in der Eingabe (Faktor 0,16) bei
      // 288..352 × 48..112: Zelle (row 5, col 20) bei Schritt 16, Mitte
      // (320, 80), Kantenlänge exp(ln 4) × 16 = 64.
      final r = Letterbox.fuer(4000, 1000, seite: 640);
      final kasten = FacePostprocess.decodeBox(
        row: 5,
        col: 20,
        stride: 16,
        dx: 0,
        dy: 0,
        dw: 1.3862943611198906,
        dh: 1.3862943611198906,
        rahmen: r,
        score: 0.9,
      );
      // Im Bild: 1800..2200 × 300..700 – also Mitte (0,5 | 0,5) und
      // 0,1 × 0,4 der Bildkanten. Gestaucht hätte die Rechnung y = 0,075
      // ergeben (48 / 640): der Kasten sässe oben am Rand.
      expect(kasten.x, closeTo(0.45, 1e-9));
      expect(kasten.y, closeTo(0.3, 1e-9));
      expect(kasten.width, closeTo(0.1, 1e-9));
      expect(kasten.height, closeTo(0.4, 1e-9));
      // Seitenverhältnis im Bild: 400 × 400 Punkte, wie das Gesicht.
      expect(kasten.width * 4000, closeTo(kasten.height * 1000, 1e-6));

      final punkte = FacePostprocess.decodeLandmarks(
        row: 5,
        col: 20,
        stride: 16,
        kps: [0, 0, 1, 1, -1, -1, 0.5, 0.25, 0, 0],
        rahmen: r,
      );
      // (320, 80) in der Eingabe ist die Bildmitte.
      expect(punkte[0], closeTo(0.5, 1e-9));
      expect(punkte[1], closeTo(0.5, 1e-9));
      // (336, 96): 16 Punkte der Eingabe sind 100 Punkte im Bild.
      expect(punkte[2], closeTo(2100 / 4000, 1e-9));
      expect(punkte[3], closeTo(600 / 1000, 1e-9));
      expect(punkte[6], closeTo(2050 / 4000, 1e-9));
      expect(punkte[7], closeTo(525 / 1000, 1e-9));
    });

    test('im Hochformat ebenso, mit dem Rand rechts', () {
      final r = Letterbox.fuer(1000, 4000, seite: 640);
      // Mitte (80, 480) in der Eingabe: row 30, col 5 bei Schritt 16.
      final kasten = FacePostprocess.decodeBox(
        row: 30,
        col: 5,
        stride: 16,
        dx: 0,
        dy: 0,
        dw: 1.3862943611198906,
        dh: 1.3862943611198906,
        rahmen: r,
        score: 0.9,
      );
      // 64 Punkte der Eingabe sind 400 im Bild: 300..700 × 2800..3200.
      expect(kasten.x, closeTo(0.3, 1e-9));
      expect(kasten.y, closeTo(0.7, 1e-9));
      expect(kasten.width, closeTo(0.4, 1e-9));
      expect(kasten.height, closeTo(0.1, 1e-9));
    });

    test('die Eingabe trägt das Bild unverzerrt und sonst Schwarz', () {
      // 800 × 200: links rot, rechts blau, je 400 Punkte.
      final bild = img.Image(width: 800, height: 200);
      for (final p in bild) {
        if (p.x < 400) {
          p
            ..r = 200
            ..g = 10
            ..b = 20;
        } else {
          p
            ..r = 30
            ..g = 40
            ..b = 250;
        }
      }
      final r = Letterbox.fuer(800, 200, seite: 640);
      expect([r.breite, r.hoehe], [640, 160]);
      final chw = FaceEngineService.yunetEingabe(bild, r);
      const flaeche = 640 * 640;
      expect(chw.length, 3 * flaeche);
      // BGR in Kanalreihenfolge.
      double wert(int kanal, int x, int y) =>
          chw[kanal * flaeche + y * 640 + x];
      expect(
        [wert(0, 100, 80), wert(1, 100, 80), wert(2, 100, 80)],
        [20, 10, 200],
      );
      expect(
        [wert(0, 500, 80), wert(1, 500, 80), wert(2, 500, 80)],
        [250, 40, 30],
      );
      // Die Grenze zwischen Rot und Blau liegt in der Mitte der Breite –
      // nicht verschoben, nicht verzerrt.
      expect(wert(2, 318, 150), 200);
      expect(wert(0, 322, 150), 250);
      // Darunter ist Rand.
      for (final y in [160, 400, 639]) {
        for (final x in [0, 320, 639]) {
          expect([wert(0, x, y), wert(1, x, y), wert(2, x, y)], [0, 0, 0]);
        }
      }
    });

    test('ein quadratisches Bild füllt die Eingabe wie bisher', () {
      final bild = img.Image(width: 512, height: 512)
        ..clear(img.ColorRgb8(1, 2, 3));
      final chw = FaceEngineService.yunetEingabe(
        bild,
        Letterbox.fuer(512, 512, seite: 640),
      );
      expect(chw.every((v) => v != 0), isTrue);
    });
  });
}
