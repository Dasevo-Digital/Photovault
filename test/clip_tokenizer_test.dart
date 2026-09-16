import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/clip_tokenizer.dart';

/// Testet den BPE-Tokenizer gegen eine kleine, handgeschriebene
/// vocab.json/merges.txt (test/fixtures/clip/) statt der echten ~1MB
/// CLIP-Vokabeldateien – deckt damit die Merge-Reihenfolge, das
/// Vokabular-Lookup, das Überspringen unbekannter Wortstücke und die
/// Kürzung auf [ClipTokenizer.contextLength] ab, ohne echte Modelldateien
/// zu benötigen.
void main() {
  late ClipTokenizer tokenizer;

  setUpAll(() async {
    tokenizer = await ClipTokenizer.loadFromFiles(
      vocabJsonPath: p.join('test', 'fixtures', 'clip', 'vocab.json'),
      mergesTxtPath: p.join('test', 'fixtures', 'clip', 'merges.txt'),
    );
  });

  test('mehrfach gemergtes Wort ergibt genau ein bekanntes Token, umrahmt von Start-/Endmarker', () {
    final ids = tokenizer.encode('cat');

    expect(ids.length, ClipTokenizer.contextLength);
    expect(ids[0], 0); // <|startoftext|>
    expect(ids[1], 5); // 'cat</w>' nach zwei BPE-Merges (c+a -> ca, ca+t</w> -> cat</w>)
    expect(ids[2], 1); // <|endoftext|>
    expect(ids.skip(3), everyElement(0)); // Padding
  });

  test('Wortstücke ohne Vokabeleintrag werden übersprungen statt einen Fehler zu werfen', () {
    final ids = tokenizer.encode('zz'); // 'z' und 'z</w>' existieren nicht im Fixture-Vokabular

    expect(ids[0], 0);
    expect(ids[1], 1); // sofort <|endoftext|>, da kein Piece von "zz" bekannt ist
    expect(ids.skip(2), everyElement(0));
  });

  test('Sequenzen länger als contextLength werden gekürzt und enden trotzdem mit <|endoftext|>', () {
    final ids = tokenizer.encode('x' * 100); // 100 Buchstaben, keine Merge-Regel für "x x" vorhanden

    expect(ids.length, ClipTokenizer.contextLength);
    expect(ids.first, 0);
    expect(ids.last, 1);
    // Die ersten 75 x-Tokens (id 20) bleiben erhalten, das abschließende
    // 'x</w>'-Token (id 21) fällt der Kürzung zum Opfer.
    expect(ids.sublist(1, ClipTokenizer.contextLength - 1), everyElement(20));
  });
}
