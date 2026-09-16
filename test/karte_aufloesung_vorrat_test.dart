import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/eigenkarte.dart';
import 'package:photo_vault/services/kachelvorrat.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

/// **Vorrat und Karte sprachen nicht dieselbe Sprache.**
///
/// Seit der nachgebildeten doppelten Auflösung fragt die Karte für die
/// Anzeigestufe z die **Serverstufe z+1** an. Der Vorrat lud unverändert
/// die Serverstufen 3 bis 14 und bediente damit nur noch die
/// Anzeigestufen 2 bis 13. Wer auf 14 hineinzoomte, wartete trotz vollem
/// Vorrat aufs Netz – gemeldet als „trotz vorgeladener Karten laden
/// einige Kacheln erst mit ein paar Sekunden Verzögerung".
///
/// An der echten Bibliothek nachgesehen: Esri-Kacheln lagen für die
/// Serverstufen 3 bis 14 im Speicher, ab 15 keine einzige.
void main() {
  setUp(() => setzeKarteHochaufloesend(true));
  tearDown(() {
    setzeKarteHochaufloesend(true);
    setzeEigeneKarte(null);
  });

  group('Der Stufenversatz', () {
    test('ist eins, wenn die Auflösung nachgebildet wird', () {
      expect(stufenversatz(Kartenstil.hell, 2.0), 1);
      expect(nachgebildeteRetina(Kartenstil.hell, 2.0), isTrue);
    });

    test('ist null auf einem gewöhnlichen Bildschirm', () {
      // Dort gibt es nichts nachzubilden - eine Kachel deckt genau ihre
      // Punkte.
      expect(stufenversatz(Kartenstil.hell, 1.0), 0);
    });

    test('ist null, wenn der Server selbst doppelt auflöst', () {
      // Eine Adresse mit {r} bekommt die feineren Kacheln geliefert; die
      // Stufe verschiebt sich dann gar nicht.
      setzeEigeneKarte(const Eigenkarte(
        name: 'Mit r',
        url: 'https://beispiel.de/{z}/{x}/{y}{r}.png',
        nennung: '© Beispiel',
        zugestimmt: true,
      ));
      expect(stufenversatz(Kartenstil.eigene, 2.0), 0);
    });

    test('ist null, wenn die doppelte Auflösung abgeschaltet ist', () {
      setzeKarteHochaufloesend(false);
      expect(stufenversatz(Kartenstil.hell, 2.0), 0);
      expect(nachgebildeteRetina(Kartenstil.hell, 2.0), isFalse);
    });
  });

  group('Die Stufen des Vorrats', () {
    test('rücken mit, wenn die Auflösung nachgebildet wird', () {
      final s = vorratStufen(Kartenstil.hell, 2.0);
      expect(s.von, 4);
      expect(s.bis, 15);
    });

    test('bleiben, wo sie waren, wenn nicht', () {
      final s = vorratStufen(Kartenstil.hell, 1.0);
      expect(s.von, vorratKleinsteStufe);
      expect(s.bis, vorratGroessteStufe);
    });

    test('gehen nicht über die letzte echte Stufe der Quelle hinaus', () {
      // OpenTopoMap hört bei 17 auf und antwortet darüber mit HTTP 200
      // und einer einfarbigen Kachel - vorgeladen wäre das eine Fläche
      // ohne Inhalt.
      final s = vorratStufen(Kartenstil.topo, 2.0, von: 16, bis: 19);
      expect(s.bis, 17);
      expect(s.von, lessThanOrEqualTo(17));
    });

    test('decken genau die Anzeigestufen ab, die die Karte anfordert', () {
      // Der eigentliche Punkt: Anzeigestufe z fragt Serverstufe
      // z + Versatz an, und genau die muss im Vorrat liegen.
      const punktdichte = 2.0;
      final s = vorratStufen(Kartenstil.hell, punktdichte);
      final versatz = stufenversatz(Kartenstil.hell, punktdichte);
      for (var anzeige = vorratKleinsteStufe;
          anzeige <= vorratGroessteStufe;
          anzeige++) {
        final gefragt = anzeige + versatz;
        expect(gefragt, greaterThanOrEqualTo(s.von), reason: 'Anzeige $anzeige');
        expect(gefragt, lessThanOrEqualTo(s.bis), reason: 'Anzeige $anzeige');
      }
    });
  });

  group('Die Einstellung', () {
    test('steht auf an, solange niemand sie angefasst hat', () async {
      final db = AppDatabase(NativeDatabase.memory());
      expect(await db.karteHochaufloesendWert(), isTrue);
      await db.close();
    });

    test('überdauert und lässt sich zurückstellen', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.setzeKarteHochaufloesend(false);
      expect(await db.karteHochaufloesendWert(), isFalse);
      await db.setzeKarteHochaufloesend(true);
      expect(await db.karteHochaufloesendWert(), isTrue);
      await db.close();
    });
  });

  group('Was das kostet', () {
    /// Wie viele Kacheln ein Bildschirm fasst – die Zahl, um die es beim
    /// Zoomen geht.
    int kachelnJeBild(double breite, double hoehe, double kachelgroesse) {
      final sx = (breite / kachelgroesse).ceil() + 3;
      final sy = (hoehe / kachelgroesse).ceil() + 3;
      return sx * sy;
    }

    test('die doppelte Auflösung kostet rund das Zweieinhalbfache', () {
      // Nachgebildet wird sie, indem vier Kacheln der naechsttieferen
      // Stufe an die Stelle einer treten - die Kachelgroesse halbiert
      // sich also von 256 auf 128 Punkte.
      final ohne = kachelnJeBild(1440, 900, 256);
      final mit = kachelnJeBild(1440, 900, 128);
      expect(ohne, 63);
      expect(mit, 165);
      expect(mit / ohne, closeTo(2.6, 0.1));
    });

    test('und eine Stufe mehr im Vorrat kostet das Vierfache', () {
      // Der Grund, warum die verschobene Stufe im Vorrat nicht umsonst
      // ist und im Dialog vor dem Laden stehen muss.
      const gebiet = (sued: 50.0, west: 8.0, nord: 51.0, ost: 9.0);
      final bis14 = kachelListe([gebiet], von: 14, bis: 14).length;
      final bis15 = kachelListe([gebiet], von: 15, bis: 15).length;
      expect(bis15 / bis14, closeTo(4.0, 0.1));
    });
  });
}
