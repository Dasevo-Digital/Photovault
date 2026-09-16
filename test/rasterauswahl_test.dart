import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/rasterauswahl.dart';

void main() {
  group('klickartAus', () {
    test('ohne Zusatztaste ist einfach', () {
      expect(klickartAus({}), Klickart.einfach);
      expect(klickartAus({LogicalKeyboardKey.keyA}), Klickart.einfach);
    });

    test('Umschalt links wie rechts ergibt Bereich', () {
      expect(klickartAus({LogicalKeyboardKey.shiftLeft}), Klickart.bereich);
      expect(klickartAus({LogicalKeyboardKey.shiftRight}), Klickart.bereich);
    });

    test('Strg und Command ergeben beide einzeln', () {
      expect(klickartAus({LogicalKeyboardKey.controlLeft}), Klickart.einzeln);
      expect(klickartAus({LogicalKeyboardKey.metaLeft}), Klickart.einzeln);
    });

    test('zusammen gedrückt gewinnt die Umschalttaste', () {
      expect(
        klickartAus({LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.metaLeft}),
        Klickart.bereich,
      );
    });
  });

  group('auswahlMitBereich', () {
    final reihe = ['a', 'b', 'c', 'd', 'e'];

    test('nimmt alles zwischen Anker und Ziel dazu', () {
      expect(auswahlMitBereich(reihe, {'b'}, 'b', 'd'), {'b', 'c', 'd'});
    });

    test('funktioniert auch rückwärts', () {
      expect(auswahlMitBereich(reihe, {'d'}, 'd', 'b'), {'b', 'c', 'd'});
    });

    test('vereinigt, statt Bestehendes ausserhalb wegzuwerfen', () {
      // Der Befund, um den es geht: Ein Umschalt-Klick darf die vorher
      // ausgewählte 'a' nicht stillschweigend verlieren.
      expect(auswahlMitBereich(reihe, {'a'}, 'c', 'd'), {'a', 'c', 'd'});
    });

    test('Anker gleich Ziel wählt genau eines', () {
      expect(auswahlMitBereich(reihe, {}, 'c', 'c'), {'c'});
    });

    test('unbekannter Anker nimmt nur das Ziel, rät keinen Bereich', () {
      expect(auswahlMitBereich(reihe, {}, 'weg', 'd'), {'d'});
    });

    test('lässt die übergebene Menge unangetastet', () {
      final vorher = {'a'};
      auswahlMitBereich(reihe, vorher, 'b', 'd');
      expect(vorher, {'a'});
    });
  });

  group('nachbarkachel', () {
    // Zwei Monate: der erste mit sieben, der zweite mit vier Aufnahmen.
    final gruppen = [
      ['a1', 'a2', 'a3', 'a4', 'a5', 'a6', 'a7'],
      ['b1', 'b2', 'b3', 'b4'],
    ];

    String? geh(String von, Rasterrichtung r, {int spalten = 3}) =>
        nachbarkachel(gruppen: gruppen, von: von, richtung: r, spalten: spalten);

    test('links und rechts laufen über die Monatsgrenze', () {
      expect(geh('a7', Rasterrichtung.rechts), 'b1');
      expect(geh('b1', Rasterrichtung.links), 'a7');
    });

    test('am Anfang und Ende ist Schluss', () {
      expect(geh('a1', Rasterrichtung.links), isNull);
      expect(geh('b4', Rasterrichtung.rechts), isNull);
    });

    test('runter springt eine Zeile innerhalb des Monats', () {
      expect(geh('a1', Rasterrichtung.runter), 'a4');
      expect(geh('a4', Rasterrichtung.runter), 'a7');
    });

    test('hoch springt eine Zeile zurück', () {
      expect(geh('a7', Rasterrichtung.hoch), 'a4');
      expect(geh('a4', Rasterrichtung.hoch), 'a1');
    });

    test('runter aus der letzten Zeile landet im nächsten Monat, gleiche Spalte', () {
      // a5 steht in Spalte 1 (0-basiert) der zweiten Zeile; unter ihm ist
      // nichts mehr, also erste Zeile des Folgemonats, Spalte 1.
      expect(geh('a5', Rasterrichtung.runter), 'b2');
    });

    test('runter rückt auf die letzte belegte Kachel, wenn die Spalte fehlt', () {
      // b1..b4 bei drei Spalten: zweite Zeile hat nur b4 (Spalte 0). Von a6
      // (Spalte 2) aus gibt es dort keine Spalte 2.
      expect(
        nachbarkachel(
          gruppen: [
            ['a1', 'a2', 'a3'],
            ['b1', 'b2'],
          ],
          von: 'a3',
          richtung: Rasterrichtung.runter,
          spalten: 3,
        ),
        'b2',
      );
    });

    test('hoch aus der ersten Zeile landet in der letzten Zeile davor', () {
      // b2 steht in Spalte 1; letzte Zeile des Vormonats beginnt bei a7
      // (Index 6), Spalte 1 wäre Index 7 – nicht belegt, also a7.
      expect(geh('b2', Rasterrichtung.hoch), 'a7');
    });

    test('hoch aus dem ersten Monat gibt es nicht', () {
      expect(geh('a2', Rasterrichtung.hoch), isNull);
    });

    test('leere Zwischengruppen werden übersprungen', () {
      expect(
        nachbarkachel(
          gruppen: [
            ['a1'],
            <String>[],
            ['c1'],
          ],
          von: 'a1',
          richtung: Rasterrichtung.runter,
          spalten: 3,
        ),
        'c1',
      );
    });

    test('unbekannte Kachel ergibt null statt einer geratenen', () {
      expect(geh('weg', Rasterrichtung.rechts), isNull);
    });

    test('null Spalten ergeben null statt einer Division durch null', () {
      expect(geh('a1', Rasterrichtung.runter, spalten: 0), isNull);
    });
  });

  group('tastenziel', () {
    test('die Auswahl hat Vorrang vor der aktiven Kachel', () {
      expect(tastenziel({'a', 'b'}, 'c'), unorderedEquals(['a', 'b']));
    });

    test('ohne Auswahl wirkt die Taste auf die aktive Kachel', () {
      expect(tastenziel({}, 'c'), ['c']);
    });

    test('ohne beides passiert nichts', () {
      expect(tastenziel({}, null), isEmpty);
    });
  });

  group('Zifferntasten', () {
    test('0 bis 5 sind Bewertungen', () {
      expect(bewertungFuerZiffer(LogicalKeyboardKey.digit0), 0);
      expect(bewertungFuerZiffer(LogicalKeyboardKey.digit5), 5);
      expect(bewertungFuerZiffer(LogicalKeyboardKey.digit6), isNull);
    });

    test('6 bis 9 sind Farbmarken in der gewohnten Reihenfolge', () {
      expect(farbmarkeFuerZiffer(LogicalKeyboardKey.digit6), 'red');
      expect(farbmarkeFuerZiffer(LogicalKeyboardKey.digit7), 'yellow');
      expect(farbmarkeFuerZiffer(LogicalKeyboardKey.digit8), 'green');
      expect(farbmarkeFuerZiffer(LogicalKeyboardKey.digit9), 'blue');
    });

    test('Bewertung und Farbmarke überschneiden sich nicht', () {
      for (final taste in [
        LogicalKeyboardKey.digit0,
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
        LogicalKeyboardKey.digit7,
        LogicalKeyboardKey.digit8,
        LogicalKeyboardKey.digit9,
      ]) {
        final beides =
            bewertungFuerZiffer(taste) != null && farbmarkeFuerZiffer(taste) != null;
        expect(beides, isFalse, reason: '$taste wäre doppelt belegt');
      }
    });
  });
}
