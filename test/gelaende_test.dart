import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/gelaendekacheln.dart';
import 'package:photo_vault/services/gelaendesicht.dart';

/// Die Rechnung hinter der Geländeansicht.
///
/// Zwei Teile: das Umrechnen der Kachelfarben in Meter und die Kamera.
/// Beides lässt sich am fertigen Bild nicht beurteilen – ein
/// seitenverkehrtes Gelände sieht aus wie ein Gelände.
void main() {
  group('Höhen aus Farben', () {
    test('die Formel trifft die bekannten Werte', () {
      // Meereshöhe null ist genau r=128, g=0, b=0.
      expect(hoeheAusFarbe(128, 0, 0), 0);
      // Und ein Meter mehr ist g=1.
      expect(hoeheAusFarbe(128, 1, 0), 1);
      // Das Blau trägt Sechzehntel-Meter... genauer: 1/256.
      expect(hoeheAusFarbe(128, 0, 128), closeTo(0.5, 0.001));
    });

    test('der tiefste und der höchste darstellbare Punkt', () {
      // −32768 m gibt es nicht, aber die Formel muss es hergeben, sonst
      // ist es die falsche Formel.
      expect(hoeheAusFarbe(0, 0, 0), closeTo(-32768, 0.01));
      expect(hoeheAusFarbe(255, 255, 255), closeTo(32767.996, 0.01));
    });

    test('der Vogelsberg kommt heraus, wenn man ihn hineingibt', () {
      // Der Taufstein misst 773 m. In der Kachel 11/1080/689 gemessen
      // lagen die Werte zwischen 336,6 und 814,0 – hier nachgestellt:
      // 773 m sind r=130, g=5 (130·256 + 5 − 32768 = 32773 − 32768 = 5?)
      // Nein: 773 + 32768 = 33541 = 131·256 + 5.
      expect(hoeheAusFarbe(131, 5, 0), 773);
    });
  });

  group('Kachelrechnung', () {
    test('die bekannte Kachel liegt, wo sie liegen soll', () {
      // 11/1080/689 ist die Kachel des Vogelsbergs. Ihre Westkante
      // liegt bei 9,84° – „9,8° O" aus der Beschreibung ist gerundet und
      // fällt schon in die Kachel daneben.
      expect(kachelX(9.9, 11), 1080);
      expect(kachelX(9.8, 11), 1079);
      expect(kachelY(50.6, 11), 689);
    });

    test('Kante und Nummer passen zusammen', () {
      // Der Westrand der Kachel muss wieder in dieselbe Kachel fallen.
      final west = kachelWesten(1080, 11);
      final nord = kachelNorden(689, 11);
      expect(kachelX(west + 0.001, 11), 1080);
      expect(kachelY(nord - 0.001, 11), 689);
    });

    test('die Zeilen laufen von Nord nach Süd', () {
      // Die häufigste Verwechslung: Zeile 0 liegt oben.
      expect(kachelNorden(689, 11), greaterThan(kachelNorden(690, 11)));
    });

    test('der Bereich nimmt die feinste Stufe, die noch passt', () {
      // Ein kleiner Ausschnitt von rund zwei Kilometern.
      final fein = kachelbereich(
          sued: 50.60, west: 9.79, nord: 50.62, ost: 9.82);
      expect(fein.zoom, gelaendeHoechsteStufe);

      // Ein ganzes Land passt auf Stufe 15 nicht in sechzehn Kacheln.
      final grob =
          kachelbereich(sued: 47.0, west: 6.0, nord: 55.0, ost: 15.0);
      expect(grob.zoom, lessThan(8));
      final anzahl = (grob.x1 - grob.x0 + 1) * (grob.y1 - grob.y0 + 1);
      expect(anzahl, lessThanOrEqualTo(16));
    });

    test('die Adressliste hat so viele Einträge wie der Bereich Kacheln',
        () {
      const bereich = (zoom: 11, x0: 1080, y0: 689, x1: 1081, y1: 690);
      expect(kacheladressen(bereich), hasLength(4));
      expect(kacheladresse(11, 1080, 689),
          endsWith('/terrarium/11/1080/689.png'));
    });
  });

  group('Das Höhengitter', () {
    /// Ein Gitter aus einer Kachel mit einer Rampe von 0 auf 255 Metern
    /// von West nach Ost.
    Hoehengitter rampe({int kante = 4}) {
      final rgba = Uint8List(kante * kante * 4);
      for (var y = 0; y < kante; y++) {
        for (var x = 0; x < kante; x++) {
          final meter = x * 100.0;
          final roh = (meter + 32768).round();
          final i = (y * kante + x) * 4;
          rgba[i] = roh >> 8;
          rgba[i + 1] = roh & 255;
          rgba[i + 2] = 0;
          rgba[i + 3] = 255;
        }
      }
      return gitterAusKacheln(
        zoom: 11,
        x0: 1080,
        y0: 689,
        x1: 1080,
        y1: 689,
        kacheln: [(x: 1080, y: 689, rgba: rgba)],
        kante: kante,
      );
    }

    test('die Höhen kommen an der richtigen Stelle an', () {
      final g = rampe();
      expect(g.spalten, 4);
      expect(g.zeilen, 4);
      expect(g.bei(0, 0), closeTo(0, 0.01));
      expect(g.bei(3, 0), closeTo(300, 0.01));
      expect(g.spanne.tief, closeTo(0, 0.01));
      expect(g.spanne.hoch, closeTo(300, 0.01));
    });

    test('eine fehlende Kachel bleibt unbekannt statt Meereshöhe', () {
      // Ein Loch, das mit Null gefüllt wird, sieht aus wie ein See.
      final g = gitterAusKacheln(
        zoom: 11,
        x0: 1080,
        y0: 689,
        x1: 1081,
        y1: 689,
        kacheln: const [],
        kante: 2,
      );
      expect(g.hoehen.every((h) => h.isNaN), isTrue);
      expect(g.spanne.tief, 0);
    });

    test('zwischen den Gitterpunkten wird gerechnet, nicht gerundet', () {
      // Eine Spur über das Gelände sprünge sonst an jeder Gitterlinie.
      final g = rampe();
      final mitte = (g.west + g.ost) / 2;
      final oben = g.nord - (g.nord - g.sued) * 0.01;
      final h = g.anOrt(oben, mitte)!;
      // Genau in der Mitte der Rampe von 0 bis 300.
      expect(h, closeTo(150, 20));
    });

    test('ausserhalb des Ausschnitts gibt es keine Höhe', () {
      final g = rampe();
      expect(g.anOrt(g.nord + 1, g.west), isNull);
      expect(g.anOrt(g.sued, g.ost + 1), isNull);
    });

    test('das Verkleinern behält die Kanten', () {
      // Genommen wird jeder n-te Punkt und nicht der Mittelwert: Ein
      // Mittel über acht Bildpunkte trüge jeden Gipfel ab.
      final g = rampe(kante: 16).verkleinert(4);
      expect(g.spalten, 4);
      expect(g.bei(0, 0), closeTo(0, 0.01));
      // **Der Ostrand muss der Ostrand bleiben.** Jeden vierten Punkt zu
      // nehmen liesse hier bei 1200 aufhören, während [ost] weiter die
      // volle Breite behauptet – die Landschaft wäre gedehnt.
      expect(g.bei(3, 0), closeTo(1500, 0.01));
      // Der Ausschnitt in Grad bleibt derselbe.
      expect(g.west, rampe(kante: 16).west);
      expect(g.ost, rampe(kante: 16).ost);
    });

    test('ein kleines Gitter wird nicht angefasst', () {
      final g = rampe();
      expect(identical(g.verkleinert(64), g), isTrue);
    });
  });

  group('Die Kamera', () {
    const kamera = Gelaendekamera(
      drehung: 0,
      neigung: 0.9,
      entfernung: 10000,
      brennweite: 800,
      mitte: Offset(200, 150),
    );

    test('der Mittelpunkt bleibt in der Mitte', () {
      final p = kamera.projiziere((x: 0, y: 0, z: 0));
      expect(p.stelle.dx, closeTo(200, 0.001));
      expect(p.stelle.dy, closeTo(150, 0.001));
    });

    test('Höhe geht nach oben, nicht nach unten', () {
      // Auf dem Bildschirm wächst y nach unten, in der Landschaft wächst
      // die Höhe nach oben – ohne das Vorzeichen stünden alle Berge auf
      // dem Kopf.
      final unten = kamera.projiziere((x: 0, y: 0, z: 0));
      final oben = kamera.projiziere((x: 0, y: 0, z: 500));
      expect(oben.stelle.dy, lessThan(unten.stelle.dy));
    });

    test('Osten geht nach rechts', () {
      expect(kamera.projiziere((x: 1000, y: 0, z: 0)).stelle.dx,
          greaterThan(200));
    });

    test('was weiter weg ist, wird kleiner', () {
      // Der Beweis, dass es eine Perspektive ist und keine Schrägansicht.
      final nah = kamera.projiziere((x: 1000, y: -3000, z: 0));
      final fern = kamera.projiziere((x: 1000, y: 3000, z: 0));
      expect((nah.stelle.dx - 200).abs(),
          greaterThan((fern.stelle.dx - 200).abs()));
      expect(fern.tiefe, greaterThan(nah.tiefe));
    });

    test('eine halbe Drehung vertauscht Osten und Westen', () {
      final gedreht = kamera.kopieMit(drehung: math.pi);
      expect(gedreht.projiziere((x: 1000, y: 0, z: 0)).stelle.dx,
          lessThan(200));
    });

    test('senkrecht von oben ist eine Karte', () {
      // Bei Neigung 0 darf die Höhe die Stelle nicht verschieben – sonst
      // wäre die Draufsicht schon keine Karte mehr.
      final karte = kamera.kopieMit(neigung: 0);
      final flach = karte.projiziere((x: 1000, y: 1000, z: 0));
      final hoch = karte.projiziere((x: 1000, y: 1000, z: 900));
      expect(hoch.stelle.dx, closeTo(flach.stelle.dx, 0.001));
      // In der Höhe verschiebt sie sich, weil der Punkt näher kommt –
      // aber nicht in der Waagerechten.
      expect(hoch.tiefe, closeTo(flach.tiefe, 0.001));
    });

    test('ein Punkt hinter der Kamera wird als solcher gemeldet', () {
      // Wer ihn trotzdem zeichnet, bekommt Unsinn – deshalb steht die
      // Tiefe dabei.
      final dahinter = kamera.projiziere((x: 0, y: -20000, z: 0));
      expect(dahinter.tiefe, lessThanOrEqualTo(0));
    });
  });

  group('Die Schattierung', () {
    test('eine ebene Fläche bekommt mittleres Licht', () {
      final s = schattierung((x: 0, y: 0, z: 1));
      expect(s, greaterThan(0.5));
      expect(s, lessThan(1.0));
    });

    test('die Nordwestflanke ist heller als die Südostflanke', () {
      // **Die Sonne steht im Nordwesten, obwohl sie das nie tut.** Das
      // Auge liest eine von links oben beleuchtete Fläche als erhaben.
      // Physikalisch richtig beleuchtet wird jedes Tal zum Berg.
      final nordwest = schattierung((x: -1, y: 1, z: 1));
      final suedost = schattierung((x: 1, y: -1, z: 1));
      expect(nordwest, greaterThan(suedost));
    });

    test('nichts wird ganz schwarz', () {
      // Eine schwarze Flanke sieht aus wie ein Loch im Gitter – und die
      // Karte darunter soll lesbar bleiben, denn die Schattierung
      // multipliziert sie.
      expect(schattierung((x: 1, y: -1, z: -1)), greaterThanOrEqualTo(0.5));
    });

    test('die Normale steht senkrecht auf einer waagerechten Fläche', () {
      final n = normale(
        (x: 0, y: 0, z: 100),
        (x: 1, y: 0, z: 100),
        (x: 0, y: 1, z: 100),
      );
      expect(n.x, closeTo(0, 0.0001));
      expect(n.y, closeTo(0, 0.0001));
      expect(n.z.abs(), greaterThan(0));
    });
  });

  group('Meter je Grad', () {
    test('am Äquator ist ein Grad Länge am längsten', () {
      expect(meterJeGradLaenge(0), closeTo(111320, 1));
      expect(meterJeGradLaenge(60), closeTo(55660, 100));
      // In Hannover, wo die Testbibliothek zu Hause ist.
      expect(meterJeGradLaenge(52.37), closeTo(67930, 200));
    });
  });
}
