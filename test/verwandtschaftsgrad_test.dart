import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/stammbaum.dart';
import 'package:photo_vault/services/verwandtschaftsgrad.dart';

/// Die Verwandtschaftsbezeichnungen.
///
/// Der Teil des Stammbaums, den man nicht ansehen, sondern nur nachrechnen
/// kann: Ob jemand der Großonkel oder der Cousin zweiten Grades ist, sieht
/// man einer Karte nicht an. Zwei Fehler sind hier besonders leicht und
/// besonders peinlich: die Richtung zu verwechseln (der Enkel als Großvater)
/// und Halbgeschwister zu behaupten, wo nur ein Elternteil eingetragen ist.
void main() {
  /// Vier Generationen, ein Seitenzweig, eine Anheirat:
  ///
  ///   urgrossvater
  ///        |
  ///     opa == oma        opasBruder
  ///        |                  |
  ///   vater == mutter      cousine1Elternteil
  ///        |                  |
  ///   ich, schwester       cousine
  ///        |
  ///     tochter
  ///        |
  ///     enkelin
  Verwandtschaftsnetz sippe() => Verwandtschaftsnetz([
        kante('opa', 'urgrossvater', Verwandtschaft.elternteil),
        kante('opasBruder', 'urgrossvater', Verwandtschaft.elternteil),
        partnerKanteFuer('opa', 'oma'),
        kante('vater', 'opa', Verwandtschaft.elternteil),
        kante('vater', 'oma', Verwandtschaft.elternteil),
        partnerKanteFuer('vater', 'mutter'),
        kante('ich', 'vater', Verwandtschaft.elternteil),
        kante('ich', 'mutter', Verwandtschaft.elternteil),
        kante('schwester', 'vater', Verwandtschaft.elternteil),
        kante('schwester', 'mutter', Verwandtschaft.elternteil),
        kante('tochter', 'ich', Verwandtschaft.elternteil),
        kante('enkelin', 'tochter', Verwandtschaft.elternteil),
        kante('cousine1Elternteil', 'opasBruder', Verwandtschaft.elternteil),
        kante('cousine', 'cousine1Elternteil', Verwandtschaft.elternteil),
        partnerKanteFuer('ich', 'gatte'),
        kante('schwiegervater', 'niemand', Verwandtschaft.elternteil),
      ]);

  Grad grad(String andere, [String ich = 'ich']) =>
      bestimmeGrad(sippe(), ich, andere);

  group('gerade Linie', () {
    test('Eltern, Großeltern, Urgroßeltern', () {
      // Eine unmittelbare Elternschaft trägt ihre Art mit – hier die
      // leibliche.
      expect(grad('vater'),
          const Grad(Gradart.vorfahre,
              aufwaerts: 1, elternArt: Verwandtschaft.elternteil));
      expect(grad('opa'), const Grad(Gradart.vorfahre, aufwaerts: 2));
      expect(grad('urgrossvater'), const Grad(Gradart.vorfahre, aufwaerts: 3));
    });

    test('Kind, Enkel', () {
      expect(grad('tochter'),
          const Grad(Gradart.nachkomme,
              abwaerts: 1, elternArt: Verwandtschaft.elternteil));
      expect(grad('enkelin'), const Grad(Gradart.nachkomme, abwaerts: 2));
    });

    test('die Richtung stimmt auch umgekehrt', () {
      // Der häufigste denkbare Fehler: oben und unten vertauscht.
      expect(grad('ich', 'urgrossvater'),
          const Grad(Gradart.nachkomme, abwaerts: 3));
      expect(grad('ich', 'enkelin'), const Grad(Gradart.vorfahre, aufwaerts: 2));
    });
  });

  group('Seitenlinien', () {
    test('Geschwister', () {
      expect(grad('schwester').art, Gradart.geschwister);
      expect(grad('schwester').halb, isFalse);
    });

    test('Großonkel', () {
      // Der Bruder des Großvaters: drei Stufen hinauf zum gemeinsamen
      // Urgroßvater, eine hinab. Zwei hinauf wäre der Bruder eines
      // Elternteils – also der Onkel.
      expect(grad('opasBruder'),
          const Grad(Gradart.vorfahrengeschwister, aufwaerts: 3, abwaerts: 1));
    });

    test('der Cousin des Vaters ist kein Onkel', () {
      // Ein Fall, bei dem die Umgangssprache („Onkel") und die
      // Verwandtschaftsrechnung auseinandergehen. Drei Stufen hinauf, zwei
      // hinab: Cousin ersten Grades, einmal entfernt.
      final g = grad('cousine1Elternteil');
      expect(g.art, Gradart.cousin);
      expect(g.cousinGrad, 1);
      expect(g.entfernung, 1);
    });

    test('Nichte und Großnichte', () {
      final netz = Verwandtschaftsnetz([
        kante('ich', 'vater', Verwandtschaft.elternteil),
        kante('bruder', 'vater', Verwandtschaft.elternteil),
        kante('neffe', 'bruder', Verwandtschaft.elternteil),
        kante('grossneffe', 'neffe', Verwandtschaft.elternteil),
      ]);
      expect(bestimmeGrad(netz, 'ich', 'neffe'),
          const Grad(Gradart.geschwisterkind, aufwaerts: 1, abwaerts: 2));
      expect(bestimmeGrad(netz, 'ich', 'grossneffe'),
          const Grad(Gradart.geschwisterkind, aufwaerts: 1, abwaerts: 3));
    });

    test('Cousine ersten Grades, einmal entfernt', () {
      // Der gemeinsame Vorfahr ist der Urgroßvater: von mir drei Stufen
      // hinauf, von der Cousine drei hinab – also Cousine zweiten Grades.
      final g = grad('cousine');
      expect(g.art, Gradart.cousin);
      expect(g.cousinGrad, 2);
      expect(g.entfernung, 0);
    });

    test('ungleiche Abstände ergeben eine Entfernung', () {
      final netz = Verwandtschaftsnetz([
        kante('a', 'ahn', Verwandtschaft.elternteil),
        kante('b', 'ahn', Verwandtschaft.elternteil),
        kante('aKind', 'a', Verwandtschaft.elternteil),
        kante('aEnkel', 'aKind', Verwandtschaft.elternteil),
        kante('bKind', 'b', Verwandtschaft.elternteil),
      ]);
      final g = bestimmeGrad(netz, 'aEnkel', 'bKind');
      expect(g.art, Gradart.cousin);
      expect(g.cousinGrad, 1, reason: 'der kleinere Abstand bestimmt den Grad');
      expect(g.entfernung, 1);
    });
  });

  group('Halbgeschwister', () {
    test('ein gemeinsamer Elternteil bei zwei eingetragenen', () {
      final netz = Verwandtschaftsnetz([
        kante('ich', 'vater', Verwandtschaft.elternteil),
        kante('ich', 'mutter', Verwandtschaft.elternteil),
        kante('halb', 'vater', Verwandtschaft.elternteil),
        kante('halb', 'andereMutter', Verwandtschaft.elternteil),
      ]);
      expect(bestimmeGrad(netz, 'ich', 'halb').halb, isTrue);
    });

    test('aber nicht, wenn nur ein Elternteil bekannt ist', () {
      // Sonst behauptete die App etwas über den zweiten, nicht
      // eingetragenen Elternteil.
      final netz = Verwandtschaftsnetz([
        kante('ich', 'vater', Verwandtschaft.elternteil),
        kante('bruder', 'vater', Verwandtschaft.elternteil),
      ]);
      expect(bestimmeGrad(netz, 'ich', 'bruder').halb, isFalse);
    });
  });

  group('angeheiratet', () {
    test('Partner', () {
      expect(grad('gatte').art, Gradart.partner);
    });

    test('Schwager von beiden Seiten', () {
      final netz = Verwandtschaftsnetz([
        kante('ich', 'vater', Verwandtschaft.elternteil),
        kante('schwester', 'vater', Verwandtschaft.elternteil),
        partnerKanteFuer('schwester', 'ihrMann'),
        partnerKanteFuer('ich', 'meineFrau'),
        kante('ihrBruder', 'fremderVater', Verwandtschaft.elternteil),
        kante('meineFrau', 'fremderVater', Verwandtschaft.elternteil),
      ]);
      // Der Mann meiner Schwester …
      expect(bestimmeGrad(netz, 'ich', 'ihrMann').art, Gradart.schwager);
      // … und der Bruder meiner Frau.
      expect(bestimmeGrad(netz, 'ich', 'ihrBruder').art, Gradart.schwager);
    });

    test('Schwiegereltern und Schwiegerkind', () {
      final netz = Verwandtschaftsnetz([
        partnerKanteFuer('ich', 'gattin'),
        kante('gattin', 'ihrVater', Verwandtschaft.elternteil),
        kante('sohn', 'ich', Verwandtschaft.elternteil),
        partnerKanteFuer('sohn', 'seineFrau'),
      ]);
      expect(bestimmeGrad(netz, 'ich', 'ihrVater').art, Gradart.schwiegerelternteil);
      expect(bestimmeGrad(netz, 'ich', 'seineFrau').art, Gradart.schwiegerkind);
    });

    test('Stiefeltern, Stiefkind, Stiefgeschwister', () {
      final netz = Verwandtschaftsnetz([
        kante('ich', 'mutter', Verwandtschaft.elternteil),
        partnerKanteFuer('mutter', 'stiefvater'),
        kante('stiefbruder', 'stiefvater', Verwandtschaft.elternteil),
        partnerKanteFuer('ich', 'gattin'),
        kante('ihrKind', 'gattin', Verwandtschaft.elternteil),
      ]);
      expect(bestimmeGrad(netz, 'ich', 'stiefvater').art, Gradart.stiefelternteil);
      expect(bestimmeGrad(netz, 'ich', 'stiefbruder').art, Gradart.stiefgeschwister);
      expect(bestimmeGrad(netz, 'ich', 'ihrKind').art, Gradart.stiefkind);
    });

    test('Blutsverwandtschaft geht vor Anheirat', () {
      // Wer seine Cousine geheiratet hat, bleibt in erster Linie ihr
      // Cousin – sonst verschwände die nähere Verwandtschaft aus der Liste.
      final netz = Verwandtschaftsnetz([
        kante('ich', 'vater', Verwandtschaft.elternteil),
        kante('onkel', 'grossvater', Verwandtschaft.elternteil),
        kante('vater', 'grossvater', Verwandtschaft.elternteil),
        kante('cousine', 'onkel', Verwandtschaft.elternteil),
        partnerKanteFuer('ich', 'cousine'),
      ]);
      expect(bestimmeGrad(netz, 'ich', 'cousine').art, Gradart.cousin);
    });
  });

  group('Adoption und Pflege', () {
    Verwandtschaftsnetz netz() => Verwandtschaftsnetz([
          kante('ich', 'leiblich', Verwandtschaft.elternteil),
          kante('ich', 'adoptiv', Verwandtschaft.adoptivelternteil),
          kante('ich', 'pflege', Verwandtschaft.pflegeelternteil),
          kante('adoptiv', 'adoptivOpa', Verwandtschaft.elternteil),
        ]);

    test('zählen überall als Eltern', () {
      expect(netz().eltern('ich'), {'leiblich', 'adoptiv', 'pflege'});
      expect(netz().kinder('adoptiv'), {'ich'});
    });

    test('unterscheiden sich in der Bezeichnung', () {
      expect(bestimmeGrad(netz(), 'ich', 'leiblich').elternArt,
          Verwandtschaft.elternteil);
      expect(bestimmeGrad(netz(), 'ich', 'adoptiv').elternArt,
          Verwandtschaft.adoptivelternteil);
      expect(bestimmeGrad(netz(), 'ich', 'pflege').elternArt,
          Verwandtschaft.pflegeelternteil);
    });

    test('auch in der Gegenrichtung', () {
      final g = bestimmeGrad(netz(), 'adoptiv', 'ich');
      expect(g.art, Gradart.nachkomme);
      expect(g.elternArt, Verwandtschaft.adoptivelternteil);
    });

    test('die Unterscheidung endet nach einer Stufe', () {
      // Der Vater des Adoptivvaters heißt Großvater – für alles andere
      // gibt es keine Wörter.
      final g = bestimmeGrad(netz(), 'ich', 'adoptivOpa');
      expect(g.art, Gradart.vorfahre);
      expect(g.aufwaerts, 2);
      expect(g.elternArt, isNull);
    });

    test('ein Adoptivelternteil kann Vorfahre sein und damit einen Kreis '
        'auslösen', () {
      expect(netz().istVorfahreVon('adoptivOpa', 'ich'), isTrue);
      expect(
          pruefeBeziehung(netz(), 'adoptivOpa', 'ich',
              Verwandtschaft.adoptivelternteil),
          Beziehungsfehler.kreis);
    });

    test('wer schon leiblicher Elternteil ist, wird nicht zusätzlich '
        'Adoptivelternteil', () {
      expect(
          pruefeBeziehung(netz(), 'ich', 'leiblich',
              Verwandtschaft.adoptivelternteil),
          Beziehungsfehler.schonVorhanden);
    });

    test('Geschwister über einen Adoptivelternteil zählen als Geschwister', () {
      final n = Verwandtschaftsnetz([
        kante('a', 'p', Verwandtschaft.adoptivelternteil),
        kante('b', 'p', Verwandtschaft.elternteil),
      ]);
      expect(bestimmeGrad(n, 'a', 'b').art, Gradart.geschwister);
    });
  });

  group('Grenzfälle', () {
    test('die Person selbst', () {
      expect(grad('ich').art, Gradart.selbst);
    });

    test('ohne jede Verbindung', () {
      expect(grad('schwiegervater').art, Gradart.keine);
    });

    test('ein Kreis im Bestand bringt die Suche nicht zum Stehen', () {
      final netz = Verwandtschaftsnetz([
        kante('a', 'b', Verwandtschaft.elternteil),
        kante('b', 'a', Verwandtschaft.elternteil),
      ]);
      expect(bestimmeGrad(netz, 'a', 'fremd').art, Gradart.keine);
    });
  });

  group('alleGrade und Reihenfolge', () {
    test('lässt Unverwandte weg', () {
      final alle = alleGrade(sippe(), 'ich',
          ['vater', 'schwester', 'gatte', 'schwiegervater', 'ich']);
      expect(alle.keys, containsAll(['vater', 'schwester', 'gatte']));
      expect(alle.containsKey('schwiegervater'), isFalse);
      expect(alle.containsKey('ich'), isFalse, reason: 'sich selbst nicht');
    });

    test('stellt die nächsten Angehörigen voran', () {
      final reihe = [
        const Grad(Gradart.cousin, aufwaerts: 2, abwaerts: 2),
        const Grad(Gradart.partner),
        const Grad(Gradart.vorfahre, aufwaerts: 1),
        const Grad(Gradart.angeheiratet),
        const Grad(Gradart.geschwister, aufwaerts: 1, abwaerts: 1),
      ]..sort((a, b) => naeheRang(a).compareTo(naeheRang(b)));
      expect(reihe.map((g) => g.art), [
        Gradart.partner,
        Gradart.geschwister,
        Gradart.vorfahre,
        Gradart.cousin,
        Gradart.angeheiratet,
      ]);
    });
  });

  group('Geschlecht', () {
    test('wandelt hin und zurück', () {
      for (final g in Geschlecht.values) {
        expect(geschlechtAusText(geschlechtZuText(g)), g);
      }
      expect(geschlechtAusText(null), isNull);
      expect(geschlechtAusText('unsinn'), isNull);
    });

    test('divers und unbekannt fallen auf die neutrale Form', () {
      expect(auswahlwert(Geschlecht.weiblich), 'w');
      expect(auswahlwert(Geschlecht.maennlich), 'm');
      expect(auswahlwert(Geschlecht.divers), 'other');
      expect(auswahlwert(null), 'other');
    });
  });

  group('Umweg – wo die Sprache kein Wort hat', () {
    /// Genau die Kette aus der Anfrage: Schwester, ihr Mann, dessen
    /// Eltern und dessen Bruder, dazu der Neffe.
    ///
    ///   schwagersVater == schwagersMutter
    ///            |            |
    ///        schwager  schwagersBruder
    ///            ||
    ///   ich    schwester
    ///              |
    ///            neffe
    Verwandtschaftsnetz schwippschaft() => Verwandtschaftsnetz([
          kante('ich', 'vater', Verwandtschaft.elternteil),
          kante('schwester', 'vater', Verwandtschaft.elternteil),
          partnerKanteFuer('schwester', 'schwager'),
          kante('neffe', 'schwester', Verwandtschaft.elternteil),
          kante('neffe', 'schwager', Verwandtschaft.elternteil),
          kante('schwager', 'schwagersVater', Verwandtschaft.elternteil),
          kante('schwager', 'schwagersMutter', Verwandtschaft.elternteil),
          kante('schwagersBruder', 'schwagersVater', Verwandtschaft.elternteil),
          kante('schwagersBruder', 'schwagersMutter', Verwandtschaft.elternteil),
          partnerKanteFuer('schwagersVater', 'schwagersMutter'),
        ]);

    test('was ein Wort hat, braucht keinen Umweg', () {
      final netz = schwippschaft();
      // Der Schwager selbst, die Schwester, der Neffe: alles benannt.
      expect(bestimmeGrad(netz, 'ich', 'schwager').art, Gradart.schwager);
      expect(bestimmeGrad(netz, 'ich', 'schwester').art, Gradart.geschwister);
      expect(bestimmeGrad(netz, 'ich', 'neffe').art, Gradart.geschwisterkind);
      // Und deshalb gibt es dort auch nichts zu beschreiben.
      expect(umwegZu(netz, 'ich', 'schwager'), isNull);
    });

    test('die Eltern des Schwagers laufen über den Schwager', () {
      // Vorher stand hier „angeheiratet" – dieselbe Auskunft, die auch
      // der Vetter der zweiten Frau des Onkels bekäme.
      final netz = schwippschaft();
      expect(bestimmeGrad(netz, 'ich', 'schwagersVater').art,
          Gradart.angeheiratet);

      final umweg = umwegZu(netz, 'ich', 'schwagersVater');
      expect(umweg, isNotNull);
      expect(umweg!.ueber, 'schwager');
      expect(umweg.ueberGrad.art, Gradart.schwager);
      // „Vater von …" – ein Schritt nach oben, nicht mehr.
      expect(umweg.schritt.art, Gradart.vorfahre);
      expect(umweg.schritt.aufwaerts, 1);
    });

    test('der Bruder des Schwagers ebenso', () {
      final umweg = umwegZu(schwippschaft(), 'ich', 'schwagersBruder');
      expect(umweg!.ueber, 'schwager');
      expect(umweg.schritt.art, Gradart.geschwister);
    });

    test('bei zwei gleich guten Wegen entscheidet die Reihenfolge', () {
      // schwagersVater ist von „schwager" aus erreichbar UND von
      // „schwagersMutter" – nur ist die selbst kein Wort wert, also
      // bleibt der Schwager. Der Fall, der wirklich zwei Wege hat:
      // schwagersMutter hängt am Schwager und an schwagersVater.
      final netz = schwippschaft();
      final a = umwegZu(netz, 'ich', 'schwagersMutter',
          reihenfolge: (id) => ['schwager', 'schwagersVater'].indexOf(id));
      final b = umwegZu(netz, 'ich', 'schwagersMutter',
          reihenfolge: (id) => ['schwager', 'schwagersVater'].indexOf(id));
      expect(a, b, reason: 'zweimal gefragt, zweimal dieselbe Antwort');
      expect(a!.ueber, 'schwager',
          reason: 'der Schwager hat ein Wort, sein Vater nicht');
    });

    test('mehr als ein Schritt bleibt „angeheiratet"', () {
      // Der Grossvater des Schwagers: Ihn über „Vater des Vaters des
      // Schwagers" zu beschreiben erklärt weniger als gar nichts.
      final netz = Verwandtschaftsnetz([
        kante('ich', 'vater', Verwandtschaft.elternteil),
        kante('schwester', 'vater', Verwandtschaft.elternteil),
        partnerKanteFuer('schwester', 'schwager'),
        kante('schwager', 'schwagersVater', Verwandtschaft.elternteil),
        kante('schwagersVater', 'schwagersOpa', Verwandtschaft.elternteil),
      ]);
      expect(bestimmeGrad(netz, 'ich', 'schwagersOpa').art,
          Gradart.angeheiratet);
      expect(umwegZu(netz, 'ich', 'schwagersOpa'), isNull);
    });

    test('wer gar nicht verbunden ist, bekommt auch keinen Umweg', () {
      final netz = schwippschaft();
      expect(bestimmeGrad(netz, 'ich', 'fremder').art, Gradart.keine);
      expect(umwegZu(netz, 'ich', 'fremder'), isNull);
    });
  });
}
