import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/reisen.dart';

/// Reisen aus den Aufnahmen selbst erkennen.
///
/// Der Kern von Punkt 11: kein leeres Formular, sondern ein Vorschlag,
/// den man bestätigt. Ob eine Häufung eine Reise ist, sieht man dem
/// fertigen Vorschlag nicht an – nachrechnen lässt es sich nur hier.
void main() {
  // Hamburg, Lübeck (60 km), Rom (1300 km), Florenz.
  const hh = (b: 53.55, l: 9.99);
  const hl = (b: 53.87, l: 10.69);
  const rom = (b: 41.90, l: 12.50);
  const florenz = (b: 43.77, l: 11.26);

  Reiseaufnahme a(
    String id,
    DateTime zeit,
    ({double b, double l}) ort, {
    String? stadt,
    String? land,
  }) =>
      (
        id: id,
        zeit: zeit,
        breite: ort.b,
        laenge: ort.l,
        land: land,
        region: null,
        stadt: stadt,
      );

  /// [tage] Kalendertage lang je [proTag] Aufnahmen ab [start].
  List<Reiseaufnahme> reihe(
    String praefix,
    DateTime start,
    int tage,
    ({double b, double l}) ort, {
    int proTag = 3,
    String? stadt,
    String? land,
  }) =>
      [
        for (var t = 0; t < tage; t++)
          for (var i = 0; i < proTag; i++)
            // Minuten und nicht Stunden: Bei dreissig Aufnahmen an einem
            // Tag liefe der Stundenzaehler in den naechsten Tag hinein,
            // und aus dem Tagesausflug wuerde eine Uebernachtung.
            a('$praefix-$t-$i',
                start.add(Duration(days: t, hours: 9, minutes: i)), ort,
                stadt: stadt, land: land),
      ];

  group('Zuhause', () {
    test('zaehlt verschiedene Tage, nicht Aufnahmen', () {
      // Der eigentliche Kniff. Eine einzige Hochzeit bringt sechshundert
      // Bilder an einem Ort, an dem man nie war; ein Zuhause bringt drei
      // Bilder an vierhundert Tagen. Nach Aufnahmen gezaehlt waere die
      // Hochzeit der Wohnort.
      final aufnahmen = [
        ...reihe('daheim', DateTime(2024, 1, 1), 200, hh, proTag: 2),
        ...reihe('hochzeit', DateTime(2024, 7, 6), 1, rom, proTag: 600),
      ];
      final heim = zuhause(aufnahmen)!;
      expect(heim.breite, closeTo(hh.b, 0.2));
      expect(heim.laenge, closeTo(hh.l, 0.2));
    });

    test('mittelt innerhalb der Zelle', () {
      // Die Ecke der Zelle waere als Wohnort bis zu 35 km daneben.
      final heim = zuhause([
        a('1', DateTime(2024, 1, 1), (b: 53.50, l: 9.90)),
        a('2', DateTime(2024, 1, 2), (b: 53.60, l: 9.95)),
      ])!;
      expect(heim.breite, closeTo(53.55, 0.01));
      expect(heim.laenge, closeTo(9.925, 0.01));
    });

    test('ohne Aufnahmen gibt es keinen Wohnort', () {
      expect(zuhause(const []), isNull);
    });
  });

  group('Erkennen', () {
    List<Reisevorschlag> erkenne(List<Reiseaufnahme> aufnahmen,
            {Set<String> verworfen = const {},
            Set<String> bekannt = const {}}) =>
        erkenneReisen(aufnahmen,
            ohneOrt: 'Unbekannt', verworfen: verworfen, bekannteIds: bekannt);

    List<Reiseaufnahme> mitZuhause(List<Reiseaufnahme> weitere) => [
          ...reihe('daheim', DateTime(2024, 1, 1), 120, hh, proTag: 2),
          ...weitere,
        ];

    test('eine Woche weit weg wird vorgeschlagen', () {
      final v = erkenne(mitZuhause(
          reihe('rom', DateTime(2024, 6, 3), 8, rom, stadt: 'Roma', land: 'Italien')));
      expect(v, hasLength(1));
      expect(v.single.anzahl, 24);
      expect(v.single.naechte, 7);
      expect(v.single.name, 'Roma');
      expect(v.single.von.day, 3);
    });

    test('Aufnahmen in der Naehe des Wohnorts ergeben nichts', () {
      // Lübeck liegt 60 km von Hamburg – darunter beginnt der Ausflug,
      // und ein Ausflug ist keine Reise.
      expect(erkenne(mitZuhause(reihe('lue', DateTime(2024, 6, 3), 8, hl))),
          isEmpty);
    });

    test('eine Luecke von mehr als zwei Tagen trennt zwei Reisen', () {
      final v = erkenne(mitZuhause([
        ...reihe('a', DateTime(2024, 6, 1), 3, rom, stadt: 'Roma'),
        ...reihe('b', DateTime(2024, 6, 10), 3, rom, stadt: 'Roma'),
      ]));
      expect(v, hasLength(2));
    });

    test('eine Luecke von genau zwei Tagen trennt nicht', () {
      // Wer unterwegs einen Tag nicht fotografiert – Regen, Fahrtag –,
      // soll deswegen nicht zwei Reisen bekommen.
      final v = erkenne(mitZuhause([
        ...reihe('a', DateTime(2024, 6, 1), 2, rom, stadt: 'Roma'),
        ...reihe('b', DateTime(2024, 6, 4), 2, rom, stadt: 'Roma'),
      ]));
      expect(v, hasLength(1));
      expect(v.single.anzahl, 12);
    });

    test('ein Tagesausflug ist keine Reise', () {
      // Auch weit weg: ohne Uebernachtung keine Reise. Wer ihn dennoch
      // fuehren will, legt ihn von Hand an.
      expect(
          erkenne(mitZuhause(reihe('tag', DateTime(2024, 6, 3), 1, rom,
              proTag: 30, stadt: 'Roma'))),
          isEmpty);
    });

    test('zu wenige Aufnahmen ergeben keinen Vorschlag', () {
      expect(
          erkenne(mitZuhause([
            a('x1', DateTime(2024, 6, 3, 10), rom, stadt: 'Roma'),
            a('x2', DateTime(2024, 6, 4, 10), rom, stadt: 'Roma'),
          ])),
          isEmpty);
    });

    test('ein abgelehnter Vorschlag kommt nicht wieder', () {
      final aufnahmen = mitZuhause(
          reihe('rom', DateTime(2024, 6, 3), 4, rom, stadt: 'Roma'));
      final erst = erkenne(aufnahmen).single;
      expect(erkenne(aufnahmen, verworfen: {erst.schluessel}), isEmpty);
    });

    test('der Schluessel bleibt, wenn hinten Aufnahmen dazukommen', () {
      // Bilder desselben Urlaubs aus einer zweiten Kamera verschieben das
      // Ende. Der Vorschlag ist derselbe und muss abgelehnt bleiben.
      final erst = erkenne(mitZuhause(
          reihe('rom', DateTime(2024, 6, 3), 4, rom, stadt: 'Roma'))).single;
      final spaeter = erkenne(mitZuhause([
        ...reihe('rom', DateTime(2024, 6, 3), 4, rom, stadt: 'Roma'),
        ...reihe('zweitkamera', DateTime(2024, 6, 6), 2, rom, stadt: 'Roma'),
      ])).single;
      expect(spaeter.schluessel, erst.schluessel);
      expect(spaeter.anzahl, greaterThan(erst.anzahl));
    });

    test('bereits zugeordnete Aufnahmen werden uebersprungen', () {
      final aufnahmen = mitZuhause(
          reihe('rom', DateTime(2024, 6, 3), 4, rom, stadt: 'Roma'));
      final ids = erkenne(aufnahmen).single.aufnahmeIds.toSet();
      expect(erkenne(aufnahmen, bekannt: ids), isEmpty);
    });

    test('die juengste Reise steht oben', () {
      final v = erkenne(mitZuhause([
        ...reihe('alt', DateTime(2024, 3, 1), 3, rom, stadt: 'Roma'),
        ...reihe('neu', DateTime(2024, 9, 1), 3, rom, stadt: 'Roma'),
      ]));
      expect(v.map((x) => x.von.month), [9, 3]);
    });
  });

  group('Aufnahmen ohne Koordinate', () {
    // An der echten Bibliothek gemessen: Von einer Reise trugen nur zwei
    // Tage GPS-Daten, und in deren Zeitfenster lagen 28 weitere Bilder
    // ohne Koordinate. Eine Reise, in der Fotos fehlen, ist eine falsche
    // Reise.
    List<Reiseaufnahme> mitZuhause(List<Reiseaufnahme> weitere) => [
          ...reihe('daheim', DateTime(2024, 1, 1), 120, hh, proTag: 2),
          ...weitere,
        ];

    test('werden innerhalb des Fensters mitgenommen', () {
      final v = erkenneReisen(
        mitZuhause(reihe('rom', DateTime(2024, 6, 3), 4, rom, stadt: 'Roma')),
        ohneOrt: 'Unbekannt',
        unverortet: [
          (id: 'ohne1', zeit: DateTime(2024, 6, 4, 12)),
          (id: 'ohne2', zeit: DateTime(2024, 6, 5, 12)),
        ],
      );
      expect(v.single.aufnahmeIds, containsAll(['ohne1', 'ohne2']));
      expect(v.single.anzahl, 14);
    });

    test('davor und danach bleiben sie draussen', () {
      // Dort wäre es geraten: Wer zu Hause fotografiert, ohne dass die
      // Kamera es weiss, käme sonst mit auf die Reise.
      final v = erkenneReisen(
        mitZuhause(reihe('rom', DateTime(2024, 6, 3), 4, rom, stadt: 'Roma')),
        ohneOrt: 'Unbekannt',
        unverortet: [
          (id: 'davor', zeit: DateTime(2024, 6, 1, 12)),
          (id: 'danach', zeit: DateTime(2024, 6, 30, 12)),
        ],
      );
      expect(v.single.aufnahmeIds, isNot(contains('davor')));
      expect(v.single.aufnahmeIds, isNot(contains('danach')));
    });

    test('sie stehen an ihrer chronologischen Stelle', () {
      final v = erkenneReisen(
        mitZuhause(reihe('rom', DateTime(2024, 6, 3), 4, rom, stadt: 'Roma')),
        ohneOrt: 'Unbekannt',
        unverortet: [
          (id: 'mittendrin', zeit: DateTime(2024, 6, 3, 9, 0, 30))
        ],
      );
      // Die verorteten Aufnahmen liegen um 9:00, 9:01 und 9:02 – diese
      // gehoert zwischen die erste und die zweite.
      expect(v.single.aufnahmeIds.indexOf('mittendrin'), 1);
    });

    test('sie allein ergeben keine Reise', () {
      // Ohne eine einzige Koordinate weiss niemand, ob man weg war.
      expect(
          erkenneReisen(
            reihe('daheim', DateTime(2024, 1, 1), 120, hh, proTag: 2),
            ohneOrt: 'Unbekannt',
            unverortet: [
              for (var i = 0; i < 50; i++)
                (id: 'o$i', zeit: DateTime(2024, 6, 3).add(Duration(hours: i)))
            ],
          ),
          isEmpty);
    });

    test('bereits zugeordnete bleiben aussen vor', () {
      final v = erkenneReisen(
        mitZuhause(reihe('rom', DateTime(2024, 6, 3), 4, rom, stadt: 'Roma')),
        ohneOrt: 'Unbekannt',
        unverortet: [(id: 'schon', zeit: DateTime(2024, 6, 4, 12))],
        bekannteIds: {'schon'},
      );
      expect(v.single.aufnahmeIds, isNot(contains('schon')));
    });
  });

  group('Der vorgeschlagene Name', () {
    test('ein Ort bleibt ein Ort', () {
      expect(reisename(['Roma'], ['Italien'], 'Unbekannt'), 'Roma');
    });

    test('zwei Orte werden verbunden, mehr nicht', () {
      // „Rom – Florenz – Siena – Pisa – …" ist kein Name mehr, sondern
      // eine Aufzaehlung.
      expect(reisename(['Roma', 'Firenze', 'Siena', 'Pisa'], ['Italien'], '-'),
          'Roma – Firenze');
    });

    test('ueber Laendergrenzen zaehlen die Laender', () {
      expect(
          reisename(['Innsbruck', 'Bozen'], ['Österreich', 'Italien'], '-'),
          'Österreich – Italien');
    });

    test('ohne jeden Ortsnamen bleibt der Ersatz', () {
      expect(reisename(const [], const [], 'Ohne Ort'), 'Ohne Ort');
    });

    test('der Name kommt aus den haeufigsten Orten', () {
      final v = erkenneReisen(
        [
          ...[
            for (var t = 0; t < 120; t++)
              (
                id: 'd$t',
                zeit: DateTime(2024, 1, 1).add(Duration(days: t)),
                breite: hh.b,
                laenge: hh.l,
                land: 'Deutschland',
                region: null,
                stadt: 'Hamburg',
              ),
          ],
          // Zwei Nächte in Florenz, fünf in Rom – Rom gehoert nach vorn.
          for (var i = 0; i < 6; i++)
            (
              id: 'f$i',
              zeit: DateTime(2024, 6, 3, 9 + i),
              breite: florenz.b,
              laenge: florenz.l,
              land: 'Italien',
              region: null,
              stadt: 'Firenze',
            ),
          for (var i = 0; i < 15; i++)
            (
              id: 'r$i',
              zeit: DateTime(2024, 6, 4 + i ~/ 5, 9 + i % 5),
              breite: rom.b,
              laenge: rom.l,
              land: 'Italien',
              region: null,
              stadt: 'Roma',
            ),
        ],
        ohneOrt: 'Unbekannt',
      );
      expect(v.single.orte, ['Roma', 'Firenze']);
      expect(v.single.name, 'Roma – Firenze');
      expect(v.single.laender, ['Italien']);
    });
  });
}
