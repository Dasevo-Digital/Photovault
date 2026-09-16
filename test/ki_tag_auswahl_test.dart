import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/ai_tagging_service.dart';

/// **Rangieren statt schwellen.**
///
/// Anlass ist die Bibliothek des Nutzers: 94.040 KI-Schlagwörter auf 7.400
/// Aufnahmen. „Bildschirmfoto" hing an 4.585 Fotos, „Geburtstagstorte" an
/// 4.050 – auf mehr als der Hälfte der Bibliothek. Die alte Regel vergab
/// jeden Begriff über einer festen Ähnlichkeit von 0,24 und setzte damit
/// voraus, dass diese Werte zwischen Begriffen vergleichbar sind. Sie
/// sind es nicht.
void main() {
  group('Die Auswahlregel', () {
    test('nimmt die besten und deckelt die Zahl', () {
      final begriffe = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
      // Sieben Begriffe, alle über der alten Schwelle von 0,24 – die alte
      // Regel hätte alle sieben vergeben.
      final naehe = [0.33, 0.32, 0.31, 0.30, 0.29, 0.28, 0.27];
      final gewaehlt = waehleTags(begriffe, naehe);
      expect(gewaehlt.length, lessThanOrEqualTo(kiTagsHoechstens));
      expect(gewaehlt.first, 'a', reason: 'der beste zuerst');
    });

    test('ein einzelner Ausreisser bekommt das Foto für sich', () {
      // Ein Begriff sticht deutlich heraus: Die Softmax gibt ihm fast die
      // ganze Masse, die übrigen fallen unter den Mindestanteil.
      final gewaehlt = waehleTags(
        ['Hund', 'Kuchen', 'Schnee', 'Auto'],
        [0.34, 0.24, 0.23, 0.22],
      );
      expect(gewaehlt, ['Hund']);
    });

    test('bei Gleichstand teilen sich mehrere das Foto', () {
      final gewaehlt = waehleTags(
        ['Strand', 'Meer', 'Sommer', 'Wasser'],
        [0.30, 0.299, 0.298, 0.297],
      );
      expect(gewaehlt.length, greaterThan(1),
          reason: 'wo nichts heraussticht, darf auch nichts alleine stehen');
    });

    test('passt gar nichts, gibt es nichts', () {
      // Der Rang allein genügt nicht: Auch auf einem Foto ohne jeden
      // passenden Begriff gibt es einen besten.
      final gewaehlt = waehleTags(['Hund', 'Kuchen'], [0.11, 0.10]);
      expect(gewaehlt, isEmpty);
    });

    test('leeres Vokabular wirft nicht', () {
      expect(waehleTags(const [], const []), isEmpty);
    });

    test('die Reihenfolge der Eingabe ändert das Ergebnis nicht', () {
      final a = waehleTags(['x', 'y', 'z'], [0.22, 0.34, 0.28]);
      final b = waehleTags(['y', 'z', 'x'], [0.34, 0.28, 0.22]);
      expect(a, b);
    });

    test('rechnet auch bei hohen Ähnlichkeiten ohne Überlauf', () {
      // exp(100 * 0,9) liefe über, wenn nicht der grösste Wert vorher
      // abgezogen würde.
      final gewaehlt = waehleTags(['a', 'b'], [0.95, 0.94]);
      expect(gewaehlt, isNotEmpty);
      expect(gewaehlt.first, 'a');
    });
  });

  group('Was die Regel gegenüber der alten Schwelle einspart', () {
    // An 1500 echten Aufnahmen der Produktivbibliothek gemessen (siehe
    // integration_test/ki_tag_auswahl_messung_test.dart):
    //
    //   alte Schwelle 0,24   5,3 je Foto, Spitzen bis 44
    //   neue Regel           3,3 je Foto, nie mehr als 5
    test('deckelt die Spitze, die es vorher gab', () {
      // Ein Foto, das unter der alten Regel 20 Schlagwörter bekam.
      final begriffe = [for (var i = 0; i < 20; i++) 'b$i'];
      final naehe = [for (var i = 0; i < 20; i++) 0.30 - i * 0.001];
      final alt = [
        for (var i = 0; i < 20; i++)
          if (naehe[i] >= 0.24) begriffe[i]
      ];
      expect(alt.length, 20, reason: 'so sah es vorher aus');
      expect(waehleTags(begriffe, naehe).length,
          lessThanOrEqualTo(kiTagsHoechstens));
    });
  });
}
