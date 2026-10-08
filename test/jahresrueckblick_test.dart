import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/jahresrueckblick.dart';

void main() {
  Jahresaufnahme aufnahme(
    String id,
    DateTime wann, {
    bool video = false,
    bool favorit = false,
    int bewertung = 0,
    double? schaerfe,
    String? land,
    String? ort,
    bool geraten = false,
  }) => (
    id: id,
    wann: wann,
    video: video,
    favorit: favorit,
    bewertung: bewertung,
    schaerfe: schaerfe,
    land: land,
    ort: ort,
    datumGeraten: geraten,
  );

  group('Zahlen', () {
    test('Fotos, Videos, Tage, Länder, Orte und Monate', () {
      final z = jahreszahlen([
        aufnahme('a', DateTime(2025, 3, 1, 9), land: 'DE', ort: 'Goslar'),
        aufnahme('b', DateTime(2025, 3, 1, 17), land: 'DE', ort: 'Goslar'),
        aufnahme('c', DateTime(2025, 7, 4), video: true, land: 'IT'),
        aufnahme('d', DateTime(2025, 7, 9), geraten: true),
      ]);
      expect(z.fotos, 3);
      expect(z.videos, 1);
      expect(z.tage, 2, reason: 'zwei am selben Tag, eins geraten');
      expect(z.laender, {'DE', 'IT'});
      expect(z.orte, {'Goslar'});
      expect(z.jeMonat[2], 2);
      expect(z.jeMonat[6], 2);
      expect(z.staerksterMonat, 3, reason: 'bei Gleichstand der frühere');
    });

    test('ein leeres Jahr hat keinen stärksten Monat', () {
      expect(jahreszahlen(const []).staerksterMonat, isNull);
    });
  });

  group('Auswahl', () {
    test(
      'jeder Monat mit Fotos kommt vor, auch neben einem Favoritenurlaub',
      () {
        final urlaub = [
          for (var i = 0; i < 30; i++)
            aufnahme('u$i', DateTime(2025, 8, 1 + i % 28), favorit: true),
        ];
        final auswahl = jahresauswahl([
          ...urlaub,
          aufnahme('jan', DateTime(2025, 1, 5)),
          aufnahme('mai', DateTime(2025, 5, 5)),
        ], groesse: 6);
        expect(auswahl, hasLength(6));
        expect(auswahl, containsAll(['jan', 'mai']));
        expect(auswahl.first, 'jan', reason: 'nach Datum geordnet');
      },
    );

    test('innerhalb eines Monats: Favorit vor Sternen vor Schärfe', () {
      final auswahl = jahresauswahl([
        aufnahme('scharf', DateTime(2025, 2, 1), schaerfe: 900),
        aufnahme('sterne', DateTime(2025, 2, 2), bewertung: 4),
        aufnahme('favorit', DateTime(2025, 2, 3), favorit: true),
      ], groesse: 1);
      expect(auswahl, ['favorit']);
      expect(
        jahresauswahl([
          aufnahme('scharf', DateTime(2025, 2, 1), schaerfe: 900),
          aufnahme('weich', DateTime(2025, 2, 2), schaerfe: 10),
        ], groesse: 1),
        ['scharf'],
      );
    });

    test('Videos und geratene Daten kommen nicht hinein', () {
      expect(
        jahresauswahl([
          aufnahme('v', DateTime(2025, 1, 1), video: true, favorit: true),
          aufnahme('g', DateTime(2025, 1, 1), geraten: true, favorit: true),
          aufnahme('f', DateTime(2025, 1, 2)),
        ]),
        ['f'],
      );
    });
  });
}
