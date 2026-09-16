import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/sanduhr.dart';
import 'package:photo_vault/services/stammbaum.dart';

/// Die Anordnung der Sanduhr.
///
/// Genau hier lag die Beschränkung, die den Baum bisher auf eine Reihe
/// festnagelte: Mehrere Generationen in flachen Reihen erzeugen
/// mehrdeutige Linien. Geprüft wird deshalb nicht, ob es hübsch aussieht,
/// sondern ob jeder Vorfahr seinen eigenen Platz über seinem Kind hat und
/// sich keine zwei Kästen überlappen.
void main() {
  seitenlinienTests();

  ///        opaV  omaV   opaM  omaM
  ///            vater  mutter
  ///                ich
  ///          kind1      kind2
  ///                   enkel
  Verwandtschaftsnetz sippe() => Verwandtschaftsnetz([
        kante('ich', 'vater', Verwandtschaft.elternteil),
        kante('ich', 'mutter', Verwandtschaft.elternteil),
        kante('vater', 'opaV', Verwandtschaft.elternteil),
        kante('vater', 'omaV', Verwandtschaft.elternteil),
        kante('mutter', 'opaM', Verwandtschaft.elternteil),
        kante('mutter', 'omaM', Verwandtschaft.elternteil),
        kante('kind1', 'ich', Verwandtschaft.elternteil),
        kante('kind2', 'ich', Verwandtschaft.elternteil),
        kante('enkel', 'kind2', Verwandtschaft.elternteil),
      ]);

  final reihenfolge = [
    'opaV',
    'omaV',
    'opaM',
    'omaM',
    'vater',
    'mutter',
    'ich',
    'kind1',
    'kind2',
    'enkel',
    'gattin',
  ];
  int ordnung(String id) => reihenfolge.indexOf(id);

  Sanduhr bau([Verwandtschaftsnetz? netz]) =>
      ordneSanduhr(netz ?? sippe(), 'ich', ordnung);

  Map<String, Sanduhrknoten> nachId(Sanduhr s) =>
      {for (final k in s.knoten) k.personId: k};

  group('Reihen', () {
    test('die gewählte Person sitzt in der Taille', () {
      expect(nachId(bau())['ich']!.reihe, 0);
    });

    test('Vorfahren nach oben, Nachkommen nach unten', () {
      final k = nachId(bau());
      expect(k['vater']!.reihe, -1);
      expect(k['opaV']!.reihe, -2);
      expect(k['kind1']!.reihe, 1);
      expect(k['enkel']!.reihe, 2);
    });

    test('hält die Tiefengrenzen ein', () {
      final tief = Verwandtschaftsnetz([
        for (var i = 1; i < 8; i++)
          kante('p${i - 1}', 'p$i', Verwandtschaft.elternteil),
        for (var i = 1; i < 8; i++)
          kante('k$i', i == 1 ? 'p0' : 'k${i - 1}', Verwandtschaft.elternteil),
      ]);
      final s = ordneSanduhr(tief, 'p0', (id) => 0, oben: 2, unten: 2);
      expect(s.obersteReihe, -2);
      expect(s.untersteReihe, 2);
    });
  });

  group('Spalten', () {
    test('kein Kasten überlappt einen anderen', () {
      // Die eigentliche Zusicherung: In einer Reihe muss jeder Platz für
      // sich stehen, sonst wäre nicht erkennbar, wessen Linie wohin geht.
      final s = bau();
      final proReihe = <int, List<double>>{};
      for (final k in s.knoten) {
        proReihe.putIfAbsent(k.reihe, () => []).add(k.spalte);
      }
      for (final e in proReihe.entries) {
        final spalten = e.value..sort();
        for (var i = 1; i < spalten.length; i++) {
          expect(spalten[i] - spalten[i - 1], greaterThanOrEqualTo(1.0),
              reason: 'Reihe ${e.key}: ${spalten[i - 1]} und ${spalten[i]}');
        }
      }
    });

    test('jeder Vorfahr steht über seinem Kind, nicht irgendwo in der Reihe',
        () {
      // Der Kern der Sache. Die Großeltern väterlicherseits müssen den
      // Vater einrahmen, nicht die Mutter.
      final k = nachId(bau());
      final vater = k['vater']!.spalte;
      expect(k['opaV']!.spalte, lessThan(vater));
      expect(k['omaV']!.spalte, greaterThan(vater));
      final mutter = k['mutter']!.spalte;
      expect(k['opaM']!.spalte, lessThan(mutter));
      expect(k['omaM']!.spalte, greaterThan(mutter));
      // Und die beiden Paare dürfen sich nicht kreuzen.
      expect(k['omaV']!.spalte, lessThan(k['opaM']!.spalte));
    });

    test('ein Elternteil sitzt mittig über seinen Kindern', () {
      final k = nachId(bau());
      final mitte = (k['kind1']!.spalte + k['kind2']!.spalte) / 2;
      expect(k['ich']!.spalte, closeTo(mitte, 1e-9));
    });

    test('ein Ast ohne Geschwister bleibt senkrecht', () {
      final k = nachId(bau());
      expect(k['enkel']!.spalte, closeTo(k['kind2']!.spalte, 1e-9));
    });
  });

  group('Kanten', () {
    test('jede Kante verbindet zwei vorhandene Knoten', () {
      final s = bau();
      final ids = {for (final k in s.knoten) k.personId};
      for (final kante in s.kanten) {
        expect(ids, contains(kante.vonId));
        expect(ids, contains(kante.zuId));
      }
    });

    test('merkt sich, wie eine Elternschaft zustande kam', () {
      final netz = Verwandtschaftsnetz([
        kante('ich', 'adoptivvater', Verwandtschaft.adoptivelternteil),
      ]);
      final s = ordneSanduhr(netz, 'ich', ordnung);
      expect(s.kanten.single.art, Verwandtschaft.adoptivelternteil);
    });

    test('Partner stehen daneben, nicht in einer Generation', () {
      final netz = Verwandtschaftsnetz([
        partnerKanteFuer('ich', 'gattin'),
        kante('kind1', 'ich', Verwandtschaft.elternteil),
      ]);
      final s = ordneSanduhr(netz, 'ich', ordnung);
      final gattin = nachId(s)['gattin']!;
      expect(gattin.reihe, 0);
      expect(gattin.istPartner, isTrue);
      expect(s.kanten.any((k) => k.art == Verwandtschaft.partner), isTrue);
    });
  });

  group('Grenzfälle', () {
    test('eine Person ohne Verwandtschaft ergibt einen Knoten', () {
      final s = ordneSanduhr(Verwandtschaftsnetz([]), 'allein', ordnung);
      expect(s.knoten, hasLength(1));
      expect(s.kanten, isEmpty);
    });

    test('ein Kreis im Bestand bringt die Anordnung nicht zum Stehen', () {
      final netz = Verwandtschaftsnetz([
        kante('a', 'b', Verwandtschaft.elternteil),
        kante('b', 'a', Verwandtschaft.elternteil),
      ]);
      final s = ordneSanduhr(netz, 'a', (id) => 0);
      expect(s.knoten, isNotEmpty);
    });

    test('niemand steht zweimal im Bild', () {
      // Bei verschlungenen Familien kann dieselbe Person auf mehreren
      // Wegen erreichbar sein – zweimal gezeichnet wäre sie zweimal
      // anzutippen und einmal falsch verbunden.
      final s = bau();
      final ids = s.knoten.map((k) => k.personId).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });
  });
}

