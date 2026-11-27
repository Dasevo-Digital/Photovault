import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kern/services/zusammenfuegen/ausrichtung.dart';
import 'package:kern/services/zusammenfuegen/belichtungsfusion.dart';
import 'package:kern/services/zusammenfuegen/fehler.dart';
import 'package:kern/services/zusammenfuegen/raster.dart';

import 'hilfen/synthetische_bilder.dart';

/// HDR aus einer Belichtungsreihe (#498): Ausrichten aus der Hand und
/// Belichtungsfusion, an künstlichen Reihen mit bekannter Lage.
void main() {
  const breite = 480, hoehe = 360;

  group('Ausrichten', () {
    final bezug = Graubild.aus(belichtungsaufnahme(breite, hoehe, 0));

    test('findet Verschiebung und Drehung auf Bruchteile eines Punkts, '
        'auch zwei Blenden heller oder dunkler', () {
      for (final (ev, dx, dy, grad) in [
        (-2.0, 6.0, -4.0, 0.0),
        (2.0, -5.0, 3.0, 0.8),
        (0.0, 17.0, 9.0, -1.2),
        (2.0, 11.0, -7.0, -0.5),
      ]) {
        final bild = Graubild.aus(
          belichtungsaufnahme(
            breite,
            hoehe,
            ev,
            dx: dx,
            dy: dy,
            winkelGrad: grad,
          ),
        );
        final l = richteAus(bezug, bild);
        final grund = 'EV $ev, soll ($dx, $dy, $grad°), ist $l';
        expect((l.dx - dx).abs(), lessThan(0.5), reason: grund);
        expect((l.dy - dy).abs(), lessThan(0.5), reason: grund);
        expect(
          (l.winkel * 180 / math.pi - grad).abs(),
          lessThan(0.05),
          reason: grund,
        );
      }
    });

    test('Gegenprobe: ohne Drehung bleibt der Winkel null, und ein '
        'deckungsgleiches Bild bleibt, wo es ist', () {
      final gedreht = Graubild.aus(
        belichtungsaufnahme(breite, hoehe, 1, dx: 4, winkelGrad: 0.7),
      );
      expect(richteAus(bezug, gedreht, drehung: false).winkel, 0);
      final gleich = richteAus(
        bezug,
        Graubild.aus(belichtungsaufnahme(breite, hoehe, -1)),
      );
      expect(gleich.winkel, 0);
      expect(gleich.dx.abs(), lessThan(0.05));
      expect(gleich.dy.abs(), lessThan(0.05));
    });

    test('der gemeinsame Ausschnitt lässt Verschiebung und Drehung aussen '
        'vor', () {
      final (x0, y0, w, h) = gemeinsamerAusschnitt(
        const [Lage.ruhe, Lage(6, -4), Lage(-5, 3, 0.01)],
        breite,
        hoehe,
      );
      expect(x0, greaterThanOrEqualTo(6));
      expect(y0, greaterThanOrEqualTo(3));
      expect(x0 + w, lessThanOrEqualTo(breite - 5));
      expect(y0 + h, lessThanOrEqualTo(hoehe - 4));
      // Die Drehung um 0,57° kostet an jeder Seite noch ein paar Punkte.
      expect(w, lessThan(breite - 11));
    });
  });

  group('Belichtungsfusion', () {
    final reihe = [
      belichtungsaufnahme(breite, hoehe, -2, dx: 6, dy: -4),
      belichtungsaufnahme(breite, hoehe, 0),
      belichtungsaufnahme(breite, hoehe, 2, dx: -5, dy: 3, winkelGrad: 0.8),
    ];

    test('erhält Lichter und Schatten besser als jede einzelne Aufnahme', () {
      final e = fuegeBelichtungen(3, (i) => reihe[i]);
      expect(e.bezug, 1, reason: 'die mittlere Belichtung ist der Bezug');
      // Die Zeichnung in Schatten, Mitte und Lichtern, bezogen auf die
      // beste Einzelaufnahme in diesem Bereich; bewertet wird der
      // schwächste Bereich.
      const bereiche = [(0.03, 0.2), (0.4, 0.6), (0.8, 0.97)];
      final beste = [
        for (final (a, b) in bereiche)
          reihe.map((r) => zeichnung(r, a, b)).reduce(math.max),
      ];
      double wertung(Farbbild bild) {
        var schwaechste = double.infinity;
        for (var k = 0; k < bereiche.length; k++) {
          final (a, b) = bereiche[k];
          schwaechste = math.min(schwaechste, zeichnung(bild, a, b) / beste[k]);
        }
        return schwaechste;
      }

      final fusion = wertung(e.bild);
      expect(fusion, greaterThan(0.8));
      for (var i = 0; i < reihe.length; i++) {
        expect(fusion, greaterThan(wertung(reihe[i]) + 0.3), reason: '$i');
      }
      // Ausgefressen ist weniger als in jeder Einzelaufnahme.
      final weiss = anteil(e.bild, (v) => v >= 250);
      for (final r in reihe) {
        expect(weiss, lessThan(anteil(r, (v) => v >= 250)));
      }
    });

    test('Gegenprobe: ohne Ausrichten weicht das Ergebnis deutlich mehr '
        'von einer deckungsgleichen Reihe ab', () {
      // Die Vergleichsreihe liegt deckungsgleich und wird ohne Ausrichten
      // verschmolzen: Ihr Ergebnis hat genau die Masse des Bezugsbilds.
      final deckend = fuegeBelichtungen(
        3,
        (i) => belichtungsaufnahme(breite, hoehe, [-2.0, 0.0, 2.0][i]),
        optionen: const HdrOptionen(ausrichten: false),
      ).bild;
      final mit = fuegeBelichtungen(3, (i) => reihe[i]);
      final ohne = fuegeBelichtungen(
        3,
        (i) => reihe[i],
        optionen: const HdrOptionen(ausrichten: false),
      ).bild;
      expect(ohne.breite, breite, reason: 'ohne Lage kein Zuschnitt');
      final (x0, y0, w, h) = mit.ausschnitt;
      double abweichung(Farbbild b, int bx, int by) {
        var s = 0.0;
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            for (var k = 0; k < 3; k++) {
              final v = b.rgb[((y + by) * b.breite + x + bx) * 3 + k];
              final r = deckend.rgb[((y + y0) * breite + x + x0) * 3 + k];
              s += (v - r).abs();
            }
          }
        }
        return s / (w * h * 3);
      }

      final fehlerMit = abweichung(mit.bild, 0, 0);
      final fehlerOhne = abweichung(ohne, x0, y0);
      expect(fehlerMit, lessThan(fehlerOhne * 0.6));
    });

    test('verkleinert über der Grenze und nimmt gleich geformte Quellen '
        'anderer Grösse', () {
      final e = fuegeBelichtungen(
        2,
        (i) => i == 0
            ? belichtungsaufnahme(240, 180, -1)
            : belichtungsaufnahme(480, 360, 1),
        optionen: const HdrOptionen(hoechstensPixel: 30000),
      );
      expect(e.bild.pixel, lessThanOrEqualTo(30000));
      expect(e.bild.breite / e.bild.hoehe, closeTo(4 / 3, 0.02));
    });

    test('Fehlerfälle: Anzahl und Seitenverhältnis', () {
      final quer = belichtungsaufnahme(120, 90, 0);
      final hoch = belichtungsaufnahme(90, 120, 0);
      expect(
        () => fuegeBelichtungen(1, (_) => quer),
        throwsA(
          isA<Zusammenfuegefehler>().having(
            (f) => f.grund,
            'grund',
            Fuegegrund.anzahl,
          ),
        ),
      );
      expect(
        () => fuegeBelichtungen(hdrHoechstens + 1, (_) => quer),
        throwsA(isA<Zusammenfuegefehler>()),
      );
      expect(
        () => fuegeBelichtungen(3, (i) => i == 2 ? hoch : quer),
        throwsA(
          isA<Zusammenfuegefehler>()
              .having((f) => f.grund, 'grund', Fuegegrund.groessenUngleich)
              .having((f) => f.quelle, 'quelle', 2),
        ),
      );
    });
  });
}
