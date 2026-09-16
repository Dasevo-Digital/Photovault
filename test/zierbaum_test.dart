import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/stammbaum.dart';
import 'package:photo_vault/services/zierbaum.dart';

/// Die Anordnung des Zierbaums.
///
/// Der Teil, den man am fertigen Bild nicht beurteilen kann: Ob sich zwei
/// Schilder um ein Hundertstel überlappen, ob ein Kind wirklich mittig
/// unter seinen Eltern sitzt und ob zweimal dasselbe herauskommt.
void main() {
  /// Dieselbe Sippe wie im Geflecht-Prüfstand.
  Verwandtschaftsnetz sippe() => Verwandtschaftsnetz([
        kante('vater', 'opa', Verwandtschaft.elternteil),
        kante('vater', 'oma', Verwandtschaft.elternteil),
        partnerKanteFuer('opa', 'oma'),
        partnerKanteFuer('vater', 'mutter'),
        kante('ich', 'vater', Verwandtschaft.elternteil),
        kante('ich', 'mutter', Verwandtschaft.elternteil),
        kante('anna', 'vater', Verwandtschaft.elternteil),
        kante('anna', 'mutter', Verwandtschaft.elternteil),
        kante('bruno', 'vater', Verwandtschaft.elternteil),
        kante('bruno', 'mutter', Verwandtschaft.elternteil),
        partnerKanteFuer('anna', 'schwager'),
        kante('neffe', 'anna', Verwandtschaft.elternteil),
        kante('neffe', 'schwager', Verwandtschaft.elternteil),
        kante('schwager', 'schwagersVater', Verwandtschaft.elternteil),
        kante('schwager', 'schwagersMutter', Verwandtschaft.elternteil),
        partnerKanteFuer('schwagersVater', 'schwagersMutter'),
        kante('schwagersBruder', 'schwagersVater', Verwandtschaft.elternteil),
        kante('schwagersBruder', 'schwagersMutter', Verwandtschaft.elternteil),
      ]);

  const alle = [
    'opa', 'oma', 'schwagersVater', 'schwagersMutter', 'vater', 'mutter',
    'ich', 'anna', 'bruno', 'schwager', 'schwagersBruder', 'neffe',
  ];

  Zierbaumplan plan([String fokus = 'ich']) =>
      zierbaumplan(geflechtUm(sippe(), fokus, alle));

  Schild schild(Zierbaumplan p, String person) =>
      p.schilder.firstWhere((s) => s.personId == person);

  group('kein Schild steht auf einem anderen', () {
    test('nirgends eine Überschneidung', () {
      final p = plan();
      for (var i = 0; i < p.schilder.length; i++) {
        for (var j = i + 1; j < p.schilder.length; j++) {
          expect(p.schilder[i].ueberschneidet(p.schilder[j]), isFalse,
              reason: '${p.schilder[i]} und ${p.schilder[j]}');
        }
      }
    });

    test('auch bei zwanzig Geschwistern nicht', () {
      // Der Fall, in dem der Schub nach rechts wirklich arbeiten muss.
      final kanten = <Kante>[kante('ich', 'vater', Verwandtschaft.elternteil)];
      final ids = <String>['vater', 'ich'];
      for (var i = 0; i < 20; i++) {
        kanten.add(kante('g$i', 'vater', Verwandtschaft.elternteil));
        ids.add('g$i');
      }
      final p = zierbaumplan(
          geflechtUm(Verwandtschaftsnetz(kanten), 'ich', ids));
      for (var i = 0; i < p.schilder.length; i++) {
        for (var j = i + 1; j < p.schilder.length; j++) {
          expect(p.schilder[i].ueberschneidet(p.schilder[j]), isFalse);
        }
      }
    });
  });

  group('Bänder', () {
    test('eine Generation, eine Höhe', () {
      final p = plan();
      double y(String person) => schild(p, person).oben;
      expect(y('ich'), y('anna'));
      expect(y('ich'), y('schwager'), reason: 'er wohnt bei Anna');
      expect(y('vater'), y('schwagersVater'));
      expect(y('vater'), lessThan(y('ich')), reason: 'Eltern stehen darüber');
      expect(y('neffe'), greaterThan(y('ich')), reason: 'Kinder darunter');
      expect(y('opa'), lessThan(y('vater')));
    });

    test('die Bänder liegen gleich weit auseinander', () {
      final p = plan();
      final abstand = schild(p, 'ich').oben - schild(p, 'vater').oben;
      expect(schild(p, 'vater').oben - schild(p, 'opa').oben,
          closeTo(abstand, 0.001));
      expect(schild(p, 'neffe').oben - schild(p, 'ich').oben,
          closeTo(abstand, 0.001));
    });
  });

  group('Äste', () {
    test('die Schwester und ihr Mann führen zu zwei verschiedenen Häusern', () {
      // Der Kern der ganzen Sache, jetzt in Zahlen: Zwei Schilder
      // nebeneinander, zwei Äste nach oben, zwei verschiedene Ziele.
      final p = plan();
      final annasAst = p.aeste.firstWhere((a) => a.personId == 'anna');
      final schwagersAst = p.aeste.firstWhere((a) => a.personId == 'schwager');
      expect(annasAst.nachX, isNot(closeTo(schwagersAst.nachX, 1)));
      // Annas Ast endet über dem Elternhaus, der des Schwagers über seinem.
      expect(annasAst.nachX, closeTo(
          (schild(p, 'vater').mitteX + schild(p, 'mutter').mitteX) / 2, 0.001));
      expect(schwagersAst.nachX, closeTo(
          (schild(p, 'schwagersVater').mitteX +
                  schild(p, 'schwagersMutter').mitteX) /
              2,
          0.001));
    });

    test('ein Ast beginnt am Schild und endet am Elternhaus', () {
      final p = plan();
      final ast = p.aeste.firstWhere((a) => a.personId == 'neffe');
      expect(ast.vonY, schild(p, 'neffe').oben);
      expect(ast.vonX, schild(p, 'neffe').mitteX);
      expect(ast.nachY, schild(p, 'anna').unten);
    });

    test('getrennt lebende Eltern ergeben zwei Aeste aus einem Schild', () {
      // Der gemeldete Fehler: Im Bild stand der Vater ohne jede
      // Verbindung, weil je Person nur ein Elternhaus gefuehrt wurde und
      // die Mutter zuerst kam.
      final p = zierbaumplan(geflechtUm(
        Verwandtschaftsnetz([
          kante('ich', 'vater', Verwandtschaft.elternteil),
          kante('ich', 'mutter', Verwandtschaft.elternteil),
        ]),
        'ich',
        const ['mutter', 'vater', 'ich'],
      ));
      final meine = p.aeste.where((a) => a.personId == 'ich').toList();
      expect(meine, hasLength(2));
      // Beide gehen an derselben Stelle los und laufen auseinander.
      expect(meine[0].vonX, meine[1].vonX);
      expect(meine[0].nachX, isNot(closeTo(meine[1].nachX, 1)));
      // Und jeder trifft wirklich ein Elternteil, keiner die Leere.
      final ziele = meine.map((a) => a.nachX).toSet();
      expect(ziele, {schild(p, 'vater').mitteX, schild(p, 'mutter').mitteX});
    });

    test('ohne Elternhaus im Bild kein Ast', () {
      // Ein Ast ins Leere wäre eine Behauptung über etwas, das man nicht
      // sieht.
      final p = plan();
      expect(p.aeste.where((a) => a.personId == 'opa'), isEmpty);
    });
  });

  group('Partnerbänder', () {
    test('zwischen zwei Bewohnern eines Haushalts liegt eines', () {
      final p = plan();
      final zwischenAnnaUndSchwager = p.baender.where((b) =>
          b.vonX == schild(p, 'anna').rechts &&
          b.nachX == schild(p, 'schwager').links);
      expect(zwischenAnnaUndSchwager, hasLength(1));
    });

    test('ein Haushalt aus einer Person hat keines', () {
      final p = plan();
      final bruno = schild(p, 'bruno');
      expect(p.baender.where((b) => b.vonX == bruno.rechts), isEmpty);
    });
  });

  group('das Ganze', () {
    test('alles liegt im sichtbaren Bereich', () {
      final p = plan();
      for (final s in p.schilder) {
        expect(s.links, greaterThanOrEqualTo(0));
        expect(s.oben, greaterThanOrEqualTo(0));
        expect(s.rechts, lessThanOrEqualTo(p.breite));
        expect(s.unten, lessThanOrEqualTo(p.hoehe));
      }
    });

    test('unter dem untersten Schild bleibt Platz für den Namen', () {
      final p = plan();
      final tiefstes = p.schilder.map((s) => s.unten).reduce((a, b) => a > b ? a : b);
      expect(p.hoehe - tiefstes, greaterThan(100));
    });

    test('der Stamm steht unter der Person in der Mitte', () {
      final p = plan();
      expect(p.stammX, closeTo(schild(p, 'ich').mitteX, 0.001));
    });

    test('zweimal gerechnet, zweimal dasselbe', () {
      // Ohne feste Reihenfolge sprängen die Häuser bei jedem Aufbau
      // umher – als Flackern, nicht als Fehler.
      expect(plan().schilder, plan().schilder);
      expect(plan().aeste, plan().aeste);
      expect(plan().baender, plan().baender);
    });

    test('grössere Masse ergeben denselben Baum, nur grösser', () {
      // Die Tafel zum Aufhängen geht diesen Weg. Zwei Sätze Konstanten
      // wären zwei Bäume, die auseinanderlaufen können.
      final klein = zierbaumplan(geflechtUm(sippe(), 'ich', alle));
      final gross = zierbaumplan(geflechtUm(sippe(), 'ich', alle),
          masse: const Zierbaummasse().mal(3));
      expect(gross.breite / klein.breite, closeTo(3, 0.001));
      expect(gross.schilder.length, klein.schilder.length);
    });
  });

  test('eine Person ganz ohne Verwandtschaft ergibt ein Schild', () {
    final p = zierbaumplan(
        geflechtUm(Verwandtschaftsnetz(const []), 'allein', ['allein']));
    expect(p.schilder, hasLength(1));
    expect(p.aeste, isEmpty);
    expect(p.schilder.single.links, greaterThanOrEqualTo(0));
  });

  group('das Nachfuehren', () {
    test('wer nach draussen gebunden ist, rueckt nach draussen', () {
      // Der Fund beim Hinsehen: Ein einziger Durchgang von der Mitte
      // nach aussen reichte nicht. Band 0 stand fest, bevor die Eltern
      // und die angeheiratete Familie gesetzt waren, und rueckte danach
      // nie nach.
      //
      // Was sich dadurch aendert, ist die REIHENFOLGE im Band: Annas
      // Haushalt traegt den Schwager und damit dessen ganze Familie mit
      // - er gehoert an deren Seite. Bruno hat keine Bindung nach
      // draussen und gehoert zwischen seine Geschwister. Ohne das
      // Nachfuehren stand es genau andersherum, und Annas Ast kreuzte
      // den von Bruno.
      final p = plan();
      final ich = schild(p, 'ich').mitteX;
      final bruno = schild(p, 'bruno').mitteX;
      final anna = schild(p, 'anna').mitteX;
      final schwiegerfamilie = schild(p, 'schwagersBruder').mitteX;

      expect(schwiegerfamilie, greaterThan(anna),
          reason: 'die angeheiratete Familie liegt auf einer Seite');
      expect(bruno, greaterThan(ich));
      expect(bruno, lessThan(anna),
          reason: 'Bruno gehoert zwischen seine Geschwister, nicht an den Rand');
    });

    test('die Eltern stehen ueber der Mitte ihrer Kinder', () {
      final p = plan();
      final elternMitte =
          (schild(p, 'vater').mitteX + schild(p, 'mutter').mitteX) / 2;
      final kinder = ['ich', 'bruno', 'anna'].map((k) => schild(p, k).mitteX);
      final schwerpunkt = kinder.reduce((a, b) => a + b) / kinder.length;
      // Nicht auf den Punkt: Der Haushalt der Schwester traegt ihren Mann
      // mit, und der zieht ihn ein Stueck nach rechts. Aber in derselben
      // Gegend.
      expect((elternMitte - schwerpunkt).abs(),
          lessThan(const Zierbaummasse().schildBreite * 2));
    });
  });

  group('das Schild traegt, was auf ihm steht', () {
    test('drei Zeilen passen auf die Tafel', () {
      // Der gemeldete Fehler: Auf einem Schild lag "Sohn" halb ueber
      // "Martin". Ein `Flexible` laesst Zeilen nicht ueberlappen - es
      // QUETSCHT sie, und der Text malt dann ueber seinen eigenen Rand
      // hinaus.
      //
      // Nachgerechnet statt nachgemessen: Ein Widget-Test rendert mit
      // einer Platzhalterschrift, deren Zeilenmasse andere sind als die
      // von EB Garamond - er kann diesen Fehler gar nicht zeigen.
      const masse = Zierbaummasse();
      const schild = Schildmasse();
      expect(schild.mindestTafelhoehe(),
          lessThanOrEqualTo(schild.tafelHoehe(masse.schildHoehe)),
          reason: 'Name, Verhaeltnis und Lebensdaten muessen hineinpassen');
    });

    test('zwei Mehrzeichen im Textfluss haetten NICHT gepasst', () {
      // Die Rechnung, die den Fehler erklaert: Die beiden Zeichen kosten
      // je rund dreizehn Punkte. Mit ihnen im Fluss braucht die Tafel
      // mehr, als sie hat - deshalb liegen sie jetzt als Marke am Rand.
      const masse = Zierbaummasse();
      const schild = Schildmasse();
      expect(schild.mindestTafelhoeheMitZeichen(),
          greaterThan(schild.tafelHoehe(masse.schildHoehe)),
          reason: 'sonst waere die Verlegung an den Rand unnoetig gewesen');
    });

    test('auch die vergroesserte Tafel traegt ihre Zeilen', () {
      // Die Tafel zum Aufhaengen rechnet mit demselben Verhaeltnis.
      final masse = const Zierbaummasse().mal(3);
      final schild = const Schildmasse().mal(3);
      expect(schild.mindestTafelhoehe(),
          lessThanOrEqualTo(schild.tafelHoehe(masse.schildHoehe)));
    });
  });

  group('grössere Systemschrift', () {
    /// **Der Fund der 18. Prüfrunde, als Rechnung.**
    ///
    /// In die Tafel eines Schildes passen genau drei Zeilen: 56,6 von 67
    /// Punkten. Das Schild ist in Punkten festgelegt, die Schrift folgte
    /// aber der Systemeinstellung – bei 120 Prozent brauchten dieselben
    /// drei Zeilen 67,9 Punkte, und der Text malte über seinen Rand.
    /// Genau das Bild, das der gemeldete Fehler mit den zwei
    /// Mehrzeichen zeigte, nur ausgelöst durch eine Einstellung des
    /// Systems statt durch den Inhalt.
    ///
    /// Ein Widget-Test findet das nicht – er rendert mit einer
    /// Platzhalterschrift, deren Zeilenmasse andere sind. Nachgewiesen
    /// wurde das in derselben Prüfrunde: Der Prüfstand bestand auch
    /// ohne die Behebung. Die Rechnung gilt für jede Schrift.
    double platzInDerTafel(Schildmasse m, Zierbaummasse b) =>
        m.tafelHoehe(b.schildHoehe);

    test('mitgewachsen passt es bei jeder Einstellung', () {
      for (final faktor in [1.0, 1.15, 1.3, 1.6, 2.0, 3.0]) {
        final m = const Schildmasse().mal(faktor);
        final b = const Zierbaummasse().mal(faktor);
        expect(m.mindestTafelhoehe(), lessThanOrEqualTo(platzInDerTafel(m, b)),
            reason: 'bei Faktor $faktor');
      }
    });

    test('nur die Schrift zu vergrössern sprengt die Tafel', () {
      // Die Gegenprobe: Genau so war es. Das Schild blieb, die Schrift
      // wuchs. Ab knapp 1,2 passte es nicht mehr.
      final tafel = platzInDerTafel(const Schildmasse(), const Zierbaummasse());
      double bedarf(double faktor) => Schildmasse(
            schriftName: 14 * faktor,
            schriftNeben: 11 * faktor,
          ).mindestTafelhoehe();
      expect(bedarf(1.0), lessThanOrEqualTo(tafel));
      // 18,9 + 29,7 Punkte Schrift und 8 Punkte Polster, das gibt
      // 48,6 f + 8 = 67 bei f = 1,21. Darüber malt der Text über den
      // Rand – und das ist keine ungewöhnliche Einstellung.
      expect(bedarf(1.21), lessThanOrEqualTo(tafel));
      expect(bedarf(1.25), greaterThan(tafel),
          reason: 'ab hier lag der Text über der Zeile darüber');
      expect(bedarf(1.5), greaterThan(tafel));
    });
  });
}
