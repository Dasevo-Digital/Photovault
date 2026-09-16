import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/stammbaum.dart';
import 'package:photo_vault/services/verwandtschaftsgrad.dart';
import 'package:photo_vault/services/verwandte_anlegen.dart';

/// Die Abkürzungen zum Eintragen entfernterer Verwandter.
///
/// Der eigentliche Test ist die Gegenrechnung: Wer über [wegeFuer] einen
/// Neffen einträgt, muss hinterher von [bestimmeGrad] auch als Neffe
/// bezeichnet werden. Ein Eintrag, der sich anders nennt als er heißt,
/// wäre schlimmer als gar keiner.
void main() {
  /// Der Ausgangsbestand:
  ///
  ///   uropa
  ///     └ opa ── oma
  ///         ├ vater ── mutter          onkel (Bruder des Vaters)
  ///         │    ├ ich ── gattin           └ cousine
  ///         │    └ bruder
  ///         └ (weitere über die Tests)
  ///   ich └ tochter ── schwiegersohn
  ///            └ enkelin
  List<Kante> grundbestand() => [
        kante('vater', 'opa', Verwandtschaft.elternteil),
        kante('vater', 'oma', Verwandtschaft.elternteil),
        kante('onkel', 'opa', Verwandtschaft.elternteil),
        kante('onkel', 'oma', Verwandtschaft.elternteil),
        kante('opa', 'uropa', Verwandtschaft.elternteil),
        kante('ich', 'vater', Verwandtschaft.elternteil),
        kante('ich', 'mutter', Verwandtschaft.elternteil),
        kante('bruder', 'vater', Verwandtschaft.elternteil),
        kante('bruder', 'mutter', Verwandtschaft.elternteil),
        kante('cousine', 'onkel', Verwandtschaft.elternteil),
        kante('tochter', 'ich', Verwandtschaft.elternteil),
        kante('enkelin', 'tochter', Verwandtschaft.elternteil),
        partnerKanteFuer('ich', 'gattin'),
        partnerKanteFuer('vater', 'mutter'),
        partnerKanteFuer('tochter', 'schwiegersohn'),
      ];

  Verwandtschaftsnetz netz([List<Kante>? extra]) =>
      Verwandtschaftsnetz([...grundbestand(), ...?extra]);

  /// Trägt [grad] über den ersten passenden Weg ein und gibt das Netz mit
  /// der neuen Person „neu" zurück.
  Verwandtschaftsnetz nachEintrag(Zusatzgrad grad, {String? ueber}) {
    final wege = wegeFuer(netz(), 'ich', grad);
    expect(wege, isNotEmpty, reason: 'für $grad gibt es keinen Weg');
    final weg = ueber == null
        ? wege.first
        : wege.firstWhere((w) => w.bezugsperson == ueber);
    return Verwandtschaftsnetz([
      ...grundbestand(),
      ...kantenFuer(weg, 'neu'),
    ]);
  }

  Grad gradVonNeu(Zusatzgrad art, {String? ueber}) =>
      bestimmeGrad(nachEintrag(art, ueber: ueber), 'ich', 'neu');

  group('Der eingetragene Grad heißt hinterher auch so', () {
    test('Großelternteil', () {
      final g = gradVonNeu(Zusatzgrad.grosselternteil);
      expect(g.art, Gradart.vorfahre);
      expect(g.aufwaerts, 2);
    });

    test('Urgroßelternteil', () {
      final g = gradVonNeu(Zusatzgrad.urgrosselternteil);
      expect(g.art, Gradart.vorfahre);
      expect(g.aufwaerts, 3);
    });

    test('Enkelkind', () {
      final g = gradVonNeu(Zusatzgrad.enkelkind);
      expect(g.art, Gradart.nachkomme);
      expect(g.abwaerts, 2);
    });

    test('Urenkelkind', () {
      final g = gradVonNeu(Zusatzgrad.urenkelkind);
      expect(g.art, Gradart.nachkomme);
      expect(g.abwaerts, 3);
    });

    test('Geschwisterkind – volle Geschwister, nicht halb', () {
      final g = gradVonNeu(Zusatzgrad.geschwisterkind);
      expect(g.art, Gradart.geschwister);
      expect(g.halb, isFalse,
          reason: 'ein Geschwisterkind bekommt ALLE Eltern');
    });

    test('Halbgeschwisterkind – ausdrücklich halb', () {
      final g = gradVonNeu(Zusatzgrad.halbgeschwisterkind);
      expect(g.art, Gradart.geschwister);
      expect(g.halb, isTrue);
    });

    test('Onkel/Tante', () {
      final g = gradVonNeu(Zusatzgrad.onkelTante);
      expect(g.art, Gradart.vorfahrengeschwister);
      expect((g.aufwaerts, g.abwaerts), (2, 1));
    });

    test('Neffe/Nichte', () {
      final g = gradVonNeu(Zusatzgrad.neffeNichte);
      expect(g.art, Gradart.geschwisterkind);
      expect((g.aufwaerts, g.abwaerts), (1, 2));
    });

    test('Cousin/Cousine', () {
      final g = gradVonNeu(Zusatzgrad.cousin);
      expect(g.art, Gradart.cousin);
      expect((g.aufwaerts, g.abwaerts), (2, 2));
    });

    test('Schwiegerelternteil', () {
      expect(gradVonNeu(Zusatzgrad.schwiegerelternteil).art,
          Gradart.schwiegerelternteil);
    });

    test('Schwiegerkind', () {
      expect(gradVonNeu(Zusatzgrad.schwiegerkind).art, Gradart.schwiegerkind);
    });

    test('Schwager über ein Geschwister – der Partner des Bruders', () {
      expect(gradVonNeu(Zusatzgrad.schwager, ueber: 'bruder').art,
          Gradart.schwager);
    });

    test('Stiefelternteil', () {
      expect(gradVonNeu(Zusatzgrad.stiefelternteil).art,
          Gradart.stiefelternteil);
    });

    test('Stiefkind', () {
      // Ein Kind der Gattin, das nicht das eigene ist.
      expect(gradVonNeu(Zusatzgrad.stiefkind).art, Gradart.stiefkind);
    });
  });

  group('Schwager, zweite Lesart', () {
    test('das Geschwister der Gattin zählt auch', () {
      // Die Gattin bekommt Eltern, damit ihr Geschwister eine Stelle hat.
      final mitSchwiegereltern = [
        kante('gattin', 'schwiegervater', Verwandtschaft.elternteil),
      ];
      final wege = wegeFuer(
          Verwandtschaftsnetz([...grundbestand(), ...mitSchwiegereltern]),
          'ich',
          Zusatzgrad.schwager);
      final ueberGattin = wege.where((w) => w.bezugsperson == 'gattin');
      expect(ueberGattin, hasLength(1));
      expect(ueberGattin.single.rolle, Ankerrolle.kind);
      expect(ueberGattin.single.anker, ['schwiegervater']);

      final danach = Verwandtschaftsnetz([
        ...grundbestand(),
        ...mitSchwiegereltern,
        ...kantenFuer(ueberGattin.single, 'neu'),
      ]);
      expect(bestimmeGrad(danach, 'ich', 'neu').art, Gradart.schwager);
    });
  });

  group('Wege und Auswahl', () {
    test('ein Geschwisterkind ist ein einziger Weg über beide Eltern', () {
      final wege = wegeFuer(netz(), 'ich', Zusatzgrad.geschwisterkind);
      expect(wege, hasLength(1), reason: 'hier gibt es nichts zu fragen');
      expect(wege.single.anker.toSet(), {'vater', 'mutter'});
      expect(wege.single.rolle, Ankerrolle.kind);
    });

    test('ein Halbgeschwisterkind ist ein Weg je Elternteil', () {
      final wege = wegeFuer(netz(), 'ich', Zusatzgrad.halbgeschwisterkind);
      expect(wege.map((w) => w.bezugsperson).toSet(), {'vater', 'mutter'});
      for (final w in wege) {
        expect(w.anker, hasLength(1));
      }
    });

    test('der Onkel hängt an den Großeltern, gefragt wird nach dem Elternteil',
        () {
      final wege = wegeFuer(netz(), 'ich', Zusatzgrad.onkelTante);
      // Nur der Vater hat Eltern; die Mutter fällt heraus.
      expect(wege, hasLength(1));
      expect(wege.single.bezugsperson, 'vater');
      expect(wege.single.anker.toSet(), {'opa', 'oma'});
    });

    test('die Reihenfolge folgt der übergebenen Ordnung', () {
      final ordnung = {'mutter': 0, 'vater': 1};
      final wege = wegeFuer(netz(), 'ich', Zusatzgrad.halbgeschwisterkind,
          reihenfolge: (id) => ordnung[id] ?? 99);
      expect(wege.map((w) => w.bezugsperson).toList(), ['mutter', 'vater']);
    });
  });

  group('Fehlende Voraussetzungen', () {
    final leer = Verwandtschaftsnetz(const []);

    test('ohne jede Verwandtschaft gibt es für keinen Grad einen Weg', () {
      for (final grad in Zusatzgrad.values) {
        expect(wegeFuer(leer, 'allein', grad), isEmpty, reason: '$grad');
      }
    });

    test('jeder Grad benennt, was ihm fehlt', () {
      for (final grad in Zusatzgrad.values) {
        expect(fehlendeVoraussetzung(grad), isNotNull, reason: '$grad');
      }
    });

    test('ein Cousin braucht einen Onkel, nicht nur einen Elternteil', () {
      final nurEltern = Verwandtschaftsnetz([
        kante('ich', 'vater', Verwandtschaft.elternteil),
      ]);
      expect(wegeFuer(nurEltern, 'ich', Zusatzgrad.cousin), isEmpty);
      expect(fehlendeVoraussetzung(Zusatzgrad.cousin), Fehlt.onkelTante);
    });

    test('ein Onkel braucht Großeltern, nicht nur Eltern', () {
      final nurEltern = Verwandtschaftsnetz([
        kante('ich', 'vater', Verwandtschaft.elternteil),
      ]);
      expect(wegeFuer(nurEltern, 'ich', Zusatzgrad.onkelTante), isEmpty);
      expect(fehlendeVoraussetzung(Zusatzgrad.onkelTante), Fehlt.grosselternteil);
    });
  });

  group('Die erzeugten Kanten', () {
    test('ein Großelternteil wird Elternteil des Elternteils', () {
      final weg = wegeFuer(netz(), 'ich', Zusatzgrad.grosselternteil)
          .firstWhere((w) => w.bezugsperson == 'mutter');
      final kanten = kantenFuer(weg, 'neu');
      expect(kanten, hasLength(1));
      expect(kanten.single.personId, 'mutter');
      expect(kanten.single.andereId, 'neu');
      expect(kanten.single.art, Verwandtschaft.elternteil);
    });

    test('ein Schwiegerkind wird Partner des Kindes, in fester Ordnung', () {
      final weg = wegeFuer(netz(), 'ich', Zusatzgrad.schwiegerkind).single;
      final kanten = kantenFuer(weg, 'neu');
      expect(kanten.single.art, Verwandtschaft.partner);
      // Partnerkanten stehen immer mit der kleineren Kennung zuerst.
      expect(kanten.single, partnerKanteFuer('neu', 'tochter'));
    });

    test('ein Geschwisterkind erzeugt eine Kante je Elternteil', () {
      final weg = wegeFuer(netz(), 'ich', Zusatzgrad.geschwisterkind).single;
      final kanten = kantenFuer(weg, 'neu');
      expect(kanten, hasLength(2));
      expect(kanten.map((k) => k.andereId).toSet(), {'vater', 'mutter'});
      expect(kanten.every((k) => k.personId == 'neu'), isTrue);
    });
  });
}
