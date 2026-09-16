import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/fotostatistik.dart';

/// Die Auswertung der Bilder statt der Kirchenbücher.
Fotoauftritt _a(String person, String bild, int jahr,
        [int monat = 6, int tag = 1]) =>
    (personId: person, assetId: bild, zeit: DateTime(jahr, monat, tag));

void main() {
  test('ohne Auftritte ist die Auswertung leer, nicht falsch', () {
    final s = fotostatistik(auftritte: const [], betrachtet: {'a', 'b'});
    expect(s.istLeer, isTrue);
    expect(s.aufnahmen, 0);
    expect(s.personen, isEmpty);
    // Und sie sagt, dass zwei fehlen.
    expect(s.ohneBild, 2);
  });

  test('zaehlt Aufnahmen je Person, haeufigste zuerst', () {
    final s = fotostatistik(
      auftritte: [
        _a('anna', 'b1', 2020),
        _a('anna', 'b2', 2021),
        _a('bert', 'b1', 2020),
      ],
      betrachtet: {'anna', 'bert'},
    );
    expect([for (final p in s.personen) p.personId], ['anna', 'bert']);
    expect(s.personen.first.aufnahmen, 2);
  });

  test('ein Familienfoto ist ein Bild und nicht vier', () {
    // Der Fehler, der plausibel aussieht: Gesichter zaehlen statt Bilder.
    final s = fotostatistik(
      auftritte: [
        _a('a', 'familie', 2020),
        _a('b', 'familie', 2020),
        _a('c', 'familie', 2020),
        _a('d', 'familie', 2020),
      ],
      betrachtet: {'a', 'b', 'c', 'd'},
    );
    expect(s.aufnahmen, 1);
    expect(s.jeJahr, {2020: 1});
  });

  test('zweimal dieselbe Person auf einem Bild zaehlt einmal', () {
    // Kommt vor: ein Spiegel, ein Bild im Bild, oder schlicht eine
    // doppelte Erkennung.
    final s = fotostatistik(
      auftritte: [_a('anna', 'b1', 2020), _a('anna', 'b1', 2020)],
      betrachtet: {'anna'},
    );
    expect(s.personen.single.aufnahmen, 1);
  });

  test('erste und letzte Aufnahme, und wie viele Jahre dazwischen liegen',
      () {
    final s = fotostatistik(
      auftritte: [
        _a('anna', 'b2', 2026, 8, 20),
        _a('anna', 'b1', 2014, 5, 4),
        _a('anna', 'b3', 2014, 9, 9),
      ],
      betrachtet: {'anna'},
    );
    final p = s.personen.single;
    expect(p.erste, DateTime(2014, 5, 4));
    expect(p.letzte, DateTime(2026, 8, 20));
    // Zwoelf Jahre Abstand, aber nur zwei Jahre Anwesenheit.
    expect(p.jahre, 2);
  });

  test('das Alter auf dem Bild kommt aus dem Geburtsdatum', () {
    final s = fotostatistik(
      auftritte: [_a('kind', 'b1', 2020, 1, 1), _a('kind', 'b2', 2026, 1, 1)],
      betrachtet: {'kind'},
      geburt: {'kind': DateTime(2018, 6, 15)},
    );
    final p = s.personen.single;
    expect(p.alterErste, 1);
    expect(p.alterLetzte, 7);
  });

  test('ohne Geburtsdatum bleibt das Alter leer statt geraten', () {
    final s = fotostatistik(
      auftritte: [_a('x', 'b1', 2020)],
      betrachtet: {'x'},
    );
    expect(s.personen.single.alterErste, isNull);
  });

  test('gemeinsame Auftritte, Paar nur einmal', () {
    final s = fotostatistik(
      auftritte: [
        _a('anna', 'b1', 2020), _a('bert', 'b1', 2020),
        _a('anna', 'b2', 2021), _a('bert', 'b2', 2021),
        _a('anna', 'b3', 2022), _a('cara', 'b3', 2022),
      ],
      betrachtet: {'anna', 'bert', 'cara'},
    );
    expect(s.paare, hasLength(2));
    expect(s.paare.first, (a: 'anna', b: 'bert', aufnahmen: 2));
    expect(s.paare.last, (a: 'anna', b: 'cara', aufnahmen: 1));
  });

  test('ein Bild mit nur einer Person ergibt kein Paar', () {
    final s = fotostatistik(
      auftritte: [_a('anna', 'b1', 2020)],
      betrachtet: {'anna'},
    );
    expect(s.paare, isEmpty);
  });

  test('Fremde bleiben draussen – auch aus den Paaren', () {
    // „Wer ist oft mit wem im Bild" soll die Familie beschreiben. Ein
    // Gast, der auf jedem Geburtstagsfoto steht, wuerde die Liste sonst
    // anfuehren.
    final s = fotostatistik(
      auftritte: [
        _a('anna', 'b1', 2020),
        _a('gast', 'b1', 2020),
        _a('bert', 'b1', 2020),
      ],
      betrachtet: {'anna', 'bert'},
    );
    expect([for (final p in s.personen) p.personId], ['anna', 'bert']);
    expect(s.paare.single, (a: 'anna', b: 'bert', aufnahmen: 1));
    expect(s.ohneBild, 0);
  });

  test('die Zahl der Paare laesst sich deckeln', () {
    final s = fotostatistik(
      auftritte: [
        for (var i = 0; i < 5; i++) _a('p$i', 'gruppe', 2020),
      ],
      betrachtet: {for (var i = 0; i < 5; i++) 'p$i'},
      hoechstensPaare: 3,
    );
    // Fuenf Personen auf einem Bild sind zehn Paare.
    expect(s.paare, hasLength(3));
  });

  test('bei gleicher Zahl entscheidet der Name, nicht der Zufall', () {
    // Ohne feste Reihenfolge sprangen die Zeilen bei jedem Aufbau.
    final s = fotostatistik(
      auftritte: [
        _a('zora', 'b1', 2020),
        _a('anna', 'b2', 2020),
      ],
      betrachtet: {'zora', 'anna'},
    );
    expect([for (final p in s.personen) p.personId], ['anna', 'zora']);
  });

  test('die Jahresverteilung zaehlt Bilder, nicht Gesichter', () {
    final s = fotostatistik(
      auftritte: [
        _a('a', 'b1', 2020), _a('b', 'b1', 2020),
        _a('a', 'b2', 2020),
        _a('a', 'b3', 2021),
      ],
      betrachtet: {'a', 'b'},
    );
    expect(s.jeJahr, {2020: 2, 2021: 1});
    expect(s.aufnahmen, 3);
  });
}
