import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/face_threshold.dart';

/// Die Herleitung der persönlichen Wiedererkennungs-Schwelle.
///
/// Sie verstellt sich hinter dem Rücken des Nutzers – deshalb muss sie
/// erstens nachvollziehbar bleiben und zweitens im Zweifel nichts tun. Eine
/// erfundene Zahl aus widersprüchlichen Klicks wäre schlimmer als gar keine
/// Anpassung: Sie liesse eine Person unauffindbar werden, ohne dass jemand
/// den Grund fände.
void main() {
  const allgemein = 0.363;

  GesichtsRueckmeldung ja(double s) => GesichtsRueckmeldung(bestaetigt: true, aehnlichkeit: s);
  GesichtsRueckmeldung nein(double s) => GesichtsRueckmeldung(bestaetigt: false, aehnlichkeit: s);

  group('Wann überhaupt abgewichen wird', () {
    test('ohne Rückmeldungen gilt die allgemeine Schwelle', () {
      expect(leiteSchwelleAb(const [], allgemein), allgemein);
      expect(herkunft(const [], allgemein), SchwellenHerkunft.zuWenigDaten);
    });

    test('zwei Entscheidungen sind noch kein Muster', () {
      final wenige = [ja(0.5), nein(0.3)];
      expect(leiteSchwelleAb(wenige, allgemein), allgemein);
      expect(herkunft(wenige, allgemein), SchwellenHerkunft.zuWenigDaten);
    });

    test('ab der dritten Entscheidung wird gerechnet', () {
      final drei = [ja(0.5), ja(0.55), nein(0.3)];
      expect(leiteSchwelleAb(drei, allgemein), isNot(allgemein));
      expect(herkunft(drei, allgemein), SchwellenHerkunft.angepasst);
    });
  });

  group('Saubere Trennung', () {
    test('die Schwelle liegt zwischen den beiden Gruppen', () {
      // Bestätigt ab 0,50, abgelehnt bis 0,40 – die Mitte ist 0,45.
      final r = [ja(0.5), ja(0.7), nein(0.4), nein(0.2)];
      expect(leiteSchwelleAb(r, allgemein), closeTo(0.45, 1e-9));
    });

    test('nur die Randwerte zählen, nicht wie viele es sind', () {
      // Zehn weitere Bestätigungen in der Mitte ändern nichts: Massgeblich
      // sind die schwächste bestätigte und die stärkste abgelehnte.
      final wenige = [ja(0.5), ja(0.7), nein(0.4)];
      final viele = [
        ja(0.5), ja(0.7), nein(0.4),
        for (var i = 0; i < 10; i++) ja(0.6),
      ];
      expect(leiteSchwelleAb(viele, allgemein), leiteSchwelleAb(wenige, allgemein));
    });
  });

  group('Widerspruch', () {
    test('überschneiden sich die Gruppen, bleibt es beim allgemeinen Wert', () {
      // Ein abgelehntes Gesicht ähnlicher als ein bestätigtes – typisch bei
      // Geschwistern. Daraus lässt sich keine Trennlinie gewinnen.
      final r = [ja(0.45), nein(0.6), ja(0.7)];
      expect(leiteSchwelleAb(r, allgemein), allgemein);
      expect(herkunft(r, allgemein), SchwellenHerkunft.widerspruch);
    });

    test('Gleichstand gilt schon als Widerspruch', () {
      final r = [ja(0.5), nein(0.5), ja(0.8)];
      expect(leiteSchwelleAb(r, allgemein), allgemein);
      expect(herkunft(r, allgemein), SchwellenHerkunft.widerspruch);
    });
  });

  group('Nur eine Sorte Rückmeldung', () {
    test('nur Bestätigungen senken die Schwelle knapp unter die schwächste', () {
      final r = [ja(0.32), ja(0.5), ja(0.6)];
      expect(leiteSchwelleAb(r, allgemein), closeTo(0.31, 1e-9));
    });

    test('liegen alle Bestätigungen darüber, bleibt die Schwelle, wo sie war', () {
      // Sie zu senken gäbe es keinen Anlass – es hat ja nichts gefehlt.
      final r = [ja(0.5), ja(0.6), ja(0.7)];
      expect(leiteSchwelleAb(r, allgemein), allgemein);
      expect(herkunft(r, allgemein), SchwellenHerkunft.wieAllgemein);
    });

    test('nur Ablehnungen heben die Schwelle knapp über die stärkste', () {
      final r = [nein(0.4), nein(0.38), nein(0.2)];
      expect(leiteSchwelleAb(r, allgemein), closeTo(0.41, 1e-9));
    });

    test('liegen alle Ablehnungen darunter, bleibt die Schwelle', () {
      final r = [nein(0.1), nein(0.2), nein(0.3)];
      expect(leiteSchwelleAb(r, allgemein), allgemein);
    });
  });

  group('Der Deckel', () {
    test('ein einzelner Fehlklick macht niemanden unauffindbar', () {
      // Ohne Deckel läge die Schwelle bei knapp 1,0 – diese Person käme in
      // keinem Vorschlag mehr vor, und niemand fände den Grund.
      final r = [nein(0.99), nein(0.2), nein(0.1)];
      expect(leiteSchwelleAb(r, allgemein), closeTo(allgemein + maximaleAbweichung, 1e-9));
    });

    test('und nach unten wird ebenso begrenzt', () {
      final r = [ja(0.02), ja(0.9), ja(0.95)];
      expect(leiteSchwelleAb(r, allgemein), closeTo(allgemein - maximaleAbweichung, 1e-9));
    });

    test('auch die saubere Trennung wird gedeckelt', () {
      final r = [ja(0.95), ja(0.97), nein(0.9)];
      expect(leiteSchwelleAb(r, allgemein), closeTo(allgemein + maximaleAbweichung, 1e-9));
    });
  });

  test('eine andere allgemeine Schwelle verschiebt alles mit', () {
    // Der Nutzer kann die allgemeine Schwelle in den Werkzeugen ändern;
    // die persönliche darf sich davon nicht abkoppeln.
    final r = [nein(0.99), nein(0.2), nein(0.1)];
    expect(leiteSchwelleAb(r, 0.5), closeTo(0.5 + maximaleAbweichung, 1e-9));
    expect(leiteSchwelleAb(const [], 0.5), 0.5);
  });
}
