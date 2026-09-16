import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/familienstatistik.dart';
import 'package:photo_vault/services/lebenslauf.dart';
import 'package:photo_vault/services/stammbaum.dart';

/// Die Familienstatistik.
///
/// Der Grund, warum diese Rechnungen reine Funktionen sind: **Eine
/// falsche Statistik sieht richtig aus.** Am fertigen Balkendiagramm ist
/// nicht zu erkennen, ob ein Durchschnitt die Lebenden als „0 Jahre"
/// mitgezählt hat – die Zahl ist plausibel, nur eben falsch.
void main() {
  StatPerson p(String id, String name, {DateTime? geb, DateTime? tod}) =>
      (id: id, name: name, geschlecht: null, geburt: geb, tod: tod);

  StatEreignis hochzeit(String personId, DateTime? datum) =>
      (personId: personId, art: Ereignisart.hochzeit, datum: datum);

  group('Alter in Jahren', () {
    test('rechnet nach dem Geburtstag, nicht nach der Jahreszahl', () {
      // Wer im Dezember 1900 geboren wurde und im Januar 1980 starb,
      // wurde 79 und nicht 80.
      expect(alterInJahren(DateTime(1900, 12, 1), DateTime(1980, 1, 5)), 79);
      expect(alterInJahren(DateTime(1900, 12, 1), DateTime(1980, 12, 1)), 80);
      expect(alterInJahren(DateTime(1900, 12, 2), DateTime(1980, 12, 1)), 79);
    });

    test('ohne eine der beiden Angaben gibt es kein Alter', () {
      expect(alterInJahren(null, DateTime(1980)), isNull);
      expect(alterInJahren(DateTime(1900), null), isNull);
      expect(alterInJahren(null, null), isNull);
    });

    test('ein Tod vor der Geburt liefert null statt eines negativen Werts',
        () {
      // Sonst zöge ein Tippfehler den Durchschnitt nach unten, und
      // niemand fände die Ursache.
      expect(alterInJahren(DateTime(1980), DateTime(1900)), isNull);
    });
  });

  group('Der Durchschnitt', () {
    test('Lebende zaehlen NICHT als null Jahre mit', () {
      // Der Kern der ganzen Datei. Zwei Verstorbene mit 80 und 90, dazu
      // zwei Lebende: Richtig sind 85. Mit den Lebenden als „0 Jahre"
      // kämen 42,5 heraus – eine Zahl, die niemandem auffiele.
      final stat = Altersauswertung.aus([80, 90, null, null]);
      expect(stat.durchschnitt, 85);
      expect(stat.anzahl, 2);
      expect(stat.nichtGezaehlt, 2,
          reason: 'die Zahl der Ausgeschlossenen gehoert neben das Ergebnis');
    });

    test('nennt die Spanne', () {
      final stat = Altersauswertung.aus([80, 90, 71]);
      expect(stat.kleinstes, 71);
      expect(stat.groesstes, 90);
    });

    test('ohne einen einzigen Wert bleibt sie leer', () {
      final stat = Altersauswertung.aus([null, null]);
      expect(stat.istLeer, isTrue);
      expect(stat.durchschnitt, isNull);
      expect(stat.nichtGezaehlt, 2);
    });
  });

  group('Generationen', () {
    final netz = Verwandtschaftsnetz([
      kante('vater', 'opa', Verwandtschaft.elternteil),
      kante('vater', 'oma', Verwandtschaft.elternteil),
      partnerKanteFuer('opa', 'oma'),
      partnerKanteFuer('vater', 'mutter'),
      kante('kind', 'vater', Verwandtschaft.elternteil),
      kante('kind', 'mutter', Verwandtschaft.elternteil),
      kante('opa', 'uropa', Verwandtschaft.adoptivelternteil),
    ]);

    test('Eltern nach oben, Kinder nach unten', () {
      final g = generationen(netz, 'vater');
      expect(g['vater'], 0);
      expect(g['opa'], -1);
      expect(g['kind'], 1);
      expect(g['uropa'], -2,
          reason: 'eine Adoptivkante zaehlt wie jede andere Elternkante');
    });

    test('ein Partner bekommt die Generation seines Partners', () {
      // Übereinkunft, keine Tatsache: Eine angeheiratete Person hat ihre
      // eigene Herkunft. Ohne diesen Schritt fiele bei jedem Paar die
      // Hälfte aus der Auswertung.
      expect(generationen(netz, 'vater')['mutter'], 0);
    });

    test('eine eigene Generation schlaegt die des Partners', () {
      // Zwei Verwandte, die einander geheiratet haben – in
      // Familienbüchern kommt das vor. Die Blutslinie entscheidet.
      final eng = Verwandtschaftsnetz([
        kante('kind', 'vater', Verwandtschaft.elternteil),
        partnerKanteFuer('kind', 'vater'),
      ]);
      expect(generationen(eng, 'vater')['kind'], 1);
    });

    test('wer nicht verbunden ist, bekommt keine Generation', () {
      expect(generationen(netz, 'vater').containsKey('fremd'), isFalse);
    });
  });

  group('Namen', () {
    test('das letzte Wort gilt als Nachname', () {
      // Dieselbe Vermutung wie im GEDCOM-Export – sonst zaehlte die
      // Auswertung anders, als die ausgegebene Datei aussieht.
      expect(namensteile('Anna Maria Meier'),
          (vorname: 'Anna', nachname: 'Meier'));
    });

    test('ein einzelner Name hat keinen Nachnamen', () {
      expect(namensteile('Oma'), (vorname: 'Oma', nachname: null));
    });

    test('haeufigste zuerst, bei Gleichstand alphabetisch', () {
      final h = haeufigkeiten(
          ['Meier', 'Meier', 'Schulz', 'Abel', 'Schulz', null, '']);
      expect(h.map((x) => x.name), ['Meier', 'Schulz', 'Abel']);
      expect(h.first.anzahl, 2);
    });

    test('die Liste wird gekuerzt', () {
      final h = haeufigkeiten(
          [for (var i = 0; i < 20; i++) 'Name$i'],
          hoechstens: 3);
      expect(h, hasLength(3));
    });
  });

  group('Die ganze Auswertung', () {
    final netz = Verwandtschaftsnetz([
      kante('vater', 'opa', Verwandtschaft.elternteil),
      kante('vater', 'oma', Verwandtschaft.elternteil),
      partnerKanteFuer('opa', 'oma'),
      partnerKanteFuer('vater', 'mutter'),
      kante('kind', 'vater', Verwandtschaft.elternteil),
      kante('kind', 'mutter', Verwandtschaft.elternteil),
      kante('schwester', 'vater', Verwandtschaft.elternteil),
      kante('schwester', 'mutter', Verwandtschaft.elternteil),
    ]);

    final personen = [
      p('opa', 'Hans Meier', geb: DateTime(1901, 5, 2), tod: DateTime(1981, 6, 3)),
      p('oma', 'Grete Meier', geb: DateTime(1903, 2, 1), tod: DateTime(1993, 1, 9)),
      p('vater', 'Karl Meier', geb: DateTime(1931, 4, 4)),
      p('mutter', 'Eva Schulz', geb: DateTime(1934, 8, 8)),
      p('kind', 'Lena Meier', geb: DateTime(1962, 3, 3)),
      p('schwester', 'Nina Meier', geb: DateTime(1965, 7, 7)),
    ];

    Familienstatistik rechne({List<StatEreignis> ereignisse = const []}) =>
        familienstatistik(
          personen: personen,
          netz: netz,
          fokus: 'kind',
          ereignisse: ereignisse,
        );

    test('das Lebensalter zaehlt nur die Verstorbenen', () {
      // Vier der sechs leben (oder haben kein Sterbedatum). Mit ihnen als
      // „0 Jahre" käme ein Durchschnitt von 28,3 heraus statt 85.
      final stat = rechne().sterbealter;
      expect(stat.anzahl, 2);
      expect(stat.nichtGezaehlt, 4);
      expect(stat.durchschnitt, closeTo(85, 0.6));
    });

    test('die aelteste Generation ist die erste', () {
      // Absolut gezaehlt und nicht als „zwei ueber dir": Die Auswertung
      // soll dieselbe bleiben, wenn jemand anders in der Mitte steht.
      final vonKind = rechne().alterJeGeneration;
      expect(vonKind.keys, [1], reason: 'nur die Grosseltern sind gestorben');
      final vonOpa = familienstatistik(
        personen: personen,
        netz: netz,
        fokus: 'opa',
        ereignisse: const [],
      ).alterJeGeneration;
      expect(vonOpa.keys, vonKind.keys);
      expect(vonOpa[1]!.durchschnitt, vonKind[1]!.durchschnitt);
    });

    test('eine Generation ohne einen einzigen Wert steht nicht im Bild', () {
      // Sonst stünde eine leere Spalte da, die aussähe wie „Alter null".
      expect(rechne().alterJeGeneration.containsKey(2), isFalse);
    });

    test('das Heiratsalter nimmt die erste Ehe', () {
      // Ein Wiederverheirateter mit sechzig verschöbe den Wert, ohne dass
      // es jemand am Ergebnis sähe.
      final stat = rechne(ereignisse: [
        hochzeit('vater', DateTime(1958, 6, 21)),
        hochzeit('vater', DateTime(1991, 6, 21)),
        hochzeit('mutter', DateTime(1958, 6, 21)),
      ]).heiratsalter;
      expect(stat.anzahl, 2);
      expect(stat.kleinstes, 23, reason: 'Eva Schulz, geboren 1934');
      expect(stat.groesstes, 27, reason: 'Karl Meier, geboren 1931');
    });

    test('eine Hochzeit ohne Datum zaehlt nicht', () {
      expect(rechne(ereignisse: [hochzeit('opa', null)]).heiratsalter.istLeer,
          isTrue);
    });

    test('die Kinderzahl kommt als Verteilung, nicht als Durchschnitt', () {
      // Ein Durchschnitt müsste entscheiden, wen er mitzählt – ein Kind
      // hat noch keine Kinder, und die Grenze zu ziehen wäre willkürlich.
      // Die Verteilung sagt beides zugleich.
      //
      // Opa und Oma haben je ein Kind (Vater), Vater und Mutter je zwei,
      // Lena und Nina keines.
      expect(rechne().kinderverteilung, {0: 2, 1: 2, 2: 2});
    });

    test('Kinder ausserhalb der Menge zaehlen nicht mit', () {
      // Sonst stünde in der Familienauswertung eine Kinderzahl, zu der
      // sich im Bild niemand finden lässt.
      final stat = familienstatistik(
        personen: [personen.first],
        netz: netz,
        fokus: 'opa',
        ereignisse: const [],
      );
      expect(stat.kinderverteilung, {0: 1});
    });

    test('zaehlt Vor- und Nachnamen', () {
      final stat = rechne();
      expect(stat.nachnamen.first, (name: 'Meier', anzahl: 5));
      expect(stat.vornamen.map((x) => x.name),
          containsAll(['Eva', 'Grete', 'Hans', 'Karl', 'Lena', 'Nina']));
    });

    test('ohne Personen ist die Auswertung leer', () {
      final stat = familienstatistik(
        personen: const [],
        netz: netz,
        fokus: 'kind',
        ereignisse: const [],
      );
      expect(stat.istLeer, isTrue);
    });
  });
}
