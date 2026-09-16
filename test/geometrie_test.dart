import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/services/geometry_edits.dart';

/// Geradeziehen und Perspektivkorrektur.
///
/// Beide Rechnungen gehen auf eine Weise schief, die man dem fertigen Bild
/// schlecht ansieht: ein um ein halbes Grad verkantetes Foto, oder eine
/// Entzerrung, die zwei Ecken vertauscht und trotzdem plausibel aussieht.
void main() {
  group('Grösstes Rechteck nach dem Drehen', () {
    test('ohne Drehung bleibt alles', () {
      final m = groesstesRechteckNachDrehung(400, 300, 0);
      expect(m.breite, closeTo(400, 1e-6));
      expect(m.hoehe, closeTo(300, 1e-6));
    });

    test('es passt tatsächlich hinein', () {
      // Die eigentliche Zusicherung: Jede Ecke des berechneten Rechtecks
      // muss nach der Rückdrehung noch im Originalbild liegen. Ein zu
      // grosses Ergebnis liesse leere Ecken stehen – genau das, was der
      // Zuschnitt verhindern soll.
      for (final grad in [1.0, 5.0, 12.5, 30.0, 44.0, -7.0, -25.0]) {
        const w = 400.0, h = 300.0;
        final rad = grad * math.pi / 180;
        final m = groesstesRechteckNachDrehung(w, h, rad);
        final cos = math.cos(rad), sin = math.sin(rad);

        for (final ecke in [
          Offset(m.breite / 2, m.hoehe / 2),
          Offset(-m.breite / 2, m.hoehe / 2),
          Offset(m.breite / 2, -m.hoehe / 2),
          Offset(-m.breite / 2, -m.hoehe / 2),
        ]) {
          // Zurück in das ungedrehte Bild.
          final x = ecke.dx * cos + ecke.dy * sin;
          final y = -ecke.dx * sin + ecke.dy * cos;
          expect(x.abs(), lessThanOrEqualTo(w / 2 + 1e-6), reason: '$grad Grad');
          expect(y.abs(), lessThanOrEqualTo(h / 2 + 1e-6), reason: '$grad Grad');
        }
      }
    });

    test('mehr Drehung heisst weniger Fläche', () {
      var vorher = double.infinity;
      for (final grad in [0.0, 2.0, 5.0, 10.0, 20.0, 35.0]) {
        final m = groesstesRechteckNachDrehung(400, 300, grad * math.pi / 180);
        final flaeche = m.breite * m.hoehe;
        expect(flaeche, lessThanOrEqualTo(vorher + 1e-6), reason: '$grad Grad');
        vorher = flaeche;
      }
    });

    test('die Drehrichtung ändert nichts an der Grösse', () {
      final links = groesstesRechteckNachDrehung(400, 300, -0.2);
      final rechts = groesstesRechteckNachDrehung(400, 300, 0.2);
      expect(links.breite, closeTo(rechts.breite, 1e-9));
      expect(links.hoehe, closeTo(rechts.hoehe, 1e-9));
    });

    test('ein leeres Bild ergibt nichts', () {
      expect(groesstesRechteckNachDrehung(0, 300, 0.3).breite, 0);
    });
  });

  group('Geradeziehen', () {
    test('das Ergebnis ist kleiner, aber nicht leer', () {
      final quelle = img.Image(width: 200, height: 150);
      img.fill(quelle, color: img.ColorRgb8(120, 130, 140));
      final gerade = geradeziehen(quelle, 6);
      expect(gerade.width, lessThan(200));
      expect(gerade.width, greaterThan(100));
      expect(gerade.height, greaterThan(70));
    });

    test('null Grad lässt das Bild unangetastet', () {
      final quelle = img.Image(width: 40, height: 30);
      expect(identical(geradeziehen(quelle, 0), quelle), isTrue);
    });

    test('hin und zurück gewinnt das Bild fast vollständig wieder', () {
      // Die aussagekräftigste Prüfung der ganzen Rechnung: Ein Bild um 8
      // Grad drehen und wieder geradeziehen muss ungefähr die
      // Ausgangsgrösse ergeben. Wäre das eingeschriebene Rechteck zu klein
      // gerechnet, bliebe deutlich weniger übrig; wäre es zu gross, kämen
      // leere Ecken zurück (siehe die Prüfung darunter).
      final ausgang = img.Image(width: 300, height: 200);
      img.fill(ausgang, color: img.ColorRgb8(200, 190, 170));
      final verkantet = img.copyRotate(ausgang, angle: 8);
      final gerade = geradeziehen(verkantet, -8);

      expect(gerade.width, closeTo(300, 4));
      expect(gerade.height, closeTo(200, 4));
    });

    test('es bleiben keine leeren Ecken übrig', () {
      // Ein durchgehend gefülltes Bild darf nach dem Geradeziehen und
      // Zuschneiden keinen einzigen schwarzen Punkt haben.
      final quelle = img.Image(width: 240, height: 180);
      img.fill(quelle, color: img.ColorRgb8(200, 100, 50));
      final gerade = geradeziehen(quelle, 7);
      var leer = 0;
      for (var y = 0; y < gerade.height; y++) {
        for (var x = 0; x < gerade.width; x++) {
          final p = gerade.getPixel(x, y);
          if (p.r < 20 && p.g < 20 && p.b < 20) leer++;
        }
      }
      expect(leer, 0, reason: '$leer leere Punkte übrig');
    });
  });

  group('Homographie', () {
    test('die Eckpunkte landen genau dort, wo sie sollen', () {
      final quelle = [
        const Offset(10, 20),
        const Offset(90, 15),
        const Offset(100, 80),
        const Offset(5, 70),
      ];
      final ziel = [
        Offset.zero,
        const Offset(200, 0),
        const Offset(200, 100),
        const Offset(0, 100),
      ];
      final h = homographie(quelle, ziel)!;
      for (var i = 0; i < 4; i++) {
        final p = abbilden(h, quelle[i].dx, quelle[i].dy);
        expect(p.dx, closeTo(ziel[i].dx, 1e-6), reason: 'Ecke $i');
        expect(p.dy, closeTo(ziel[i].dy, 1e-6), reason: 'Ecke $i');
      }
    });

    test('entartete Punkte werden abgelehnt statt geraten', () {
      // Drei Punkte auf einer Linie: Es gibt keine eindeutige Abbildung,
      // und ein gerechnetes Ergebnis wäre Zufall.
      final aufLinie = [
        const Offset(0, 0),
        const Offset(10, 0),
        const Offset(20, 0),
        const Offset(30, 0),
      ];
      final ziel = [
        Offset.zero,
        const Offset(100, 0),
        const Offset(100, 50),
        const Offset(0, 50),
      ];
      expect(homographie(aufLinie, ziel), isNull);
    });

    test('mit der falschen Zahl an Punkten kommt nichts zurück', () {
      expect(homographie([Offset.zero], [Offset.zero]), isNull);
    });
  });

  group('Perspektivisch entzerren', () {
    /// Ein Bild mit einem verkanteten hellen Viereck auf dunklem Grund.
    img.Image mitViereck(List<Offset> ecken) {
      final bild = img.Image(width: 200, height: 200);
      img.fill(bild, color: img.ColorRgb8(20, 20, 20));
      // Grob füllen: für jeden Punkt prüfen, ob er im Viereck liegt.
      bool drin(double px, double py) {
        var vorzeichen = 0;
        for (var i = 0; i < 4; i++) {
          final a = ecken[i], b = ecken[(i + 1) % 4];
          final kreuz = (b.dx - a.dx) * (py - a.dy) - (b.dy - a.dy) * (px - a.dx);
          final s = kreuz > 0 ? 1 : (kreuz < 0 ? -1 : 0);
          if (s == 0) continue;
          if (vorzeichen == 0) {
            vorzeichen = s;
          } else if (s != vorzeichen) {
            return false;
          }
        }
        return true;
      }

      for (var y = 0; y < 200; y++) {
        for (var x = 0; x < 200; x++) {
          if (drin(x.toDouble(), y.toDouble())) {
            bild.setPixelRgb(x, y, 230, 230, 230);
          }
        }
      }
      return bild;
    }

    test('aus dem verkanteten Viereck wird ein volles Rechteck', () {
      final ecken = [
        const Offset(40, 30),
        const Offset(170, 55),
        const Offset(160, 165),
        const Offset(30, 150),
      ];
      final entzerrt = perspektivischEntzerren(mitViereck(ecken), ecken, 120, 100)!;

      expect(entzerrt.width, 120);
      expect(entzerrt.height, 100);
      // In der Mitte und an allen vier Ecken muss jetzt das Helle stehen.
      for (final punkt in [
        const Offset(0.5, 0.5),
        const Offset(0.05, 0.05),
        const Offset(0.95, 0.05),
        const Offset(0.95, 0.95),
        const Offset(0.05, 0.95),
      ]) {
        final p = entzerrt.getPixel(
            (punkt.dx * 119).round(), (punkt.dy * 99).round());
        expect(p.r, greaterThan(150), reason: 'bei $punkt');
      }
    });

    test('entartete Ecken ergeben null statt eines Zufallsbildes', () {
      final quelle = img.Image(width: 50, height: 50);
      expect(
          perspektivischEntzerren(quelle, [
            Offset.zero,
            const Offset(10, 0),
            const Offset(20, 0),
            const Offset(30, 0),
          ], 40, 40),
          isNull);
    });

    test('eine unsinnige Zielgrösse wird abgelehnt', () {
      final quelle = img.Image(width: 50, height: 50);
      final ecken = [
        Offset.zero,
        const Offset(40, 0),
        const Offset(40, 40),
        const Offset(0, 40)
      ];
      expect(perspektivischEntzerren(quelle, ecken, 0, 40), isNull);
    });
  });
}
