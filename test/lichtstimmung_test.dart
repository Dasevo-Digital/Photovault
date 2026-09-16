// Die Tageszeit über der Geländeansicht.
//
// Zwei Fragen: Bleibt „Mittag" genau das, was vorher fest im Code stand
// (sonst hätte sich die Vorgabe nebenbei verändert)? Und halten die
// Zusagen, auf denen die Lesbarkeit beruht – Sonne im Nordwesten,
// Untergrenze eingehalten?
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/gelaendesicht.dart';
import 'package:photo_vault/services/lichtstimmung.dart';

/// Die Schattierung, wie sie vor den Tageszeiten gerechnet wurde –
/// abgeschrieben aus dem Stand von 3.3.1.
double _wieFrueher(Raumpunkt n) {
  const lx = -0.5, ly = 0.5, lz = 0.707;
  final laenge = math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z);
  if (laenge == 0) return 1;
  final p = (n.x * lx + n.y * ly + n.z * lz) / laenge;
  return (0.72 + 0.28 * p).clamp(0.5, 1.0);
}

/// Ein paar Flächen, wie sie in einem Gelände vorkommen: eben, nach
/// Nordwesten geneigt, nach Südosten, senkrecht, überhängend.
const _flaechen = <Raumpunkt>[
  (x: 0, y: 0, z: 1),
  (x: -1, y: 1, z: 1),
  (x: 1, y: -1, z: 1),
  (x: -1, y: 0, z: 0),
  (x: 1, y: -1, z: -1),
  (x: 0.3, y: 0.8, z: 2.0),
];

void main() {
  group('Mittag ist genau das Bisherige', () {
    test('für jede Fläche dieselbe Zahl wie vor den Tageszeiten', () {
      for (final f in _flaechen) {
        expect(schattierung(f, stimmungMittag), closeTo(_wieFrueher(f), 1e-12),
            reason: 'bei $f');
      }
    });

    test('und ohne Angabe gilt genau diese Stimmung', () {
      for (final f in _flaechen) {
        expect(schattierung(f), schattierung(f, stimmungMittag));
      }
      expect(lichtstimmungVorgabe, Tageszeit.mittag);
      expect(stimmungFuer(lichtstimmungVorgabe), same(stimmungMittag));
    });
  });

  group('Was für jede Tageszeit gelten muss', () {
    test('die Sonne steht im Nordwesten und über dem Horizont', () {
      // Der Grund steht bei [schattierung]: Von rechts unten beleuchtet
      // liest das Auge jedes Tal als Berg. Wer eine Stimmung ergänzt und
      // die Sonne physikalisch richtig nach Osten stellt, dreht das
      // ganze Relief um – und würde es am Zahlenwert nicht merken.
      for (final s in lichtstimmungen) {
        expect(s.sonne.x, lessThan(0), reason: '${s.zeit}: nicht westlich');
        expect(s.sonne.y, greaterThan(0), reason: '${s.zeit}: nicht nördlich');
        expect(s.sonne.z, greaterThan(0), reason: '${s.zeit}: unter Grund');
      }
    });

    test('die Sonnenrichtung hat Länge eins', () {
      for (final s in lichtstimmungen) {
        final l = math.sqrt(s.sonne.x * s.sonne.x +
            s.sonne.y * s.sonne.y +
            s.sonne.z * s.sonne.z);
        expect(l, closeTo(1, 0.005), reason: '${s.zeit}');
      }
    });

    test('Grund- und Richtungslicht ergeben zusammen eins', () {
      for (final s in lichtstimmungen) {
        expect(s.grundlicht + s.richtungslicht, closeTo(1, 1e-9),
            reason: '${s.zeit}');
      }
    });

    test('keine Fläche wird dunkler als die Untergrenze', () {
      // Eine schwarze Nordflanke sieht aus wie ein Loch im Gitter.
      for (final s in lichtstimmungen) {
        for (final f in _flaechen) {
          final w = schattierung(f, s);
          expect(w, greaterThanOrEqualTo(s.untergrenze - 1e-9),
              reason: '${s.zeit} bei $f');
          expect(w, lessThanOrEqualTo(1.0), reason: '${s.zeit} bei $f');
        }
      }
      // Und auch nicht bei einer Fläche, die direkt von der Sonne
      // wegzeigt – die kommt in echtem Gelände durchaus vor.
      for (final s in lichtstimmungen) {
        final weg = (x: -s.sonne.x, y: -s.sonne.y, z: -s.sonne.z);
        expect(schattierung(weg, s), closeTo(s.untergrenze, 1e-9),
            reason: '${s.zeit}');
      }
    });

    test('die Untergrenze liegt nicht unter der Grundhelligkeit', () {
      // Sonst schnitte sie nie – und die Zahl wäre eine Behauptung.
      for (final s in lichtstimmungen) {
        expect(s.untergrenze,
            lessThan(s.grundlicht),
            reason: '${s.zeit}: Untergrenze greift nie');
      }
    });
  });

  group('Was die Tageszeiten unterscheidet', () {
    /// Der Abstand zwischen der hellsten und der dunkelsten Fläche –
    /// das ist die Reliefwirkung in einer Zahl.
    double spreizung(Lichtstimmung s) {
      final werte = [for (final f in _flaechen) schattierung(f, s)];
      return werte.reduce(math.max) - werte.reduce(math.min);
    }

    test('Morgen und Abend zeigen mehr Relief als der Mittag', () {
      // Flachere Sonne heisst längere Schatten. Das ist der Grund, warum
      // es die Tageszeiten überhaupt gibt.
      expect(spreizung(stimmungMorgen), greaterThan(spreizung(stimmungMittag)));
      expect(spreizung(stimmungAbend), greaterThan(spreizung(stimmungMorgen)));
    });

    test('die blaue Stunde zeigt weniger, nicht mehr', () {
      // Ohne direkte Sonne gibt es keine harten Schatten. Wer hier das
      // Relief hochzöge, malte eine Mittagsszene in Blau.
      expect(spreizung(stimmungBlaueStunde),
          lessThan(spreizung(stimmungAbend)));
    });

    test('jede Tageszeit hat ihren eigenen Himmel', () {
      final oben = {for (final s in lichtstimmungen) s.himmelOben};
      final unten = {for (final s in lichtstimmungen) s.himmelUnten};
      final dunst = {for (final s in lichtstimmungen) s.dunst};
      expect(oben, hasLength(lichtstimmungen.length));
      expect(unten, hasLength(lichtstimmungen.length));
      expect(dunst, hasLength(lichtstimmungen.length));
    });

    test('es gibt zu jeder Tageszeit genau eine Stimmung', () {
      expect(lichtstimmungen.map((s) => s.zeit).toSet(),
          Tageszeit.values.toSet());
    });
  });

  group('Eine gemerkte Nummer', () {
    test('findet ihre Tageszeit wieder', () {
      for (final z in Tageszeit.values) {
        expect(tageszeit(z.index), z);
      }
    });

    test('ausserhalb der Reihe fällt sie auf die Vorgabe zurück', () {
      // Eine Nummer aus einer Fassung, die es nicht mehr gibt, darf den
      // Bildschirm nicht verhindern – dieselbe Regel wie beim
      // Kartenstil.
      for (final falsch in [-1, 4, 99, 1 << 30]) {
        expect(tageszeit(falsch), lichtstimmungVorgabe, reason: 'bei $falsch');
      }
    });
  });
}
