// Bündige Reihen – die reine Rechnung hinter der neuen Zeitleistenform.
//
// Geprüft wird, was am Bildschirm auffiele: ein Rand, der nicht bündig
// ist; eine Reihenfolge, die springt; ein letztes Foto, das über den
// halben Bildschirm gezogen wird.
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/bildreihen.dart';

/// Die Breite, die eine Reihe tatsächlich belegt – samt Abständen.
double _belegteBreite(Bildreihe r, double abstand) {
  var summe = 0.0;
  for (final p in r.plaetze) {
    summe += p.breite;
  }
  return summe + abstand * (r.plaetze.length - 1);
}

void main() {
  const abstand = 4.0;
  const breite = 1200.0;
  const zielhoehe = 160.0;

  // Ein gemischter Satz, wie ihn die echte Bibliothek liefert: überwiegend
  // quer (3:2), dazwischen Hochformate (2:3) und ein Quadrat.
  List<double> gemischt(int n) => [
        for (var i = 0; i < n; i++)
          switch (i % 5) {
            0 || 1 || 2 => 3 / 2,
            3 => 2 / 3,
            _ => 1.0,
          }
      ];

  group('Bündigkeit', () {
    test('jede volle Reihe füllt die Breite auf den Punkt', () {
      final reihen = bildreihen(
        seitenverhaeltnisse: gemischt(60),
        breite: breite,
        zielhoehe: zielhoehe,
        abstand: abstand,
      );
      expect(reihen.length, greaterThan(1));
      // Die letzte Reihe ist absichtlich nicht gestreckt.
      for (final r in reihen.take(reihen.length - 1)) {
        expect(_belegteBreite(r, abstand), closeTo(breite, 0.0001),
            reason: 'Reihe ab Index ${r.ersterIndex} ist nicht bündig');
      }
    });

    test('auch bei nur Hochformaten bleibt es bündig', () {
      final reihen = bildreihen(
        seitenverhaeltnisse: List.filled(40, 2 / 3),
        breite: breite,
        zielhoehe: zielhoehe,
        abstand: abstand,
      );
      for (final r in reihen.take(reihen.length - 1)) {
        expect(_belegteBreite(r, abstand), closeTo(breite, 0.0001));
      }
    });
  });

  group('Reihenfolge', () {
    test('läuft lückenlos und aufsteigend durch', () {
      // Das ist der Grund, warum es Reihen und keine Spalten sind: In einer
      // Zeitleiste muss Foto 2 neben Foto 1 stehen, nicht darunter.
      final reihen = bildreihen(
        seitenverhaeltnisse: gemischt(53),
        breite: breite,
        zielhoehe: zielhoehe,
        abstand: abstand,
      );
      final gesehen = <int>[];
      for (final r in reihen) {
        for (final p in r.plaetze) {
          gesehen.add(p.index);
        }
      }
      expect(gesehen, List.generate(53, (i) => i));
    });
  });

  group('Reihenhöhe', () {
    test('keine volle Reihe wird höher als die Zielhöhe', () {
      final reihen = bildreihen(
        seitenverhaeltnisse: gemischt(60),
        breite: breite,
        zielhoehe: zielhoehe,
        abstand: abstand,
      );
      for (final r in reihen.take(reihen.length - 1)) {
        expect(r.hoehe, lessThanOrEqualTo(zielhoehe + 0.0001));
      }
    });

    test('die letzte Reihe wird nicht gestreckt', () {
      // Zwei Querformate bei 1200 Punkten Breite füllten gestreckt die
      // ganze Zeile - 400 Punkte hoch für zwei übrig gebliebene Fotos.
      final reihen = bildreihen(
        seitenverhaeltnisse: [3 / 2, 3 / 2],
        breite: breite,
        zielhoehe: zielhoehe,
        abstand: abstand,
      );
      expect(reihen, hasLength(1));
      expect(reihen.single.hoehe, zielhoehe);
      expect(_belegteBreite(reihen.single, abstand), lessThan(breite));
    });

    test('ein sehr breites Panorama bekommt seine eigene Reihe', () {
      final reihen = bildreihen(
        seitenverhaeltnisse: [12.0, 3 / 2, 3 / 2],
        breite: breite,
        zielhoehe: zielhoehe,
        abstand: abstand,
      );
      expect(reihen.first.plaetze, hasLength(1));
      expect(reihen.first.plaetze.single.index, 0);
      // Und es wird flacher als die Zielhöhe, statt überzulaufen.
      expect(reihen.first.hoehe, lessThan(zielhoehe));
      expect(_belegteBreite(reihen.first, abstand), closeTo(breite, 0.0001));
    });
  });

  group('Was schiefgehen kann', () {
    test('leere Liste ergibt keine Reihe statt einer Ausnahme', () {
      expect(
          bildreihen(
              seitenverhaeltnisse: const [],
              breite: breite,
              zielhoehe: zielhoehe,
              abstand: abstand),
          isEmpty);
    });

    test('Breite null ergibt keine Reihe', () {
      // Ein Widget wird beim ersten Aufbau durchaus mit 0 vermessen.
      expect(
          bildreihen(
              seitenverhaeltnisse: gemischt(10),
              breite: 0,
              zielhoehe: zielhoehe,
              abstand: abstand),
          isEmpty);
    });

    test('ein kaputtes Seitenverhältnis fällt auf 3:2 zurück', () {
      // Sonst wäre eine Reihe unendlich hoch oder null breit - ein
      // Bildschirm, der wegen eines einzigen Eintrags nichts mehr zeigt.
      for (final kaputt in [0.0, -1.0, double.nan, double.infinity]) {
        final reihen = bildreihen(
          seitenverhaeltnisse: [kaputt],
          breite: breite,
          zielhoehe: zielhoehe,
          abstand: abstand,
        );
        expect(reihen, hasLength(1), reason: 'bei $kaputt');
        expect(reihen.single.hoehe.isFinite, isTrue, reason: 'bei $kaputt');
        expect(reihen.single.plaetze.single.breite,
            closeTo(zielhoehe * seitenverhaeltnisVorgabe, 0.0001),
            reason: 'bei $kaputt');
      }
    });
  });

  group('Gesamthöhe', () {
    test('ist die Summe der Reihen samt Abständen', () {
      final reihen = bildreihen(
        seitenverhaeltnisse: gemischt(30),
        breite: breite,
        zielhoehe: zielhoehe,
        abstand: abstand,
      );
      var erwartet = abstand * (reihen.length - 1);
      for (final r in reihen) {
        erwartet += r.hoehe;
      }
      expect(reihenGesamthoehe(reihen, abstand), closeTo(erwartet, 0.0001));
    });

    test('keine Reihe ergibt keine Höhe', () {
      expect(reihenGesamthoehe(const [], abstand), 0);
    });
  });
}