/// Die Seitenlinie: Geschwister neben der Person, ihre Kinder darunter.
///
/// Der Anlass war eine Rückmeldung: Ein neu eingetragener Neffe war in
/// dieser Ansicht nirgends zu sehen. Er hängt an keiner Kante, die von der
/// gewählten Person ausgeht – die Sanduhr zeigte damit ausgerechnet die
/// Verwandten nicht, die sich neu eintragen lassen.
void seitenlinienTests() {
  /// Der gemeldete Bestand, auf das Wesentliche verkürzt:
  ///
  ///   anton ── berta
  ///     ├ caesar ── emma        dora ── felix
  ///     │  └ gustav              └ heidi
  Verwandtschaftsnetz bestand() => Verwandtschaftsnetz([
        kante('caesar', 'anton', Verwandtschaft.elternteil),
        kante('caesar', 'berta', Verwandtschaft.elternteil),
        kante('dora', 'anton', Verwandtschaft.elternteil),
        kante('dora', 'berta', Verwandtschaft.elternteil),
        kante('gustav', 'caesar', Verwandtschaft.elternteil),
        kante('heidi', 'dora', Verwandtschaft.elternteil),
        kante('heidi', 'felix', Verwandtschaft.elternteil),
        partnerKanteFuer('emma', 'caesar'),
        partnerKanteFuer('felix', 'dora'),
      ]);

  const ordnung = {
    'anton': 0,
    'berta': 1,
    'caesar': 2,
    'dora': 3,
    'emma': 4,
    'felix': 5,
    'gustav': 6,
    'heidi': 7,
  };
  int rang(String id) => ordnung[id] ?? 99;

  Sanduhr mitSeite({bool an = true}) =>
      ordneSanduhr(bestand(), 'caesar', rang, seitenlinien: an);

  group('Seitenlinie', () {
    test('das Geschwister steht in derselben Reihe wie die Person', () {
      final s = mitSeite();
      final dora = s.knoten.firstWhere((k) => k.personId == 'dora');
      expect(dora.reihe, 0);
      expect(dora.istPartner, isFalse);
    });

    test('der Neffe steht eine Reihe darunter – der eigentliche Anlass', () {
      final s = mitSeite();
      final heidi = s.knoten.firstWhere((k) => k.personId == 'heidi');
      expect(heidi.reihe, 1);
    });

    test('der Schwager kommt als Partner des Geschwisters mit', () {
      final s = mitSeite();
      final felix = s.knoten.firstWhere((k) => k.personId == 'felix');
      expect(felix.reihe, 0);
      expect(felix.istPartner, isTrue);
    });

    test('ohne Seitenlinie bleibt es bei der eigenen Linie', () {
      final s = mitSeite(an: false);
      final drin = s.knoten.map((k) => k.personId).toSet();
      expect(drin, equals({'caesar', 'emma', 'gustav', 'anton', 'berta'}));
      expect(drin, isNot(contains('dora')));
      expect(drin, isNot(contains('heidi')));
    });

    test('das Geschwister hängt an denselben Eltern, mit eigenen Kanten', () {
      final s = mitSeite();
      final vonPersonC =
          s.kanten.where((k) => k.vonId == 'dora').map((k) => k.zuId).toSet();
      expect(vonPersonC, containsAll({'anton', 'berta'}),
          reason: 'ohne diese Kanten schwebte das Geschwister ohne Anschluss');
    });

    test('in keiner Reihe überlappen sich zwei Kästen', () {
      final s = mitSeite();
      for (var r = s.obersteReihe; r <= s.untersteReihe; r++) {
        final spalten = s.knoten
            .where((k) => k.reihe == r)
            .map((k) => k.spalte)
            .toList()
          ..sort();
        for (var i = 1; i < spalten.length; i++) {
          expect(spalten[i] - spalten[i - 1], greaterThanOrEqualTo(1.0),
              reason: 'Reihe $r: ${spalten[i - 1]} und ${spalten[i]}');
        }
      }
    });

    test('die Wurzel bleibt die Achse – die Eltern stehen über ihr', () {
      final s = mitSeite();
      final caesar = s.knoten.firstWhere((k) => k.personId == 'caesar');
      final anton = s.knoten.firstWhere((k) => k.personId == 'anton');
      final berta = s.knoten.firstWhere((k) => k.personId == 'berta');
      expect((anton.spalte + berta.spalte) / 2, closeTo(caesar.spalte, 0.001),
          reason: 'die Eltern rahmen die gewählte Person, nicht die Gruppe');
    });

    test('ein Halbgeschwister bekommt nur die Kante zum gemeinsamen Elternteil',
        () {
      final netz = Verwandtschaftsnetz([
        kante('caesar', 'anton', Verwandtschaft.elternteil),
        kante('caesar', 'berta', Verwandtschaft.elternteil),
        // Halb: nur anton gemeinsam.
        kante('halb', 'anton', Verwandtschaft.elternteil),
        kante('halb', 'fremd', Verwandtschaft.elternteil),
      ]);
      final s = ordneSanduhr(netz, 'caesar', rang);
      final vonHalb =
          s.kanten.where((k) => k.vonId == 'halb').map((k) => k.zuId).toSet();
      expect(vonHalb, equals({'anton'}),
          reason: 'der zweite Elternteil steht nicht im Bild');
    });

    test('ohne Geschwister ändert der Schalter nichts', () {
      final netz = Verwandtschaftsnetz([
        kante('einzel', 'mutter', Verwandtschaft.elternteil),
      ]);
      final mit = ordneSanduhr(netz, 'einzel', rang);
      final ohne = ordneSanduhr(netz, 'einzel', rang, seitenlinien: false);
      expect(mit.knoten.length, ohne.knoten.length);
    });
  });
}
