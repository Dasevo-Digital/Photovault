import 'dart:convert';
import 'dart:io';

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

  test(
    'mehrfach gemergtes Wort ergibt genau ein bekanntes Token, umrahmt von Start-/Endmarker',
    () {
      final ids = tokenizer.encode('cat');

      expect(ids.length, ClipTokenizer.contextLength);
      expect(ids[0], 0); // <|startoftext|>
      expect(
        ids[1],
        5,
      ); // 'cat</w>' nach zwei BPE-Merges (c+a -> ca, ca+t</w> -> cat</w>)
      expect(ids[2], 1); // <|endoftext|>
      expect(ids.skip(3), everyElement(0)); // Padding
    },
  );

  test(
    'Wortstücke ohne Vokabeleintrag werden übersprungen statt einen Fehler zu werfen',
    () {
      final ids = tokenizer.encode(
        'zz',
      ); // 'z' und 'z</w>' existieren nicht im Fixture-Vokabular

      expect(ids[0], 0);
      expect(
        ids[1],
        1,
      ); // sofort <|endoftext|>, da kein Piece von "zz" bekannt ist
      expect(ids.skip(2), everyElement(0));
    },
  );

  test('jede Ziffer ist ein eigenes Wort, wie im Original-CLIP', () async {
    // Als Folge zerlegt, wurde „19“ zu „1“ + „9</w>“ – Bytestücke, die das
    // echte Modell bei allen Zahlen gleich behandelt.
    final ordner = await Directory.systemTemp.createTemp('pv_clip_ziffern');
    addTearDown(() => ordner.delete(recursive: true));
    final vocab = File(p.join(ordner.path, 'vocab.json'))
      ..writeAsStringSync(
        jsonEncode({
          '<|startoftext|>': 0,
          '<|endoftext|>': 1,
          '1': 2,
          '9': 3,
          '1</w>': 4,
          '9</w>': 5,
          's</w>': 6,
        }),
      );
    final merges = File(p.join(ordner.path, 'merges.txt'))
      ..writeAsStringSync('#version: 0.2\n');
    final ziffern = await ClipTokenizer.loadFromFiles(
      vocabJsonPath: vocab.path,
      mergesTxtPath: merges.path,
    );

    expect(ziffern.encode('19s').take(5), [0, 4, 5, 6, 1]);
  });

  test(
    'Sequenzen länger als contextLength werden gekürzt und enden trotzdem mit <|endoftext|>',
    () {
      final ids = tokenizer.encode(
        'x' * 100,
      ); // 100 Buchstaben, keine Merge-Regel für "x x" vorhanden

      expect(ids.length, ClipTokenizer.contextLength);
      expect(ids.first, 0);
      expect(ids.last, 1);
      // Die ersten 75 x-Tokens (id 20) bleiben erhalten, das abschließende
      // 'x</w>'-Token (id 21) fällt der Kürzung zum Opfer.
      expect(ids.sublist(1, ClipTokenizer.contextLength - 1), everyElement(20));
    },
  );
}
