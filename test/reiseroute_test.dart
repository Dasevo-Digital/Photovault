import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/reiseroute.dart';

/// Route und Tageskapitel einer Reise.
void main() {
  Routenpunkt p(double b, double l, int stunde) =>
      (breite: b, laenge: l, zeit: DateTime(2024, 6, 3, stunde));

  group('Die Route', () {
    test('fasst dicht beieinanderliegende Aufnahmen zusammen', () {
      // An der echten Bibliothek: 356 Aufnahmen, davon ueber dreihundert
      // an derselben Stelle. Als Linie waeren das dreihundert
      // deckungsgleiche Ecken.
      final route = reiseroute([
        for (var i = 0; i < 50; i++) p(41.900, 12.500, i % 24),
      ]);
      expect(route, hasLength(1),
          reason: 'auch der letzte Punkt faellt weg – er liegt dort, wo der '
              'erste schon steht');
    });

    test('behaelt weit auseinanderliegende Punkte', () {
      final route = reiseroute([
        p(41.90, 12.50, 9),
        p(43.77, 11.26, 12),
        p(45.44, 12.32, 18),
      ]);
      expect(route, hasLength(3));
    });

    test('der letzte Punkt bleibt immer stehen', () {
      // Wo eine Reise endet, ist eine Angabe, auch wenn der Rueckweg
      // kurz war.
      final route = reiseroute([
        p(41.900, 12.500, 9),
        p(43.770, 11.260, 12),
        // Nur wenige Meter vom vorigen entfernt – wuerde sonst wegfallen.
        p(43.7702, 11.2602, 20),
      ]);
      expect(route.last.zeit.hour, 20);
      expect(route, hasLength(3));
    });

    test('sortiert nach Zeit, nicht nach Eingabereihenfolge', () {
      final route = reiseroute([
        p(45.44, 12.32, 18),
        p(41.90, 12.50, 9),
      ]);
      expect(route.first.zeit.hour, 9);
    });

    test('ein einzelner Punkt bleibt ein Punkt', () {
      expect(reiseroute([p(41.9, 12.5, 9)]), hasLength(1));
      expect(reiseroute(const []), isEmpty);
    });
  });

  group('Die Tageskapitel', () {
    ({String id, DateTime zeit, String? stadt}) a(
            String id, DateTime zeit, String? stadt) =>
        (id: id, zeit: zeit, stadt: stadt);

    test('teilen nach Kalendertagen', () {
      // Was um 23:50 aufgenommen wurde, gehoert zum 4. Juni und nicht zum
      // halben fuenften.
      final tage = reisetage([
        a('a', DateTime(2024, 6, 4, 23, 50), 'Roma'),
        a('b', DateTime(2024, 6, 5, 0, 10), 'Roma'),
      ]);
      expect(tage, hasLength(2));
      expect(tage.first.tag, DateTime(2024, 6, 4));
    });

    test('kommen chronologisch', () {
      final tage = reisetage([
        a('spaet', DateTime(2024, 6, 6, 10), 'Roma'),
        a('frueh', DateTime(2024, 6, 4, 10), 'Roma'),
      ]);
      expect(tage.map((t) => t.tag.day), [4, 6]);
    });

    test('der Ort eines Tages ist sein haeufigster', () {
      final tage = reisetage([
        a('1', DateTime(2024, 6, 4, 9), 'Firenze'),
        a('2', DateTime(2024, 6, 4, 15), 'Roma'),
        a('3', DateTime(2024, 6, 4, 16), 'Roma'),
      ]);
      expect(tage.single.ort, 'Roma');
    });

    test('ein Tag ohne verortete Aufnahme bleibt ohne Ort', () {
      // Richtiger als der Ort vom Vortag.
      final tage = reisetage([
        a('1', DateTime(2024, 6, 4, 9), 'Roma'),
        a('2', DateTime(2024, 6, 5, 9), null),
      ]);
      expect(tage.last.ort, isNull);
    });

    test('die Aufnahmen eines Tages stehen chronologisch', () {
      final tage = reisetage([
        a('mittag', DateTime(2024, 6, 4, 12), null),
        a('morgen', DateTime(2024, 6, 4, 8), null),
      ]);
      expect(tage.single.aufnahmeIds, ['morgen', 'mittag']);
    });
  });

  group('aufenthaltsorte', () {
    Aufenthaltsaufnahme a(String id, double breite, double laenge, int tag,
            {String? stadt}) =>
        (
          id: id,
          breite: breite,
          laenge: laenge,
          zeit: DateTime(2024, 6, tag),
          stadt: stadt
        );

    test('Aufnahmen derselben Stadt werden ein Pin', () {
      // Rom und der Vatikan sind zwei Kilometer auseinander.
      final orte = aufenthaltsorte([
        a('a', 41.9028, 12.4964, 3, stadt: 'Roma'),
        a('b', 41.9022, 12.4539, 3, stadt: 'Città del Vaticano'),
        a('c', 41.8902, 12.4922, 4, stadt: 'Roma'),
      ]);
      expect(orte, hasLength(1));
      expect(orte.single.aufnahmeIds, ['a', 'b', 'c']);
      // Der haeufigste Name gewinnt, nicht der erste.
      expect(orte.single.name, 'Roma');
    });

    test('weit auseinander liegende Orte bleiben getrennt', () {
      final orte = aufenthaltsorte([
        a('rom', 41.9028, 12.4964, 3, stadt: 'Roma'),
        a('flo', 43.7696, 11.2558, 5, stadt: 'Firenze'),
      ]);
      expect(orte.map((o) => o.name), ['Roma', 'Firenze']);
    });

    test('die Reihenfolge ist die der ersten Aufnahme', () {
      final orte = aufenthaltsorte([
        a('spaet', 43.7696, 11.2558, 8),
        a('frueh', 41.9028, 12.4964, 3),
      ]);
      expect(orte.first.aufnahmeIds, ['frueh']);
      expect(orte.first.von, DateTime(2024, 6, 3));
      expect(orte.last.bis, DateTime(2024, 6, 8));
    });

    test('ohne Ortsnamen bleibt der Name leer statt geraten', () {
      final orte = aufenthaltsorte([a('a', 41.9, 12.5, 3)]);
      expect(orte.single.name, isNull);
    });

    test('eine Kette zieht die Gruppe nicht beliebig weit fort', () {
      // Drei Bilder in einer Reihe, je 12 km auseinander. Gemessen gegen
      // das jeweils letzte Bild waeren alle drei ein Aufenthaltsort ueber
      // 24 km, und der Pin laege auf keinem davon. Gegen die Mitte
      // gemessen ruecken die ersten beiden zusammen (Mitte 50,054), und
      // das dritte ist 18 km davon entfernt – also ein eigener Ort.
      final orte = aufenthaltsorte([
        a('a', 50.0, 8.0, 3),
        a('b', 50.108, 8.0, 3),
        a('c', 50.216, 8.0, 3),
      ]);
      expect(orte, hasLength(2));
      expect(orte.first.aufnahmeIds, ['a', 'b']);
      expect(orte.first.breite, closeTo(50.054, 0.001));
      expect(orte.last.aufnahmeIds, ['c']);
    });

    test('ein kleinerer Radius zerlegt dieselben Bilder feiner', () {
      // Die Gegenprobe zum Radius: Ohne sie stuende nur die Behauptung da,
      // die 15 km machten einen Unterschied.
      final bilder = [
        a('rom', 41.9028, 12.4964, 3),
        a('vat', 41.9022, 12.4539, 3),
      ];
      expect(aufenthaltsorte(bilder), hasLength(1));
      expect(aufenthaltsorte(bilder, radiusKm: 1), hasLength(2));
    });

    test('ohne Aufnahmen gibt es keine Orte', () {
      expect(aufenthaltsorte(const []), isEmpty);
    });
  });
}
