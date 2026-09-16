import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/bart_tokenizer.dart';

/// Der Wortzerleger der Sprachhälfte von Florence-2.
///
/// Geprüft gegen **echte** Kennungen: Die erwarteten Zahlen stammen aus
/// einem Lauf gegen die vollständige `vocab.json`/`merges.txt` des
/// Exports, nicht aus erfundenen Werten. Die Dateien unter
/// `test/fixtures/florence/` sind ein Ausschnitt daraus – dieselben
/// Zeichenketten, dieselben Kennungen, dieselbe Reihenfolge der
/// Merge-Regeln (deren Rang bestimmt das Ergebnis).
///
/// Der Zerleger ist die Stelle, an der ein Fehler am leisesten ist: Ein
/// falsches Wortende-Zeichen liefert lauter gültige Kennungen und
/// trotzdem Kauderwelsch.
void main() {
  late BartTokenizer tok;

  setUpAll(() async {
    tok = await BartTokenizer.loadFromFiles(
      vocabJsonPath: 'test/fixtures/florence/vocab_subset.json',
      mergesTxtPath: 'test/fixtures/florence/merges_subset.txt',
    );
  });

  group('Encodieren', () {
    test('die Aufgabenfrage ergibt genau die erwarteten Kennungen', () {
      // Diese Frage geht bei JEDER Bildbeschreibung an das Modell.
      expect(tok.encode('What does the image describe?'),
          [0, 2264, 473, 5, 2274, 6190, 116, 2]);
    });

    test('rahmt jede Eingabe mit <s> und </s>', () {
      final ids = tok.encode('A man in uniform standing in front of a military vehicle.');
      expect(ids.first, BartTokenizer.bosId);
      expect(ids.last, BartTokenizer.eosId);
    });

    test('das führende Leerzeichen gehört zum Wort, nicht ans Wortende', () {
      // Der Unterschied zu CLIP. „ man" ist ein anderes Stück als „man";
      // wer hier die CLIP-Regel anwendet, bekommt lauter gültige
      // Kennungen und trotzdem Unsinn.
      final mitte = tok.encode('A man in uniform standing in front of a military vehicle.');
      expect(mitte, [0, 250, 313, 11, 8284, 2934, 11, 760, 9, 10, 831, 1155, 4, 2]);
    });
  });

  group('Decodieren', () {
    test('macht aus den Kennungen wieder den Satz', () {
      expect(tok.decode([0, 250, 313, 11, 8284, 2934, 11, 760, 9, 10, 831, 1155, 4, 2]),
          'A man in uniform standing in front of a military vehicle.');
    });

    test('bringt Schrift aus dem Bild samt Anführungszeichen zurück', () {
      // Genau das kann das neue Modell und das alte nicht: Es liest
      // Ladenschilder. Ein Zerleger, der an Anführungszeichen scheitert,
      // machte den Gewinn wieder zunichte.
      expect(
          tok.decode([0, 250, 1203, 13, 10, 2391, 14, 161, 22, 23029, 3807, 918, 113, 15, 24, 4, 2]),
          'A sign for a restaurant that says "Peppies" on it.');
    });

    test('überspringt Sondertoken auch mitten im Satz', () {
      expect(tok.decode([250, 313, BartTokenizer.bosId, 11, 8284]),
          tok.decode([250, 313, 11, 8284]));
    });

    test('Hin und zurück ergibt wieder den Ausgangstext', () {
      for (final satz in [
        'What does the image describe?',
        'A man in uniform standing in front of a military vehicle.',
        'A sign for a restaurant that says "Peppies" on it.',
      ]) {
        expect(tok.decode(tok.encode(satz)), satz);
      }
    });
  });
}
