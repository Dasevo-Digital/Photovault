import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/marian_tokenizer.dart';

/// Prüft die Zerlegung gegen die echte Bibliothek `tokenizers`.
///
/// Die erwarteten Stückfolgen stammen aus einem realen Lauf von
/// `Tokenizer.from_file()` auf der `tokenizer.json` von
/// `Xenova/opus-mt-en-de` – keine ausgedachten Werte. Verglichen werden
/// **Stücke**, nicht Kennungen: Die Fixture ist eine Teilmenge des
/// Vokabulars und damit anders nummeriert, aber die Zerlegung selbst muss
/// dieselbe sein.
///
/// Die Teilmenge ist dafür eigens **teilzeichenketten-abgeschlossen**
/// gewählt: Sie enthält jedes Stück des echten Vokabulars, das in einem
/// der Testwörter überhaupt vorkommen kann. Ein weggelassenes Stück hätte
/// also nie passen können – die beste Zerlegung über die Teilmenge ist
/// damit beweisbar dieselbe wie über alle 58101 Einträge.
void main() {
  late MarianTokenizer tok;

  setUpAll(() async {
    final roh = await File('test/fixtures/marian_vocab_subset.json').readAsString();
    tok = MarianTokenizer.fromJson(jsonDecode(roh) as Map<String, dynamic>);
  });

  /// Übersetzt Kennungen zurück in ihre Stücke – für den Vergleich mit der
  /// Referenz, die Stücke ausgibt.
  List<String> stuecke(List<int> ids) {
    final vokabular = jsonDecode(File('test/fixtures/marian_vocab_subset.json').readAsStringSync())
        as Map<String, dynamic>;
    final liste = (vokabular['model']['vocab'] as List).map((e) => e[0] as String).toList();
    return [for (final id in ids) liste[id]];
  }

  group('Zerlegung gegen die Referenz', () {
    // Jeweils die Stückfolge, die `tokenizers` für denselben Text liefert
    // (ohne das angehängte Satzende, das separat geprüft wird).
    const erwartet = <String, List<String>>{
      'a dog running on the beach': ['▁a', '▁dog', '▁running', '▁on', '▁the', '▁beach'],
      'sunset over the sea': ['▁sunset', '▁over', '▁the', '▁sea'],
      'A man riding a horse.': ['▁A', '▁man', '▁riding', '▁a', '▁horse', '.'],
      'birthday cake with candles': ['▁birthday', '▁cake', '▁with', '▁candles'],
      'two children playing in the snow': [
        '▁two', '▁children', '▁playing', '▁in', '▁the', '▁snow',
      ],
    };

    for (final eintrag in erwartet.entries) {
      test('„${eintrag.key}"', () {
        final ids = tok.encode(eintrag.key);
        expect(ids.last, MarianTokenizer.eosId, reason: 'Satzende muss angehängt werden');
        expect(stuecke(ids.sublist(0, ids.length - 1)), eintrag.value);
      });
    }
  });

  test('mehrfacher Leerraum fällt weg', () {
    // Nicht Nachlässigkeit, sondern das Verhalten der Vorlage: erst
    // WhitespaceSplit, dann Metaspace je Wort. Referenz liefert
    // ▁a ▁double ▁space.
    final ids = tok.encode('a  double   space');
    expect(stuecke(ids.sublist(0, ids.length - 1)), ['▁a', '▁double', '▁space']);
  });

  test('führender und abschliessender Leerraum stören nicht', () {
    expect(tok.encode('  sunset over the sea  '), tok.encode('sunset over the sea'));
  });

  test('ein unbekanntes Zeichen wird zu unkId, nicht zu <unk>', () {
    // Die Referenz liefert für „a ☃ b" die Stücke ▁a, ▁, ☃, ▁b – wobei ☃
    // die Kennung 2 bekommt, obwohl <unk> im Vokabular an Position 1
    // steht. Das Modell führt seine eigene unk_id.
    final ids = tok.encode('a ☃ b');
    expect(ids.last, MarianTokenizer.eosId);
    final ohneEnde = ids.sublist(0, ids.length - 1);
    expect(ohneEnde, hasLength(4));
    expect(stuecke([ohneEnde[0]]), ['▁a']);
    expect(stuecke([ohneEnde[1]]), ['▁']);
    expect(ohneEnde[2], tok.unkId, reason: 'das unbekannte Zeichen');
    expect(stuecke([ohneEnde[3]]), ['▁b']);
  });

  test('eine leere Eingabe ergibt nur das Satzende', () {
    expect(tok.encode(''), [MarianTokenizer.eosId]);
    expect(tok.encode('   '), [MarianTokenizer.eosId]);
  });

  group('Zusammensetzen', () {
    test('macht aus Stücken wieder Text', () {
      // Rundlauf über die Zerlegung: Was hineingeht, muss herauskommen.
      for (final satz in [
        'a dog running on the beach',
        'sunset over the sea',
        'birthday cake with candles',
      ]) {
        expect(tok.decode(tok.encode(satz)), satz);
      }
    });

    test('Sondertoken erscheinen nicht im Text', () {
      final ids = tok.encode('sunset over the sea');
      expect(
        tok.decode([MarianTokenizer.padId, ...ids, MarianTokenizer.eosId]),
        'sunset over the sea',
      );
    });

    test('Kennungen ausserhalb des Vokabulars werden übergangen', () {
      // Ein Modell kann theoretisch alles ausgeben; ein Absturz beim
      // Zusammensetzen wäre die schlechteste Antwort darauf.
      expect(tok.decode([999999, -1]), '');
    });
  });

  test('das Satzende ist 0 und der Decoder-Start das Füllzeichen', () {
    // Beide aus der generation_config.json von Xenova/opus-mt-en-de.
    // Marian startet den Decoder NICHT mit dem Satzende, wie sonst üblich.
    expect(MarianTokenizer.eosId, 0);
    expect(MarianTokenizer.padId, 58100);
  });
}
