import 'package:flutter_test/flutter_test.dart';
import 'package:kern/services/stammbaum.dart';

/// Das Geflecht: wer mit wem lebt, und wer von wem abstammt.
///
/// Der Unterschied zum [ausschnittUm] daneben ist genau **eine** Frage,
/// und es ist die, wegen der es das Geflecht gibt: Zu welcher Schwester
/// gehört dieser Schwager? Eine Reihe nach Rolle kann das nicht sagen.
void main() {
  /// Die Kette aus der Anfrage, dazu ein zweites Geschwister ohne
  /// Anhang – damit sich zeigt, dass die Zuordnung nicht rät.
  ///
  ///   opa == oma      schwagersVater == schwagersMutter
  ///        |                    |            |
  ///   vater == mutter       schwager   schwagersBruder
  ///        |                   ||
  ///   ich, anna, bruno      anna
  ///                           |
  ///                         neffe
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

  /// Alle Personen, in einer festen Reihenfolge – wie im Baum.
  const alle = [
    'opa',
    'oma',
    'schwagersVater',
    'schwagersMutter',
    'vater',
    'mutter',
    'ich',
    'anna',
    'bruno',
    'schwager',
    'schwagersBruder',
    'neffe',
  ];

  Stammbaumgeflecht geflecht([String fokus = 'ich']) =>
      geflechtUm(sippe(), fokus, alle);

  group('Haushalte', () {
    test('der Schwager wohnt bei seiner Frau, nicht irgendwo daneben', () {
      // DIE Frage. Vorher stand er in einer eigenen Reihe „Schwäger", und
      // welche der Schwestern ihn geheiratet hatte, war nicht zu sehen.
      final haus = geflecht().haushaltVon('schwager');
      expect(haus, isNotNull);
      expect(haus!.anker, 'anna');
      expect(haus.personen, containsAll(['anna', 'schwager']));
    });

    test('das Geschwister ohne Partner wohnt für sich', () {
      final haus = geflecht().haushaltVon('bruno');
      expect(haus!.personen, ['bruno']);
    });

    test('Vater und Mutter sind ein Haushalt, nicht zwei', () {
      final g = geflecht();
      expect(g.haushaltVon('vater'), same(g.haushaltVon('mutter')));
      expect(
        g.imBand(-1).where((h) => h.personen.contains('vater')),
        hasLength(1),
      );
    });

    test('niemand wohnt zweimal', () {
      // Eine Person kann auf mehreren Wegen erreichbar sein. Zwei
      // Schilder für einen Menschen sind kein Baum, sondern ein Fehler.
      final personen = <String>[];
      for (final h in geflecht().haushalte) {
        personen.addAll(h.personen);
      }
      expect(personen.length, personen.toSet().length);
    });
  });

  group('die Elternkante hängt an der Person', () {
    test('die Schwester stammt von meinen Eltern, ihr Mann von seinen', () {
      // Der ganze Sinn: Beide wohnen im selben Haushalt und haben
      // trotzdem verschiedene Eltern. Am Haushalt festgemacht wäre eine
      // der beiden Linien gelogen.
      final g = geflecht();
      expect(g.elternhaeuserVon['anna'], [g.haushaltVon('vater')!.id]);
      expect(g.elternhaeuserVon['schwager'], [
        g.haushaltVon('schwagersVater')!.id,
      ]);
      expect(g.elternhaeuserVon['anna'], isNot(g.elternhaeuserVon['schwager']));
    });

    test('der Neffe hängt am Haushalt seiner Eltern', () {
      final g = geflecht();
      expect(g.elternhaeuserVon['neffe'], [g.haushaltVon('anna')!.id]);
    });

    test('wessen Eltern nicht im Bild stehen, bekommt keine Kante', () {
      // Ein Ast ins Leere wäre eine Behauptung über etwas, das man nicht
      // sieht. Dafür gibt es das Mehrzeichen.
      final g = geflecht();
      expect(g.elternhaeuserVon.containsKey('opa'), isFalse);
      expect(
        g.weitereOben['opa'],
        isFalse,
        reason: 'Opa hat keine Eltern im Netz',
      );
    });
  });

  group('Bänder', () {
    test('jede Generation steht auf ihrer Höhe', () {
      final g = geflecht();
      int bandVon(String person) => g.band[g.haushaltVon(person)!.id]!;
      expect(bandVon('ich'), 0);
      expect(bandVon('anna'), 0);
      expect(bandVon('schwager'), 0, reason: 'er wohnt bei Anna');
      expect(bandVon('schwagersBruder'), 0);
      expect(bandVon('vater'), -1);
      expect(bandVon('schwagersVater'), -1, reason: 'Eltern des Schwagers');
      expect(bandVon('opa'), -2);
      expect(bandVon('neffe'), 1);
    });

    test('die Eltern des Schwagers stehen über ihm, nicht über mir', () {
      // Sie sind eine Generation über der Mitte – aber ihr Ast führt zum
      // Schwager, nicht zu mir.
      final g = geflecht();
      expect(g.band[g.haushaltVon('schwagersVater')!.id], -1);
      expect(g.elternhaeuserVon['schwager'], [
        g.haushaltVon('schwagersVater')!.id,
      ]);
      expect(g.elternhaeuserVon['ich'], [g.haushaltVon('vater')!.id]);
    });
  });

  group('getrennt lebende Eltern', () {
    /// Der gemeldete Fall: Vater und Mutter sind **keine** Partner. Bis
    /// dahin führte das Geflecht je Person genau ein Elternhaus und
    /// brach nach dem ersten ab – der Vater stand ohne jeden Ast im
    /// Bild, als gehörte er nicht dazu.
    Verwandtschaftsnetz getrennt() => Verwandtschaftsnetz([
      kante('ich', 'vater', Verwandtschaft.elternteil),
      kante('ich', 'mutter', Verwandtschaft.elternteil),
      kante('schwester', 'vater', Verwandtschaft.elternteil),
      kante('schwester', 'mutter', Verwandtschaft.elternteil),
    ]);

    // Die Mutter steht vorn - genau die Reihenfolge, in der der Vater
    // vorher unter den Tisch fiel.
    Stammbaumgeflecht g() => geflechtUm(getrennt(), 'ich', const [
      'mutter',
      'vater',
      'ich',
      'schwester',
    ]);

    test('beide Eltern haben ein eigenes Haus', () {
      final geflecht = g();
      expect(geflecht.haushaltVon('vater')!.personen, ['vater']);
      expect(geflecht.haushaltVon('mutter')!.personen, ['mutter']);
    });

    test('und beide bekommen einen Ast', () {
      final geflecht = g();
      expect(
        geflecht.elternhaeuserVon['ich'],
        containsAll([
          geflecht.haushaltVon('vater')!.id,
          geflecht.haushaltVon('mutter')!.id,
        ]),
      );
      expect(geflecht.elternhaeuserVon['ich'], hasLength(2));
    });

    test('zusammen lebende Eltern bleiben ein einziger Ast', () {
      // Die Gegenprobe: Sonst hinge an jedem Kind eine doppelte Linie
      // zum selben Haushalt, und der Ast waere doppelt so dick gemalt.
      final geflecht = geflechtUm(sippe(), 'ich', alle);
      expect(geflecht.elternhaeuserVon['ich'], hasLength(1));
    });
  });

  group('die Grenze', () {
    test('ein grosses Band wird gedeckelt und sagt, wie viel fehlt', () {
      // Zwanzig Geschwister passen auf kein Blatt. Stillschweigend
      // wegzulassen wäre das Schlimmste von beidem.
      final kanten = <Kante>[kante('ich', 'vater', Verwandtschaft.elternteil)];
      final alleIds = <String>['vater', 'ich'];
      for (var i = 0; i < 20; i++) {
        kanten.add(kante('g$i', 'vater', Verwandtschaft.elternteil));
        alleIds.add('g$i');
      }
      final g = geflechtUm(Verwandtschaftsnetz(kanten), 'ich', alleIds);

      expect(g.imBand(0).length, maxHaushalteJeBand);
      expect(g.verschwiegen, greaterThan(0));
      // 1 Mitte + 20 Geschwister = 21 Haushalte im Band 0, davon passen
      // maxHaushalteJeBand hinein.
      expect(g.verschwiegen, 21 - maxHaushalteJeBand);
    });

    test('ohne Gedränge wird nichts verschwiegen', () {
      expect(geflecht().verschwiegen, 0);
    });
  });

  group('Auswahl für den Lebensbaum', () {
    test('die Vorgabe ist der ganze Baum, samt Familie des Schwagers', () {
      expect(geflecht().personen, containsAll(['schwagersBruder', 'neffe']));
    });

    test('die direkte Linie lässt Geschwister und Schwägerschaft weg', () {
      final g = geflechtUm(sippe(), 'ich', alle, kreis: Verwandtenkreis.linie);
      expect(g.personen, {'opa', 'oma', 'vater', 'mutter', 'ich'});
      expect(g.verschwiegen, 0, reason: 'nicht verschwiegen, nicht verlangt');
    });

    test('mit Geschwistern: samt Partnern und Kindern, ohne deren '
        'Herkunftsfamilien', () {
      final g = geflechtUm(
        sippe(),
        'ich',
        alle,
        kreis: Verwandtenkreis.geschwister,
      );
      expect(g.personen, containsAll(['anna', 'schwager', 'neffe', 'bruno']));
      expect(
        g.personen.intersection({
          'schwagersVater',
          'schwagersMutter',
          'schwagersBruder',
        }),
        isEmpty,
      );
    });

    test('die Generationen begrenzen nach oben und nach unten', () {
      final g = geflechtUm(sippe(), 'ich', alle, oben: 1, unten: 0);
      expect(g.personen, containsAll(['vater', 'mutter', 'anna', 'bruno']));
      expect(g.personen, isNot(contains('opa')));
      expect(g.personen, isNot(contains('neffe')));
      expect(g.band.values.reduce((a, b) => a < b ? a : b), -1);
      expect(g.band.values.reduce((a, b) => a > b ? a : b), 0);
      // Wer oben abgeschnitten ist, trägt das Mehrzeichen: Da geht es
      // weiter, nur nicht in diesem Bild.
      expect(g.weitereOben['vater'], isTrue);
    });
  });

  test('zweimal gefragt, zweimal dasselbe', () {
    // Die Reihenfolge ist übergeben, also darf nichts umherspringen.
    final a = geflecht();
    final b = geflecht();
    expect(a.haushalte, b.haushalte);
    expect(a.band, b.band);
    expect(a.elternhaeuserVon, b.elternhaeuserVon);
  });

  group('nach unten so weit wie nach oben', () {
    /// Der gemeldete Fehler: Der Baum zeigte Urgrosseltern, aber keine
    /// Enkel. Drei Generationen hinauf, eine hinab - und die App sagte
    /// mit ihrem Mehrzeichen sogar selbst, dass da unten noch etwas ist.
    Verwandtschaftsnetz vierGenerationen() => Verwandtschaftsnetz([
      kante('vater', 'opa', Verwandtschaft.elternteil),
      kante('ich', 'vater', Verwandtschaft.elternteil),
      kante('anna', 'vater', Verwandtschaft.elternteil),
      kante('kind', 'ich', Verwandtschaft.elternteil),
      kante('enkel', 'kind', Verwandtschaft.elternteil),
      kante('urenkel', 'enkel', Verwandtschaft.elternteil),
      kante('neffe', 'anna', Verwandtschaft.elternteil),
      kante('grossneffe', 'neffe', Verwandtschaft.elternteil),
    ]);
    const ids = [
      'opa',
      'vater',
      'ich',
      'anna',
      'kind',
      'neffe',
      'enkel',
      'grossneffe',
      'urenkel',
    ];

    test('Enkel und Urenkel stehen im Bild', () {
      final g = geflechtUm(vierGenerationen(), 'ich', ids);
      int? bandVon(String p) => g.band[g.haushaltVon(p)?.id];
      expect(bandVon('kind'), 1);
      expect(bandVon('enkel'), 2, reason: 'der gemeldete Fehler');
      expect(bandVon('urenkel'), 3);
    });

    test('auch die Kinder der Neffen', () {
      final g = geflechtUm(vierGenerationen(), 'ich', ids);
      expect(g.band[g.haushaltVon('grossneffe')?.id], 2);
    });

    test('so weit hinab wie hinauf', () {
      // Die Symmetrie ist der Punkt: Ein Baum, der drei Generationen
      // hinauf und eine hinab zeigt, ist keiner.
      final g = geflechtUm(vierGenerationen(), 'ich', ids);
      final baender = g.haushalte.map((h) => g.band[h.id]!);
      expect(
        baender.reduce((a, b) => a < b ? a : b),
        -2,
        reason: 'Opa ist der einzige Vorfahre ausser dem Vater',
      );
      expect(baender.reduce((a, b) => a > b ? a : b), 3);
    });

    test('wer unten alles zeigt, traegt kein Mehrzeichen', () {
      final g = geflechtUm(vierGenerationen(), 'ich', ids);
      expect(
        g.weitereUnten['kind'],
        isFalse,
        reason: 'der Enkel steht jetzt im Bild',
      );
      expect(g.weitereUnten['enkel'], isFalse);
    });
  });

  group('weiter gestellt: Generationen und Seitenlinien (#233)', () {
    ///   ururur
    ///     |
    ///   urur
    ///     |
    ///   urgross ─────────────┐
    ///     |                  |
    ///   opa == oma       grossonkel
    ///     |                  |
    ///   vater == mutter   onkel == tante   vatersCousin
    ///     |                  |                  |
    ///    ich             cousine            cousin2
    ///                        |
    ///                  cousinenKind
    Verwandtschaftsnetz weit() => Verwandtschaftsnetz([
      kante('urur', 'ururur', Verwandtschaft.elternteil),
      kante('urgross', 'urur', Verwandtschaft.elternteil),
      kante('opa', 'urgross', Verwandtschaft.elternteil),
      kante('grossonkel', 'urgross', Verwandtschaft.elternteil),
      partnerKanteFuer('opa', 'oma'),
      kante('vater', 'opa', Verwandtschaft.elternteil),
      kante('vater', 'oma', Verwandtschaft.elternteil),
      kante('onkel', 'opa', Verwandtschaft.elternteil),
      kante('onkel', 'oma', Verwandtschaft.elternteil),
      partnerKanteFuer('onkel', 'tante'),
      partnerKanteFuer('vater', 'mutter'),
      kante('ich', 'vater', Verwandtschaft.elternteil),
      kante('ich', 'mutter', Verwandtschaft.elternteil),
      kante('cousine', 'onkel', Verwandtschaft.elternteil),
      kante('cousine', 'tante', Verwandtschaft.elternteil),
      kante('cousinenKind', 'cousine', Verwandtschaft.elternteil),
      kante('vatersCousin', 'grossonkel', Verwandtschaft.elternteil),
      kante('cousin2', 'vatersCousin', Verwandtschaft.elternteil),
    ]);
    const ids = [
      'ururur',
      'urur',
      'urgross',
      'opa',
      'oma',
      'grossonkel',
      'vater',
      'mutter',
      'onkel',
      'tante',
      'vatersCousin',
      'ich',
      'cousine',
      'cousin2',
      'cousinenKind',
    ];
    int? bandVon(Stammbaumgeflecht g, String p) => g.band[g.haushaltVon(p)?.id];

    test('die Vorgabe bleibt: Onkel ja, Cousine nein', () {
      final g = geflechtUm(weit(), 'ich', ids);
      expect(g.personen, containsAll(['onkel', 'tante', 'urgross']));
      expect(
        g.personen.intersection({'cousine', 'grossonkel', 'cousin2', 'urur'}),
        isEmpty,
      );
      expect(g.weitereUnten['onkel'], isTrue, reason: 'da wäre die Cousine');
    });

    test('mit Cousins: die Cousine unter ihren Eltern, ihr Kind darunter', () {
      final g = geflechtUm(weit(), 'ich', ids, kreis: Verwandtenkreis.cousins);
      expect(bandVon(g, 'cousine'), 0);
      expect(bandVon(g, 'cousinenKind'), 1);
      expect(g.elternhaeuserVon['cousine'], [g.haushaltVon('onkel')!.id]);
      expect(g.weitereUnten['onkel'], isFalse);
      // Die zweite Stufe kommt erst mit der eigenen Wahl.
      expect(g.personen, isNot(contains('grossonkel')));
      expect(g.personen, isNot(contains('cousin2')));
    });

    test('mit Cousins zweiten Grades: Grossonkel, sein Kind und Enkel', () {
      final g = geflechtUm(
        weit(),
        'ich',
        ids,
        kreis: Verwandtenkreis.cousinsZweitenGrades,
      );
      expect(bandVon(g, 'grossonkel'), -2);
      expect(bandVon(g, 'vatersCousin'), -1);
      expect(bandVon(g, 'cousin2'), 0);
      expect(g.elternhaeuserVon['grossonkel'], [g.haushaltVon('urgross')!.id]);
      expect(bandVon(g, 'cousine'), 0, reason: 'jede Stufe enthält die vorige');
    });

    test('ohne die Grosseltern hängt keine Seitenlinie in der Luft', () {
      final g = geflechtUm(
        weit(),
        'ich',
        ids,
        oben: 1,
        kreis: Verwandtenkreis.cousinsZweitenGrades,
      );
      expect(
        g.personen.intersection({'grossonkel', 'vatersCousin', 'cousin2'}),
        isEmpty,
      );
      // Onkel und Cousine stehen dagegen auf Bändern, die im Bild sind.
      expect(g.personen, containsAll(['onkel', 'cousine']));
    });

    test('fünf Generationen hinauf', () {
      final drei = geflechtUm(weit(), 'ich', ids);
      expect(drei.personen, isNot(contains('urur')));
      expect(drei.weitereOben['urgross'], isTrue);

      final fuenf = geflechtUm(weit(), 'ich', ids, oben: 5);
      expect(bandVon(fuenf, 'urur'), -4);
      expect(bandVon(fuenf, 'ururur'), -5);
      expect(fuenf.weitereOben['urgross'], isFalse);
    });

    test('wer mehr verlangt, bekommt mehr Platz je Band', () {
      final kanten = <Kante>[
        kante('ich', 'vater', Verwandtschaft.elternteil),
        kante('vater', 'opa', Verwandtschaft.elternteil),
        kante('onkel', 'opa', Verwandtschaft.elternteil),
      ];
      final alleIds = <String>['opa', 'vater', 'onkel', 'ich'];
      for (var i = 0; i < 20; i++) {
        kanten.add(kante('c$i', 'onkel', Verwandtschaft.elternteil));
        alleIds.add('c$i');
      }
      final g = geflechtUm(
        Verwandtschaftsnetz(kanten),
        'ich',
        alleIds,
        kreis: Verwandtenkreis.cousins,
      );
      expect(g.imBand(0).length, 21, reason: 'ich und zwanzig Cousins');
      expect(g.verschwiegen, 0);

      expect(
        haushalteJeBand(
          oben: geflechtGenerationen,
          unten: geflechtGenerationen,
          kreis: Verwandtenkreis.alle,
        ),
        maxHaushalteJeBand,
        reason: 'die Vorgabe bleibt, wie sie war',
      );
      expect(
        haushalteJeBand(oben: 4, unten: 0, kreis: Verwandtenkreis.linie),
        maxHaushalteJeBandWeit,
      );
    });
  });
}
