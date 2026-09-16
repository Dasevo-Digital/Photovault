// Höhenlinien, aus dem Höhengitter gerechnet statt geladen.
//
// Prüfbar ist das an Gelände, dessen Antwort man vorher weiss: eine
// schiefe Ebene, ein Kegel, eine ebene Fläche. Ein echter Ausschnitt
// sagt hier nichts – ein falscher Linienverlauf sieht darauf aus wie ein
// richtiger.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/gelaendekacheln.dart';
import 'package:photo_vault/services/hoehenlinien.dart';

const _sued = 51.83;
const _nord = 51.84;
const _west = 10.63;
const _ost = 10.65;

Hoehengitter _gitter(double Function(double x, double y) hoehe, {int n = 64}) {
  final h = Float32List(n * n);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      h[y * n + x] = hoehe(x / (n - 1), y / (n - 1));
    }
  }
  return Hoehengitter(
      spalten: n, zeilen: n, hoehen: h,
      nord: _nord, sued: _sued, west: _west, ost: _ost);
}

Hoehenlinien _linien(Hoehengitter g,
        {double abstand = 10, int maschen = 48}) =>
    hoehenlinien(g,
        west: _west, ost: _ost, sued: _sued, nord: _nord,
        abstand: abstand, maschen: maschen);

