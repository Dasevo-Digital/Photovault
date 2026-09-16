import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/eye_state_service.dart';

/// Prüft [eyeCropRects] – die reine Geometrie-Logik hinter der
/// Geschlossene-Augen-Erkennung (Landmarks -> Augen-Ausschnitte), ohne eine
/// echte ONNX-Laufzeit/Modelldatei zu brauchen.
void main() {
  group('eyeCropRects', () {
    test('liefert null ohne Landmarks', () {
      expect(eyeCropRects(200, 200, null), isNull);
    });

    test('liefert null bei zu kurzer Landmark-Liste', () {
      expect(eyeCropRects(200, 200, [0.3, 0.4]), isNull);
    });

    test('berechnet plausible, an die Bildgrenzen geklemmte Rechtecke für beide Augen', () {
      // Rechtes Auge bei (0.3, 0.4), linkes Auge bei (0.7, 0.4) - typische
      // frontale Anordnung, Nase/Mund-Landmarks werden ignoriert (nur die
      // ersten 4 Werte zählen).
      final landmarks = [0.3, 0.4, 0.7, 0.4, 0.5, 0.6, 0.35, 0.8, 0.65, 0.8];
      final result = eyeCropRects(200, 200, landmarks);

      expect(result, isNotNull);
      final (right, left) = result!;
      expect(right, isNotNull);
      expect(left, isNotNull);

      // Rechtes Auge (Landmark-Index 0/1) liegt bei x=60 (0.3*200), linkes
      // Auge (Index 2/3) bei x=140 (0.7*200) - das rechte Rechteck muss also
      // klar links vom linken liegen.
      expect(right!.x, lessThan(left!.x));

      // Beide Rechtecke bleiben innerhalb der Bildgrenzen.
      for (final rect in [right, left]) {
        expect(rect.x, greaterThanOrEqualTo(0));
        expect(rect.y, greaterThanOrEqualTo(0));
        expect(rect.x + rect.width, lessThanOrEqualTo(200));
        expect(rect.y + rect.height, lessThanOrEqualTo(200));
      }

      // Seitenverhältnis nähert sich dem Modell-Eingang 40:24 (5:3) an.
      final ratio = right.width / right.height;
      expect(ratio, closeTo(40 / 24, 0.3));
    });

    test('klemmt ein Auge nahe am Bildrand statt negativ/außerhalb zu werden', () {
      // Rechtes Auge praktisch in der Bildecke (0,0).
      final landmarks = [0.01, 0.01, 0.7, 0.4, 0.5, 0.6, 0.35, 0.8, 0.65, 0.8];
      final result = eyeCropRects(200, 200, landmarks);

      expect(result, isNotNull);
      final (right, left) = result!;
      expect(right, isNotNull);
      expect(right!.x, greaterThanOrEqualTo(0));
      expect(right.y, greaterThanOrEqualTo(0));
      expect(left, isNotNull);
    });

    test('sehr eng beieinanderliegende Punkte ergeben trotzdem ein Mindest-Fenster', () {
      // Augenabstand nahe 0 - die Fenstergröße darf nicht gegen 0 gehen.
      final landmarks = [0.5, 0.5, 0.501, 0.501, 0.5, 0.6, 0.4, 0.7, 0.6, 0.7];
      final result = eyeCropRects(200, 200, landmarks);

      expect(result, isNotNull);
      final (right, left) = result!;
      expect(right!.width, greaterThanOrEqualTo(2));
      expect(right.height, greaterThanOrEqualTo(2));
      expect(left!.width, greaterThanOrEqualTo(2));
    });
  });
}
