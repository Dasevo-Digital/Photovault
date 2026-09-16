import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/lebenslauf.dart';
import 'package:photo_vault/services/zeitleiste.dart';

/// Die Rechnung hinter der Familien-Zeitleiste.
///
/// Auf dem fertigen Bild sieht ein Balken auch dann richtig aus, wenn er
/// an der falschen Stelle sitzt – erst als Zahl lässt sich das prüfen.
/// Geprüft wird deshalb die Lage auf der Achse, die Reihenfolge der
/// Zeilen und das, was die Leiste über Unbekanntes sagt.
void main() {
  EreignisEingabe e(String id, Ereignisart art, DateTime? datum) =>
      (id: id, art: art, datum: datum, ort: null, notiz: null);

  Zeitzeile person(String id, {DateTime? geb, DateTime? tod,
          List<EreignisEingabe> ereignisse = const []}) =>
      zeitzeile(
          personId: id,
          name: id,
          geburt: geb,
          tod: tod,
          ereignisse: ereignisse);

  group('Eine Zeile', () {
    test('Geburt und Tod stehen nicht doppelt in den Marken', () {
      // Sie sind die Enden des Balkens. Noch einmal als Marke gezeichnet
      // sähen sie aus wie zusätzliche Ereignisse.
      final z = person('a',
          geb: DateTime(1931, 4, 2),
          tod: DateTime(2004, 11, 9),
          ereignisse: [e('x', Ereignisart.hochzeit, DateTime(1955, 5, 14))]);
      expect(z.marken, hasLength(1));
      expect(z.marken.single.datum, DateTime(1955, 5, 14));
    });

    test('ein Ereignis ohne Datum bekommt keine Marke', () {
      // Es hätte auf der Achse keinen Ort. „Irgendwo" wäre eine
      // Behauptung.
      final z = person('a',
          geb: DateTime(1931),
          ereignisse: [e('x', Ereignisart.umzug, null)]);
      expect(z.marken, isEmpty);
    });

    test('die Marken kommen chronologisch', () {
      final z = person('a', geb: DateTime(1900), ereignisse: [
        e('spaet', Ereignisart.beruf, DateTime(1950)),
        e('frueh', Ereignisart.ausbildung, DateTime(1920)),
      ]);
      expect(z.marken.map((m) => m.datum.year), [1920, 1950]);
    });

    test('der frueheste Zeitpunkt ist nicht zwingend die Geburt', () {
      // Von manchen Vorfahren kennt man nur das Sterbejahr oder eine
      // Hochzeit. Sie deshalb auf Jahr 0 zu setzen verschöbe die ganze
      // Leiste.
      expect(person('a', tod: DateTime(1890)).frueheste, DateTime(1890));
      expect(
          person('b',
                  ereignisse: [e('x', Ereignisart.hochzeit, DateTime(1875))])
              .frueheste,
          DateTime(1875));
    });

    test('ein Ereignis nach dem Tod verlaengert die Zeile', () {
      // Umbettung, Nachlass – lebenslauf.dart lässt das ausdrücklich zu.
      final z = person('a',
          geb: DateTime(1900),
          tod: DateTime(1960),
          ereignisse: [e('x', Ereignisart.umzug, DateTime(1975))]);
      expect(z.spaeteste, DateTime(1975));
    });

    test('offen heisst: Geburt bekannt, Tod nicht', () {
      // Und bleibt zweideutig: „lebt noch" und „Sterbedatum unbekannt"
      // sind für diese App dasselbe, weil niemand danach gefragt hat.
      expect(person('a', geb: DateTime(1990)).offen, isTrue);
      expect(person('b', geb: DateTime(1900), tod: DateTime(1980)).offen,
          isFalse);
      expect(person('c', tod: DateTime(1980)).offen, isFalse,
          reason: 'ohne Geburt gibt es keinen Balken, der auslaufen könnte');
    });

    test('ohne jedes Datum ist die Zeile undatiert', () {
      expect(person('a').datiert, isFalse);
      expect(person('a').frueheste, isNull);
    });
  });

  group('Die Spanne', () {
    test('umfasst alle Zeilen', () {
      final s = zeitspanne([
        person('a', geb: DateTime(1901), tod: DateTime(1970)),
        person('b', geb: DateTime(1962)),
        person('c', tod: DateTime(1890)),
      ])!;
      expect(s.von, DateTime(1890));
      expect(s.bis, DateTime(1970));
    });

    test('undatierte Zeilen ziehen sie nicht auseinander', () {
      final s = zeitspanne([
        person('a', geb: DateTime(1901), tod: DateTime(1970)),
        person('leer'),
      ])!;
      expect(s.von, DateTime(1901));
    });

    test('ohne ein einziges Datum gibt es keine Spanne', () {
      expect(zeitspanne([person('a'), person('b')]), isNull);
      expect(zeitspanne(const []), isNull);
    });

    test('ein einzelner Zeitpunkt wird auf ein Jahr aufgezogen', () {
      // Sonst läge jede Lage bei 0,5 und die Jahresachse bliebe leer.
      final s = zeitspanne([person('a', geb: DateTime(1931, 7, 1))])!;
      expect(s.bis.difference(s.von).inDays, 366);
      expect(s.anteil(DateTime(1931, 7, 1)), closeTo(0.5, 0.01));
    });

    test('der Anteil rechnet linear', () {
      final spanne = Zeitspanne(DateTime(1900), DateTime(2000));
      expect(spanne.anteil(DateTime(1900)), 0);
      expect(spanne.anteil(DateTime(2000)), 1);
      expect(spanne.anteil(DateTime(1950)), closeTo(0.5, 0.01));
    });

    test('ein Zeitpunkt ausserhalb wird an den Rand geklammert', () {
      final spanne = Zeitspanne(DateTime(1900), DateTime(2000));
      expect(spanne.anteil(DateTime(1800)), 0);
      expect(spanne.anteil(DateTime(2100)), 1);
    });
  });

  group('Die Reihenfolge', () {
    test('von frueh nach spaet', () {
      final sortiert = nachZeitSortiert([
        person('spaet', geb: DateTime(1962)),
        person('frueh', geb: DateTime(1901)),
        person('mitte', geb: DateTime(1931)),
      ]);
      expect(sortiert.map((z) => z.personId), ['frueh', 'mitte', 'spaet']);
    });

    test('wer nur ein Sterbejahr hat, steht bei seiner Zeit', () {
      // Der Grund, warum nach dem frühesten bekannten Zeitpunkt sortiert
      // wird und nicht nach der Geburt. Ans Ende gehört, wer gar kein
      // Datum hat – nicht, wer eines hat, das zufällig nicht die Geburt
      // ist.
      final sortiert = nachZeitSortiert([
        person('jung', geb: DateTime(1990)),
        person('alt', tod: DateTime(1890)),
      ]);
      expect(sortiert.first.personId, 'alt');
    });

    test('undatierte Zeilen stehen hinten', () {
      final sortiert = nachZeitSortiert([
        person('ohne'),
        person('mit', geb: DateTime(1990)),
      ]);
      expect(sortiert.map((z) => z.personId), ['mit', 'ohne']);
    });

    test('bei gleichem Datum entscheidet der Name', () {
      // Ohne feste zweite Ordnung sprängen die Zeilen bei jedem Aufbau.
      final sortiert = nachZeitSortiert([
        Zeitzeile(personId: '2', name: 'Berta', geburt: DateTime(1900)),
        Zeitzeile(personId: '1', name: 'Anna', geburt: DateTime(1900)),
      ]);
      expect(sortiert.map((z) => z.name), ['Anna', 'Berta']);
    });
  });

  group('Die Jahresachse', () {
    test('nimmt runde Schritte', () {
      // „1900, 1920, 1940" liest sich, „1898, 1919, 1940" nicht. Bei 106
      // Jahren und höchstens acht Marken fällt die Wahl auf den
      // Zwanzigerschritt: Zehn ergäbe elf Marken, das ist eine zu viel.
      final marken =
          jahresmarken(Zeitspanne(DateTime(1898), DateTime(2004)));
      expect(marken, [1900, 1920, 1940, 1960, 1980, 2000]);
    });

    test('haelt die Obergrenze ein', () {
      for (final jahre in [5, 40, 120, 900, 3000]) {
        final marken = jahresmarken(
            Zeitspanne(DateTime(1000), DateTime(1000 + jahre)),
            hoechstens: 6);
        expect(marken.length, lessThanOrEqualTo(7), reason: '$jahre Jahre');
        expect(marken, isNotEmpty, reason: '$jahre Jahre');
      }
    });

    test('eine sehr kurze Spanne bekommt trotzdem eine Marke', () {
      final marken =
          jahresmarken(Zeitspanne(DateTime(1930, 6), DateTime(1931, 6)));
      expect(marken, [1930, 1931]);
    });
  });
}
