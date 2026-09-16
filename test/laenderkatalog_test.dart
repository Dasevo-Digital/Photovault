import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/laenderkatalog.dart';

// Auszug im Format von countryInfo.txt: Spalte 0 ISO, 4 Name,
// 5 Hauptstadt, 8 Erdteil.
String _land(String iso, String name, String hauptstadt, String erdteil) =>
    [iso, '${iso}X', '000', 'XX', name, hauptstadt, '1', '2', erdteil]
        .join('\t');

void main() {
  group('Laenderkatalog', () {
    test('liest Name, Hauptstadt und Erdteil aus der Zeile', () {
      final k = Laenderkatalog.aus(
        countryInfoZeilen: [
          '# eine Kommentarzeile',
          _land('DE', 'Germany', 'Berlin', 'EU'),
        ],
        admin1Zeilen: const [],
      );
      final de = k.nachIso('DE')!;
      expect(de.name, 'Germany');
      expect(de.hauptstadt, 'Berlin');
      expect(de.kontinent, 'EU');
    });

    test('zählt die Regionen je Land', () {
      final k = Laenderkatalog.aus(
        countryInfoZeilen: [
          _land('DE', 'Germany', 'Berlin', 'EU'),
          _land('AF', 'Afghanistan', 'Kabul', 'AS'),
        ],
        admin1Zeilen: [
          'DE.02\tHamburg\tHamburg\t1',
          'DE.09\tBavaria\tBavaria\t2',
          'AF.01\tBadakhshan\tBadakhshan\t3',
        ],
      );
      expect(k.nachIso('DE')!.regionen, 2);
      expect(k.nachIso('AF')!.regionen, 1);
    });

    test('ein Land ohne Regionen hat 0 und fliegt nicht raus', () {
      final k = Laenderkatalog.aus(
        countryInfoZeilen: [_land('MC', 'Monaco', 'Monaco', 'EU')],
        admin1Zeilen: const ['DE.02\tHamburg\tHamburg\t1'],
      );
      expect(k.nachIso('MC')!.regionen, 0);
      expect(k.anzahl, 1);
    });

    test('fehlende Hauptstadt wird null statt leerem Text', () {
      final k = Laenderkatalog.aus(
        countryInfoZeilen: [_land('AQ', 'Antarctica', '', 'AN')],
        admin1Zeilen: const [],
      );
      expect(k.nachIso('AQ')!.hauptstadt, isNull);
    });

    test('zu kurze Zeilen werden übersprungen, nicht geworfen', () {
      final k = Laenderkatalog.aus(
        countryInfoZeilen: const ['DE\tDEU\t276', ''],
        admin1Zeilen: const [],
      );
      expect(k.anzahl, 0);
    });

    test('sortiert nach Namen, nicht nach Code', () {
      final k = Laenderkatalog.aus(
        countryInfoZeilen: [
          _land('DE', 'Germany', 'Berlin', 'EU'),
          _land('AT', 'Austria', 'Vienna', 'EU'),
          _land('ZW', 'Zimbabwe', 'Harare', 'AF'),
        ],
        admin1Zeilen: const [],
      );
      expect([for (final l in k.laender) l.iso], ['AT', 'DE', 'ZW']);
    });

    test('nachIso findet auch bei Kleinschreibung', () {
      final k = Laenderkatalog.aus(
        countryInfoZeilen: [_land('DE', 'Germany', 'Berlin', 'EU')],
        admin1Zeilen: const [],
      );
      expect(k.nachIso('de')?.iso, 'DE');
    });

    test('ein doppelter Code gewinnt beim ersten Mal', () {
      final k = Laenderkatalog.aus(
        countryInfoZeilen: [
          _land('DE', 'Germany', 'Berlin', 'EU'),
          _land('DE', 'Zweitfassung', 'Bonn', 'EU'),
        ],
        admin1Zeilen: const [],
      );
      expect(k.anzahl, 1);
      expect(k.nachIso('DE')!.name, 'Germany');
    });
  });

  group('flaggeAus', () {
    test('macht aus dem Code zwei regionale Anzeigezeichen', () {
      expect(flaggeAus('DE'), '\u{1F1E9}\u{1F1EA}');
      expect(flaggeAus('PL'), '\u{1F1F5}\u{1F1F1}');
    });

    test('Kleinschreibung geht auch', () {
      expect(flaggeAus('de'), flaggeAus('DE'));
    });

    test('gibt null statt leerer Kästchen, wenn der Code nicht passt', () {
      expect(flaggeAus(''), isNull);
      expect(flaggeAus('D'), isNull);
      expect(flaggeAus('DEU'), isNull);
      expect(flaggeAus('D1'), isNull);
    });
  });
}
