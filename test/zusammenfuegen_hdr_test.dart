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
      // Die kleinere Quelle zeigt dieselbe Szene – das Muster der
      // künstlichen Aufnahmen hängt an Punkten, nicht an der Bildgrösse,
      // und eine anders gezeichnete Szene liesse sich nicht ausrichten.
      final e = fuegeBelichtungen(
        2,
        (i) => i == 0
            ? verkleinere(belichtungsaufnahme(480, 360, -1), 240, 180)
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

    test('eine Aufnahme, die auch ausgerichtet nicht passt, scheitert '
        'verständlich statt mit Doppelkanten (#498)', () {
      // Weiter verschoben, als die Suche reicht (bei 480 Punkten gut 15).
      final weit = belichtungsaufnahme(breite, hoehe, 2, dx: 60, dy: 40);
      expect(
        () => fuegeBelichtungen(3, (i) => [reihe[0], reihe[1], weit][i]),
        throwsA(
          isA<Zusammenfuegefehler>()
              .having((f) => f.grund, 'grund', Fuegegrund.nichtAusrichtbar)
              .having((f) => f.quelle, 'quelle', 2),
        ),
      );
      // Gegenprobe: ohne Ausrichten wird nichts geprüft.
      expect(
        fuegeBelichtungen(
          3,
          (i) => [reihe[0], reihe[1], weit][i],
          optionen: const HdrOptionen(ausrichten: false),
        ).bild.breite,
        breite,
      );
    });

    test('vom Stativ bleibt jede Aufnahme unverschoben, und zu kleine '
        'Aufnahmen scheitern mit eigenem Grund', () {
      final stativ = fuegeBelichtungen(
        3,
        (i) => belichtungsaufnahme(breite, hoehe, [-3.0, 0.0, 3.0][i]),
      );
      for (final l in stativ.lagen) {
        expect((l.dx, l.dy, l.winkel), (0, 0, 0));
      }
      expect(stativ.bild.breite, breite);
      final winzig = [
        for (final ev in [-1.0, 1.0]) belichtungsaufnahme(40, 30, ev),
      ];
      expect(
        () => fuegeBelichtungen(2, (i) => winzig[i]),
        throwsA(
          isA<Zusammenfuegefehler>().having(
            (f) => f.grund,
            'grund',
            Fuegegrund.zuKlein,
          ),
        ),
      );
      expect(
        fuegeBelichtungen(
          2,
          (i) => winzig[i],
          optionen: const HdrOptionen(ausrichten: false),
        ).bild.breite,
        40,
      );
    });

    test('eine Schwarzweissreihe wird verschmolzen, nicht bloss gemittelt '
        '(#498)', () {
      Farbbild grau(Farbbild b) {
        final g = Farbbild.leer(b.breite, b.hoehe);
        for (var i = 0; i < b.rgb.length; i += 3) {
          g.rgb[i] = g.rgb[i + 1] = g.rgb[i + 2] = b.rgb[i];
        }
        return g;
      }

      final sw = [
        for (final ev in [-2.0, 0.0, 2.0])
          grau(belichtungsaufnahme(breite, hoehe, ev)),
      ];
      final fusion = fuegeBelichtungen(3, (i) => sw[i]).bild;
      final mittel = Farbbild.leer(breite, hoehe);
      for (var k = 0; k < mittel.rgb.length; k++) {
        mittel.rgb[k] = (sw[0].rgb[k] + sw[1].rgb[k] + sw[2].rgb[k]) ~/ 3;
      }
      // Mehr Zeichnung als das Mittel in Schatten und Lichtern.
      for (final (a, b) in const [(0.03, 0.2), (0.8, 0.97)]) {
        expect(
          zeichnung(fusion, a, b),
          greaterThan(zeichnung(mittel, a, b) * 1.15),
          reason: '$a–$b',
        );
      }
      // Gegenprobe: Mit der Sättigung im Gewicht ist es überall dasselbe –
      // eben das Mittel.
      final mitSaettigung = gewichteNachMertens(sw[1]);
      expect(mitSaettigung.werte.every((w) => w < 1e-11), isTrue);
      expect(
        gewichteNachMertens(
          sw[1],
          saettigung: false,
        ).werte.any((w) => w > 1e-3),
        isTrue,
      );
    });

    test('die kleine Fassung im ersten Durchgang ergibt dieselben Lagen und '
        'dieselbe Grösse; voll gelesen wird jede Quelle nur einmal', () {
      final voll = fuegeBelichtungen(3, (i) => reihe[i]);
      var gelesen = 0;
      final klein = fuegeBelichtungen(
        3,
        (i) {
          gelesen++;
          return reihe[i];
        },
        ladeKlein: (i) => (
          bild: verkleinere(reihe[i], breite ~/ 2, hoehe ~/ 2),
          breite: breite,
          hoehe: hoehe,
        ),
      );
      expect(gelesen, 3);
      expect(klein.bezug, voll.bezug);
      expect(klein.ausschnitt, voll.ausschnitt);
      for (var i = 0; i < 3; i++) {
        final (a, b) = (klein.lagen[i], voll.lagen[i]);
        expect((a.dx - b.dx).abs(), lessThan(0.5), reason: '$i: $a / $b');
        expect((a.dy - b.dy).abs(), lessThan(0.5), reason: '$i: $a / $b');
        expect(
          (a.winkel - b.winkel).abs() * 180 / math.pi,
          lessThan(0.05),
          reason: '$i: $a / $b',
        );
      }
    });
  });
}