void main() {
  group('Der Abstand passt sich dem Gelände an', () {
    test('im Mittelgebirge zehn Meter, im Hochgebirge nicht', () {
      // Der Harz: 195 bis 1139 m auf dem geladenen Ausschnitt.
      expect(hoehenlinienAbstand(944), 50);
      // Ein einzelnes Tal darin.
      expect(hoehenlinienAbstand(180), 10);
      // Grindelwald: 547 bis 4035 m. Bei zehn Metern lägen dort 350
      // Linien übereinander - ein schwarzer Filz.
      expect(hoehenlinienAbstand(3488), 200);
    });

    test('die Stufen sind die einer Wanderkarte', () {
      // „Alle 37 Meter" liest niemand.
      final erlaubt = {5.0, 10.0, 20.0, 25.0, 50.0, 100.0, 200.0, 500.0, 1000.0};
      for (var spanne = 1.0; spanne < 6000; spanne *= 1.3) {
        expect(erlaubt, contains(hoehenlinienAbstand(spanne)));
      }
    });
  });

  group('Was die Linien beschreiben', () {
    test('eine ebene Fläche hat keine Höhenlinien', () {
      final l = _linien(_gitter((x, y) => 500));
      expect(l.linien, isEmpty);
      expect(l.zaehllinien, isEmpty);
    });

    test('eine schiefe Ebene ergibt gerade, parallele Linien', () {
      // Von 400 im Westen auf 500 im Osten: bei zehn Metern Abstand neun
      // Linien, alle senkrecht.
      final l = _linien(_gitter((x, y) => 400 + 100 * x));
      final alle = [...l.linien, ...l.zaehllinien];
      expect(alle, isNotEmpty);
      for (final s in alle) {
        expect((s.x1 - s.x2).abs(), lessThan(0.02),
            reason: 'eine Linie über einer schiefen Ebene muss senkrecht '
                'stehen, diese läuft von ${s.x1} nach ${s.x2}');
      }
      // Neun Höhen (410..490) mal 48 Zellen je Spalte.
      final hoehenZahl = alle.map((s) => (s.x1 * 100).round()).toSet().length;
      expect(hoehenZahl, greaterThanOrEqualTo(8));
      expect(hoehenZahl, lessThanOrEqualTo(11));
    });

    test('die Linien liegen dort, wo die Höhe steht', () {
      // Bei 400 + 100·x liegt die 450er Linie genau in der Mitte.
      final l = _linien(_gitter((x, y) => 400 + 100 * x), abstand: 50);
      // 450 ist keine Zähllinie (450/50 = 9), 500 wäre eine.
      final vierhundertfuenfzig =
          [...l.linien, ...l.zaehllinien].where((s) => s.x1 > 0.4 && s.x1 < 0.6);
      expect(vierhundertfuenfzig, isNotEmpty);
      for (final s in vierhundertfuenfzig) {
        expect(s.x1, closeTo(0.5, 0.03));
      }
    });

    test('jede fünfte Linie ist eine Zähllinie', () {
      // Ohne sie ist eine Schar von Linien nicht zu zählen.
      final l = _linien(_gitter((x, y) => 400 + 100 * x));
      expect(l.zaehllinien, isNotEmpty);
      expect(l.linien, isNotEmpty);
      // 410..490 bei zehn Metern: 450 ist die einzige durch fünf
      // teilbare, also ein Achtel bis ein Viertel der Strecken.
      final anteil = l.zaehllinien.length /
          (l.linien.length + l.zaehllinien.length);
      expect(anteil, lessThan(0.35));
      expect(anteil, greaterThan(0.05));
    });

    test('ein Kegel ergibt geschlossene Ringe um seine Spitze', () {
      // Jede Linie muss einen ähnlichen Abstand zur Mitte haben wie ihre
      // Nachbarn auf derselben Höhe – das ist die prüfbare Eigenschaft
      // eines Rings.
      final l = _linien(
          _gitter((x, y) {
            final dx = x - 0.5, dy = y - 0.5;
            return 500 - 300 * math.sqrt(dx * dx + dy * dy);
          }),
          abstand: 20);
      final alle = [...l.linien, ...l.zaehllinien];
      expect(alle, isNotEmpty);
      // Zu jeder Höhe gehört genau ein Radius. Geprüft wird die
      // Streuung der Abstände zur Mitte je Höhenstufe.
      final radien = <int, List<double>>{};
      for (final s in alle) {
        final dx = s.x1 - 0.5, dy = s.y1 - 0.5;
        final r = math.sqrt(dx * dx + dy * dy);
        // Die Höhe an dieser Stelle - gerundet auf die Stufe.
        final h = ((500 - 300 * r) / 20).round();
        (radien[h] ??= []).add(r);
      }
      for (final e in radien.entries) {
        if (e.value.length < 8) continue;
        final mittel = e.value.reduce((a, b) => a + b) / e.value.length;
        for (final r in e.value) {
          expect((r - mittel).abs(), lessThan(0.06),
              reason: 'Stufe ${e.key}: Radius $r weicht von $mittel ab');
        }
      }
    });

    test('ein Loch im Gitter erzeugt keine erfundene Linie', () {
      // Eine Zelle mit einer unbekannten Ecke wird übersprungen. Ohne
      // das liefe eine Linie quer durch eine fehlende Kachel.
      const n = 32;
      final h = Float32List(n * n);
      for (var y = 0; y < n; y++) {
        for (var x = 0; x < n; x++) {
          // Die rechte Hälfte ist unbekannt.
          h[y * n + x] = x < n ~/ 2 ? 400 + 100 * x / n : double.nan;
        }
      }
      final l = _linien(Hoehengitter(
          spalten: n, zeilen: n, hoehen: h,
          nord: _nord, sued: _sued, west: _west, ost: _ost));
      final alle = [...l.linien, ...l.zaehllinien];
      expect(alle, isNotEmpty, reason: 'die linke Hälfte muss Linien haben');
      for (final s in alle) {
        expect(s.x1, lessThan(0.55),
            reason: 'eine Linie in der unbekannten Hälfte wäre erfunden');
      }
    });
  });

  test('die Koordinaten bleiben im Block', () {
    // Sie werden mit der Kantenlänge der Textur multipliziert; alles
    // ausserhalb von 0..1 landete neben dem Bild.
    final l = _linien(_gitter((x, y) => 400 + 100 * x + 60 * y));
    for (final s in [...l.linien, ...l.zaehllinien]) {
      for (final w in [s.x1, s.y1, s.x2, s.y2]) {
        expect(w, greaterThanOrEqualTo(0));
        expect(w, lessThanOrEqualTo(1));
      }
    }
  });
}
