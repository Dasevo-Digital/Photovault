/// **Was der Vorrat hält und was er wegwirft.**
///
/// Geprüft mit Zahlen statt mit Bildern – die Verdrängung ist eine
/// Entscheidung, keine Grafik. Siehe `blockvorrat.dart`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/blockvorrat.dart';
import 'package:photo_vault/services/gelaendetextur.dart';

Texturblock _b(int spalte) =>
    Texturblock(spalte: spalte, zeile: 0, grundstufe: 16);

void main() {
  late List<int> freigegeben;
  late Blockvorrat<int> vorrat;

  setUp(() {
    freigegeben = [];
    vorrat = Blockvorrat<int>(
      hoechstensBytes: 1000,
      freigeben: freigegeben.add,
    );
  });

  test('was hineingelegt wurde, kommt wieder heraus', () {
    vorrat.lege(_b(1), 17, 42, 300);
    expect(vorrat.bei(_b(1), 17), 42);
    expect(vorrat.bei(_b(1), 18), isNull);
    expect(vorrat.bei(_b(2), 17), isNull);
    expect(vorrat.belegt, 300);
  });

  test('dieselbe Stufe zweimal ersetzt und gibt die alte frei', () {
    vorrat.lege(_b(1), 17, 42, 300);
    vorrat.lege(_b(1), 17, 43, 300);
    expect(vorrat.bei(_b(1), 17), 43);
    expect(vorrat.belegt, 300, reason: 'sonst zaehlt der Vorrat doppelt');
    expect(freigegeben, [42]);
  });

  test('bestes liefert die feinste vorhandene Fassung', () {
    vorrat.lege(_b(1), 16, 100, 100);
    vorrat.lege(_b(1), 18, 300, 300);
    expect(vorrat.bestes(_b(1))!.stufe, 18);
    expect(vorrat.bestes(_b(1))!.inhalt, 300);
    // Und mit Deckel die gröbere - genau der Rueckfall, waehrend die
    // feine noch laedt.
    expect(vorrat.bestes(_b(1), hoechstens: 17)!.stufe, 16);
    expect(vorrat.bestes(_b(9)), isNull);
  });

  group('Verdrängung', () {
    test('das Fernste geht zuerst', () {
      for (var i = 1; i <= 5; i++) {
        vorrat.lege(_b(i), 17, i, 300);
      }
      expect(vorrat.belegt, 1500);
      // Block 1 ist am naechsten, Block 5 am fernsten.
      vorrat.raeume((b) => b.spalte.toDouble());
      expect(vorrat.belegt, lessThanOrEqualTo(1000));
      expect(vorrat.bei(_b(5), 17), isNull);
      expect(vorrat.bei(_b(4), 17), isNull);
      expect(vorrat.bei(_b(1), 17), 1);
      expect(freigegeben, [5, 4]);
    });

    test('bei gleicher Entfernung faellt die feinere Fassung zuerst', () {
      // Beide Fassungen desselben Blocks: Die feine ist die teure, und
      // die grobe haelt die Stelle weiter besetzt.
      vorrat.lege(_b(1), 16, 16, 400);
      vorrat.lege(_b(1), 18, 18, 700);
      vorrat.raeume((b) => 1);
      expect(vorrat.bei(_b(1), 18), isNull);
      expect(vorrat.bei(_b(1), 16), 16);
      expect(freigegeben, [18]);
    });

    test('unter der Grenze wird gar nicht geraeumt', () {
      vorrat.lege(_b(1), 17, 1, 400);
      vorrat.lege(_b(2), 17, 2, 400);
      vorrat.raeume((b) => b.spalte.toDouble());
      expect(vorrat.anzahl, 2);
      expect(freigegeben, isEmpty);
    });

    test('was gezeichnet wird, bleibt - auch wenn es fern ist', () {
      for (var i = 1; i <= 5; i++) {
        vorrat.lege(_b(i), 17, i, 300);
      }
      vorrat.raeume((b) => b.spalte.toDouble(),
          behalten: (b, s) => b.spalte == 5);
      // Der ferne Block 5 haette als erster fallen muessen; er ist
      // geschuetzt, also faellt stattdessen der naechste.
      expect(vorrat.bei(_b(5), 17), 5);
      expect(vorrat.bei(_b(4), 17), isNull);
      expect(vorrat.belegt, lessThanOrEqualTo(1000));
    });

    test('geraeumt wird nur so weit wie noetig', () {
      for (var i = 1; i <= 4; i++) {
        vorrat.lege(_b(i), 17, i, 300);
      }
      // 1200 Bytes, Grenze 1000 - ein Stueck reicht.
      vorrat.raeume((b) => b.spalte.toDouble());
      expect(vorrat.anzahl, 3);
      expect(vorrat.belegt, 900);
    });
  });

  test('leeren gibt alles frei', () {
    vorrat.lege(_b(1), 17, 1, 300);
    vorrat.lege(_b(2), 18, 2, 300);
    vorrat.leeren();
    expect(vorrat.anzahl, 0);
    expect(vorrat.belegt, 0);
    expect(freigegeben, containsAll([1, 2]));
  });

  test('am Ilsetal: was 80 Bloecke bei 80 MB bedeuten', () {
    // Die echte Rechnung: Bei der feinsten Stufe sind vier Megabyte je
    // Block, also passen zwanzig hinein - von achtzig.
    const grenze = 80 * 1024 * 1024;
    final einer = const Texturblock(spalte: 0, zeile: 0, grundstufe: 16)
        .speicherBytes(18);
    expect(grenze ~/ einer, 20);
  });
}
