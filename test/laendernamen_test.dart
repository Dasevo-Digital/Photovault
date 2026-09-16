import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/laenderkatalog.dart';
import 'package:photo_vault/services/laendernamen.dart';

/// **In der deutschen Oberfläche stand „Germany".**
///
/// Der Länderkatalog kommt aus `countryInfo.txt` von GeoNames, und der
/// führt jedes Land nur englisch. An der gewachsenen Bibliothek waren
/// alle fünf vorkommenden Länder betroffen – Germany, Poland,
/// Afghanistan, Spain, Switzerland –, in der Länderliste ebenso wie im
/// Infoblatt jeder Aufnahme und im Suchfilter.
///
/// Die Namen stammen aus CLDR, demselben Datensatz, aus dem auch
/// Betriebssysteme ihre Ländernamen nehmen. Geprüft wird hier weniger die
/// Übersetzung als das, was sie **nicht** anfassen darf: den englischen
/// Namen in der Datenbank, die Regionen und Städte, und die englische
/// Oberfläche.
void main() {
  group('Der Name zur Anzeige', () {
    test('die fünf Länder der echten Bibliothek', () {
      expect(landAnzeige('Germany', 'de'), 'Deutschland');
      expect(landAnzeige('Poland', 'de'), 'Polen');
      expect(landAnzeige('Spain', 'de'), 'Spanien');
      expect(landAnzeige('Switzerland', 'de'), 'Schweiz');
      // Gleich in beiden Sprachen – und steht trotzdem in der Liste.
      expect(landAnzeige('Afghanistan', 'de'), 'Afghanistan');
    });

    test('auf Englisch bleibt alles, wie es ist', () {
      expect(landAnzeige('Germany', 'en'), 'Germany');
      expect(landAnzeige('Poland', 'en'), 'Poland');
    });

    test('was kein Land ist, kommt unveraendert zurueck', () {
      // Die Ortszeile reicht Ort, Region und Land durch dieselbe Stelle.
      expect(landAnzeige('Lower Saxony', 'de'), 'Lower Saxony');
      expect(landAnzeige('Hannover', 'de'), 'Hannover');
    });

    test('nichts wird zu nichts, nicht zu „null"', () {
      expect(landAnzeige(null, 'de'), '');
      expect(landAnzeige('', 'de'), '');
    });

    test('die Liste kennt jedes Land des Datensatzes', () {
      // 250 von 252 Einträgen aus countryInfo.txt.
      expect(laendernamenDe.length, 250);
      expect(laendernamenDe['DE'], 'Deutschland');
      expect(laendernamenDe['CD'], 'Kongo-Kinshasa');
      expect(laendernamenDe['VC'], 'St. Vincent und die Grenadinen');
    });

    test('die beiden aufgeloesten Codes fehlen mit Absicht', () {
      // GeoNames führt sie noch, CLDR beantwortet sie mit ihrem
      // Nachfolger. „AN" hiesse dann Curaçao und stünde zweimal in der
      // Liste, eines davon unter falschem Namen.
      expect(laendernamenDe.containsKey('AN'), isFalse);
      expect(laendernamenDe.containsKey('CS'), isFalse);
      expect(landAnzeige('Netherlands Antilles', 'de'), 'Netherlands Antilles');
      expect(landAnzeige('Serbia and Montenegro', 'de'),
          'Serbia and Montenegro');
    });

    test('kein deutscher Name steht fuer zwei Laender', () {
      // Die Falle, in die eine selbstgemachte Liste laeuft: Serbien und
      // Curaçao standen zweimal da.
      final namen = laendernamenDe.values.toList();
      expect(namen.toSet().length, namen.length);
    });
  });

  group('Der Katalog', () {
    /// Zwei Zeilen im Format von `countryInfo.txt` – 19 Spalten, davon
    /// zählen 0 (ISO), 4 (Name), 5 (Hauptstadt) und 8 (Erdteil).
    String zeile(String iso, String name, String hauptstadt) =>
        [iso, '', '', '', name, hauptstadt, '', '', 'EU', ...List.filled(10, '')]
            .join('\t');

    test('jeder Eintrag traegt beide Namen', () {
      final k = Laenderkatalog.aus(
        countryInfoZeilen: [zeile('DE', 'Germany', 'Berlin')],
        admin1Zeilen: const [],
      );
      final de = k.nachIso('DE')!;
      expect(de.name, 'Germany', reason: 'so steht es in den Aufnahmen');
      expect(de.nameDe, 'Deutschland');
      expect(de.anzeige('de'), 'Deutschland');
      expect(de.anzeige('en'), 'Germany');
    });

    test('ein unbekannter Code behaelt seinen englischen Namen', () {
      // Erfundene Codes gibt es nicht, aber der Datensatz waechst – und
      // ein englischer Name ist besser als ein leeres Feld.
      final k = Laenderkatalog.aus(
        countryInfoZeilen: [zeile('ZZ', 'Neuland', 'Neustadt')],
        admin1Zeilen: const [],
      );
      expect(k.nachIso('ZZ')!.nameDe, 'Neuland');
      expect(k.nachIso('ZZ')!.anzeige('de'), 'Neuland');
    });

    test('der Katalog uebersetzt auch, was nur als Name vorliegt', () {
      final k = Laenderkatalog.aus(
        countryInfoZeilen: [zeile('PL', 'Poland', 'Warsaw')],
        admin1Zeilen: const [],
      );
      expect(k.anzeige('Poland', 'de'), 'Polen');
      expect(k.anzeige('Poland', 'en'), 'Poland');
      // Auch ein Land, das der geladene Datensatz gar nicht führt.
      expect(k.anzeige('Germany', 'de'), 'Deutschland');
      expect(k.anzeige(null, 'de'), '');
    });
  });
}
