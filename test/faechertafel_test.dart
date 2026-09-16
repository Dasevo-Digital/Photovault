import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/faechertafel.dart';
import 'package:photo_vault/services/stammbaum.dart';

/// Der Fächer und die Nachfahrengliederung.
///
/// Winkel lassen sich am fertigen Bild nicht beurteilen: Ob ein Ring
/// lückenlos gefüllt ist oder zwei Plätze sich um ein Hundertstel
/// überlappen, sieht niemand. Hier wird es nachgerechnet.
void main() {
  group('Ein leerer Ring bleibt als Einladung stehen', () {
    // Der gemeldete Eindruck: „hier werden nur die Eltern aufgeführt".
    // Die Daten waren richtig – aufwärts standen nur die Eltern im
    // Bestand –, aber der Fächer endete bündig mit ihnen und zeigte
    // nirgends, dass darüber noch Platz ist.
    Verwandtschaftsnetz nurEltern() => Verwandtschaftsnetz([
          kante('ich', 'vater', Verwandtschaft.elternteil),
          kante('ich', 'mutter', Verwandtschaft.elternteil),
        ]);

    int rang(String id) => const {'vater': 0, 'mutter': 1}[id] ?? 99;

    test('über belegten Eltern stehen vier gestrichelte Großelternplätze', () {
      final p = faechertafel(nurEltern(), 'ich', rang);
      final ring2 = p.where((x) => x.ring == 2).toList();
      expect(ring2, hasLength(4));
      expect(ring2.every((x) => x.istLeer), isTrue);
    });

    test('aber nur einer – Ring 3 bleibt weg', () {
      final p = faechertafel(nurEltern(), 'ich', rang);
      expect(p.where((x) => x.ring >= 3), isEmpty,
          reason: 'zwei leere Ringe sähen aus wie ein Zeichenfehler');
    });

    test('ohne jeden Vorfahren bleibt es bei den zwei Elternplätzen', () {
      final p = faechertafel(Verwandtschaftsnetz(const []), 'ich', rang);
      expect(p.where((x) => x.ring == 1), hasLength(2));
      expect(p.where((x) => x.ring >= 2), isEmpty);
    });

    test('der leere Ring wächst mit: über Großeltern stehen die Urgroßeltern',
        () {
      final netz = Verwandtschaftsnetz([
        kante('ich', 'vater', Verwandtschaft.elternteil),
        kante('vater', 'opa', Verwandtschaft.elternteil),
      ]);
      final p = faechertafel(netz, 'ich', rang);
      expect(p.where((x) => x.ring == 3), isNotEmpty);
      expect(p.where((x) => x.ring == 3).every((x) => x.istLeer), isTrue);
      expect(p.where((x) => x.ring >= 4), isEmpty);
    });

    test('die Höchstzahl der Ringe wird nicht überschritten', () {
      // Vier Generationen voll – ein fünfter Ring darf nicht entstehen.
      final kanten = <Kante>[];
      var vorher = 'ich';
      for (var i = 0; i < 4; i++) {
        kanten.add(kante(vorher, 'ahn$i', Verwandtschaft.elternteil));
        vorher = 'ahn$i';
      }
      final p = faechertafel(Verwandtschaftsnetz(kanten), 'ich', rang);
      expect(p.fold(0, (m, x) => x.ring > m ? x.ring : m),
          lessThanOrEqualTo(maxFachRinge));
    });
  });

  /// vier Generationen über „ich", ein Ast bricht früher ab:
  ///
  ///   ich
  ///    ├ vater  ── opaV ── uropaV
  ///    │         └ omaV
  ///    └ mutter ── opaM
  Verwandtschaftsnetz sippe() => Verwandtschaftsnetz([
        kante('ich', 'vater', Verwandtschaft.elternteil),
        kante('ich', 'mutter', Verwandtschaft.elternteil),
        kante('vater', 'opaV', Verwandtschaft.elternteil),
        kante('vater', 'omaV', Verwandtschaft.elternteil),
        kante('mutter', 'opaM', Verwandtschaft.elternteil),
        kante('opaV', 'uropaV', Verwandtschaft.elternteil),
        kante('kind', 'ich', Verwandtschaft.elternteil),
        kante('enkel', 'kind', Verwandtschaft.elternteil),
        kante('zweitesKind', 'ich', Verwandtschaft.elternteil),
      ]);

  /// Feste Ordnung für die Tests: alphabetisch.
  final reihenfolge = [
    'enkel', 'ich', 'kind', 'mutter', 'omaV', 'opaM', 'opaV', 'uropaV',
    'vater', 'zweitesKind',
  ];
  int ordnung(String id) => reihenfolge.indexOf(id);

  group('elternFuerTafel', () {
    test('liefert immer zwei Plätze, auch bei nur einem Elternteil', () {
      final e = elternFuerTafel(sippe(), 'mutter', ordnung);
      expect(e, hasLength(2));
      expect(e[0], 'opaM');
      expect(e[1], isNull);
    });

    test('hält eine feste Reihenfolge ein', () {
      // Ohne feste Ordnung sprängen die Plätze bei jedem Aufbau, weil die
      // Eltern im Bestand eine Menge sind.
      expect(elternFuerTafel(sippe(), 'vater', ordnung), ['omaV', 'opaV']);
    });

    test('kappt einen dritten Elternteil', () {
      // Eine Ahnentafel ist auf Verdopplung gebaut und kann nicht mehr als
      // zwei abbilden – die Reihen-Ansicht zeigt weiterhin alle.
      final netz = Verwandtschaftsnetz([
        kante('x', 'a', Verwandtschaft.elternteil),
        kante('x', 'b', Verwandtschaft.elternteil),
        kante('x', 'c', Verwandtschaft.elternteil),
      ]);
      final e = elternFuerTafel(netz, 'x', (id) => id.codeUnitAt(0));
      expect(e, ['a', 'b']);
    });
  });

  group('faechertafel', () {
    test('nummeriert nach Ahnentafel: Eltern von n sind 2n und 2n+1', () {
      final plaetze = faechertafel(sippe(), 'ich', ordnung);
      final nachNummer = {for (final p in plaetze) p.nummer: p.personId};
      expect(nachNummer[1], 'ich');
      // Die Eltern von 1 sind 2 und 3 …
      expect({nachNummer[2], nachNummer[3]}, {'mutter', 'vater'});
      // … und die Eltern des Vaters liegen unter seiner Nummer.
      final vaterNummer = nachNummer[2] == 'vater' ? 2 : 3;
      expect({nachNummer[vaterNummer * 2], nachNummer[vaterNummer * 2 + 1]},
          {'omaV', 'opaV'});
    });

    test('ein Ring ist lückenlos und überlappungsfrei', () {
      final plaetze = faechertafel(sippe(), 'ich', ordnung);
      for (var ring = 0; ring <= 2; ring++) {
        final imRing = plaetze.where((p) => p.ring == ring).toList()
          ..sort((a, b) => a.vonWinkel.compareTo(b.vonWinkel));
        expect(imRing.first.vonWinkel, closeTo(fachAnfang, 1e-9),
            reason: 'Ring $ring beginnt am Anfang');
        for (var i = 1; i < imRing.length; i++) {
          expect(imRing[i].vonWinkel,
              closeTo(imRing[i - 1].vonWinkel + imRing[i - 1].oeffnung, 1e-9),
              reason: 'Ring $ring, Platz $i schließt nahtlos an');
        }
        final summe = imRing.fold(0.0, (s, p) => s + p.oeffnung);
        expect(summe, closeTo(fachOeffnung, 1e-9),
            reason: 'Ring $ring füllt den Halbkreis');
      }
    });

    test('jeder Ring hat doppelt so viele Plätze wie der darunter – '
        'solange dort jemand steht', () {
      final plaetze = faechertafel(sippe(), 'ich', ordnung);
      expect(plaetze.where((p) => p.ring == 0), hasLength(1));
      expect(plaetze.where((p) => p.ring == 1), hasLength(2));
      expect(plaetze.where((p) => p.ring == 2), hasLength(4));
      // Ring 3: nur unter opaV und omaV bzw. opaM steht überhaupt jemand,
      // also drei belegte Elternplätze -> sechs Plätze.
      expect(plaetze.where((p) => p.ring == 3), hasLength(6));
    });

    test('lässt genau einen leeren Aussenring stehen', () {
      // Geänderte Entscheidung: Vorher endete der Fächer bündig mit der
      // letzten belegten Generation – hier also bei Ring 2. Damit sah ein
      // Fächer aus Mitte und Eltern aus, als könne er nicht mehr, statt
      // als warte er auf mehr; genau das wurde gemeldet. Jetzt bleibt
      // einer stehen, aber auch nur einer.
      final ohneUropa = Verwandtschaftsnetz([
        kante('ich', 'vater', Verwandtschaft.elternteil),
        kante('vater', 'opaV', Verwandtschaft.elternteil),
      ]);
      final plaetze = faechertafel(ohneUropa, 'ich', ordnung);
      expect(plaetze.map((p) => p.ring).reduce(math.max), 3,
          reason: 'ein leerer Ring als Einladung');
      expect(plaetze.where((p) => p.ring == 3).every((p) => p.istLeer), isTrue);
      // Ring 2 bleibt belegt: Dort steht opaV.
      expect(plaetze.where((p) => p.ring == 2 && !p.istLeer), hasLength(1));
    });

    test('verfolgt einen leeren Ast nicht weiter', () {
      // Sonst wären es bei vier Ringen immer 31 Plätze, auch für jemanden
      // ohne einen einzigen eingetragenen Vorfahren.
      //
      // Der erste Ring entsteht trotzdem: Zwei leere Elternplätze sind
      // die Aussage „hier fehlt etwas" und gehören ins Bild. Erst
      // dahinter bricht der Ast ab.
      final allein = faechertafel(Verwandtschaftsnetz([]), 'allein', ordnung);
      expect(allein, hasLength(3));
      expect(allein.where((p) => p.ring == 1), hasLength(2));
      expect(allein.where((p) => p.ring >= 2), isEmpty);
    });

    test('zeigt Lücken, statt sie wegzulassen', () {
      final plaetze = faechertafel(sippe(), 'ich', ordnung);
      // Die Mutter hat nur einen Elternteil – der zweite Platz bleibt da,
      // aber leer.
      expect(plaetze.where((p) => p.ring == 2 && p.istLeer), hasLength(1));
    });
  });

  group('platzBei', () {
    test('trifft den Platz unter dem Finger', () {
      final plaetze = faechertafel(sippe(), 'ich', ordnung);
      // Mitte des ersten Rings, linke Hälfte: der erste Platz.
      final links = platzBei(plaetze, fachAnfang + fachOeffnung * 0.25, 1.5);
      expect(links, isNotNull);
      expect(links!.ring, 1);
      expect(links.nummer, 2);
      // Rechte Hälfte: der zweite.
      expect(platzBei(plaetze, fachAnfang + fachOeffnung * 0.75, 1.5)!.nummer, 3);
    });

    test('trifft die Mitte', () {
      final plaetze = faechertafel(sippe(), 'ich', ordnung);
      expect(platzBei(plaetze, fachAnfang + 0.1, 0.5)!.personId, 'ich');
    });

    test('unterhalb der Mittellinie liegt nichts', () {
      final plaetze = faechertafel(sippe(), 'ich', ordnung);
      // Ein Winkel in der unteren Hälfte (nach Flutters Zählung 0 … π).
      expect(platzBei(plaetze, math.pi / 2, 1.5), isNull);
    });

    test('jenseits des äußersten Rings liegt nichts', () {
      final plaetze = faechertafel(sippe(), 'ich', ordnung);
      expect(platzBei(plaetze, fachAnfang + 0.1, 9.5), isNull);
    });
  });

  group('nachfahren', () {
    test('rückt jede Generation eine Stufe ein', () {
      final zeilen = nachfahren(sippe(), 'ich', ordnung);
      expect(zeilen.map((z) => z.personId),
          ['ich', 'kind', 'enkel', 'zweitesKind']);
      expect(zeilen.map((z) => z.stufe), [0, 1, 2, 1]);
    });

    test('meldet, wo es weitergeht', () {
      final zeilen = nachfahren(sippe(), 'ich', ordnung);
      expect(zeilen.firstWhere((z) => z.personId == 'kind').hatKinder, isTrue);
      expect(zeilen.firstWhere((z) => z.personId == 'enkel').hatKinder, isFalse);
    });

    test('bleibt bei einem Kreis im Bestand stehen', () {
      final netz = Verwandtschaftsnetz([
        kante('a', 'b', Verwandtschaft.elternteil),
        kante('b', 'a', Verwandtschaft.elternteil),
      ]);
      final zeilen = nachfahren(netz, 'a', (id) => id.codeUnitAt(0));
      expect(zeilen.map((z) => z.personId), ['a', 'b']);
    });

    test('achtet auf die Tiefengrenze', () {
      final netz = Verwandtschaftsnetz([
        for (var i = 1; i < 12; i++)
          kante('p$i', 'p${i - 1}', Verwandtschaft.elternteil),
      ]);
      final zeilen = nachfahren(netz, 'p0', (id) => 0, tiefe: 3);
      expect(zeilen.map((z) => z.stufe).reduce(math.max), 3);
    });
  });
}
