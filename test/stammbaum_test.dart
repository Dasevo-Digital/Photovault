import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/stammbaum.dart';
import 'package:photo_vault/services/verwandtschaftsgrad.dart';

/// Die Verwandtschaftslogik.
///
/// Zwei Dinge sind hier leicht falsch und am fertigen Bild nicht zu sehen:
/// ein Kreis (jemand wird zum eigenen Vorfahren, jede Auswertung nach oben
/// läuft dann endlos) und eine Partnerkante, die je nach Eingaberichtung
/// zweimal entsteht und sich nur zur Hälfte wieder entfernen lässt.
void main() {
  /// Eine kleine Familie:
  ///   opa + oma
  ///        |
  ///     vater + mutter
  ///        |
  ///   kind, schwester
  Verwandtschaftsnetz familie() => Verwandtschaftsnetz([
        partnerKanteFuer('opa', 'oma'),
        kante('vater', 'opa', Verwandtschaft.elternteil),
        kante('vater', 'oma', Verwandtschaft.elternteil),
        partnerKanteFuer('vater', 'mutter'),
        kante('kind', 'vater', Verwandtschaft.elternteil),
        kante('kind', 'mutter', Verwandtschaft.elternteil),
        kante('schwester', 'vater', Verwandtschaft.elternteil),
        kante('schwester', 'mutter', Verwandtschaft.elternteil),
      ]);

  group('Verwandtschaftsnetz', () {
    test('liest die Gegenrichtung aus derselben Kante', () {
      final netz = familie();
      expect(netz.eltern('kind'), {'vater', 'mutter'});
      expect(netz.kinder('vater'), {'kind', 'schwester'});
    });

    test('Partnerschaft gilt in beide Richtungen, obwohl nur einmal gespeichert', () {
      final netz = familie();
      expect(netz.partner('vater'), {'mutter'});
      expect(netz.partner('mutter'), {'vater'});
    });

    test('Geschwister sind die weiteren Kinder der eigenen Eltern', () {
      expect(familie().geschwister('kind'), {'schwester'});
      expect(familie().geschwister('vater'), isEmpty);
    });

    test('ein gemeinsamer Elternteil genügt für Geschwister', () {
      final netz = Verwandtschaftsnetz([
        kante('a', 'vater', Verwandtschaft.elternteil),
        kante('b', 'vater', Verwandtschaft.elternteil),
        kante('b', 'zweiteMutter', Verwandtschaft.elternteil),
      ]);
      expect(netz.geschwister('a'), {'b'});
    });

    test('Vorfahren werden über beliebig viele Stufen gefunden', () {
      final netz = familie();
      expect(netz.istVorfahreVon('opa', 'kind'), isTrue);
      expect(netz.istVorfahreVon('kind', 'opa'), isFalse);
      expect(netz.istVorfahreVon('kind', 'kind'), isTrue,
          reason: 'die Person selbst zählt mit');
    });

    test('kommt aus einem bereits vorhandenen Kreis zurück', () {
      // Ein Bestand, der ohne die Prüfung entstanden sein könnte. Ohne das
      // Merken des Besuchten liefe diese Suche endlos.
      final netz = Verwandtschaftsnetz([
        kante('a', 'b', Verwandtschaft.elternteil),
        kante('b', 'a', Verwandtschaft.elternteil),
      ]);
      expect(netz.istVorfahreVon('fremd', 'a'), isFalse);
    });
  });

  group('partnerKanteFuer', () {
    test('ergibt dieselbe Kante, egal in welcher Richtung eingegeben', () {
      expect(partnerKanteFuer('anna', 'bert'), partnerKanteFuer('bert', 'anna'));
    });
  });

  group('pruefeBeziehung', () {
    test('lässt eine neue Verwandtschaft zu', () {
      expect(pruefeBeziehung(familie(), 'kind', 'fremd', Verwandtschaft.elternteil), isNull);
    });

    test('weist eine Person mit sich selbst ab', () {
      expect(pruefeBeziehung(familie(), 'kind', 'kind', Verwandtschaft.elternteil),
          Beziehungsfehler.mitSichSelbst);
    });

    test('weist einen Kreis ab', () {
      // „kind" als Elternteil von „opa" wäre ein Kreis über drei Stufen.
      expect(pruefeBeziehung(familie(), 'opa', 'kind', Verwandtschaft.elternteil),
          Beziehungsfehler.kreis);
    });

    test('erkennt eine bereits eingetragene Verwandtschaft', () {
      expect(pruefeBeziehung(familie(), 'kind', 'vater', Verwandtschaft.elternteil),
          Beziehungsfehler.schonVorhanden);
      // Auch in der Gegenrichtung, in der die Kante gar nicht steht.
      expect(pruefeBeziehung(familie(), 'mutter', 'vater', Verwandtschaft.partner),
          Beziehungsfehler.schonVorhanden);
    });

    test('eine Partnerschaft darf einen Kreis nicht auslösen', () {
      // Partner sind ungerichtet – zwischen ihnen kann es keinen Kreis
      // geben, auch nicht zwischen Vorfahr und Nachkomme.
      expect(pruefeBeziehung(familie(), 'opa', 'kind', Verwandtschaft.partner), isNull);
    });
  });

  group('ausschnittUm', () {
    final reihenfolge = ['oma', 'opa', 'mutter', 'vater', 'kind', 'schwester'];

    test('sammelt die unmittelbare Verwandtschaft', () {
      final a = ausschnittUm(familie(), 'kind', reihenfolge);
      expect(a.eltern, ['mutter', 'vater']);
      expect(a.geschwister, ['schwester']);
      expect(a.kinder, isEmpty);
      expect(a.partner, isEmpty);
    });

    test('hält die vorgegebene Reihenfolge ein', () {
      final a = ausschnittUm(familie(), 'vater', ['opa', 'oma']);
      expect(a.eltern, ['opa', 'oma'], reason: 'nicht die Reihenfolge der Kanten');
    });

    test('meldet Verwandtschaft, die außerhalb des Ausschnitts liegt', () {
      final a = ausschnittUm(familie(), 'kind', reihenfolge);
      // Der Vater hat selbst Eltern – die stehen nicht im Bild.
      expect(a.weitereOben['vater'], isTrue);
      // Die Kinder des Vaters sind der Fokus und die Schwester, beide da.
      expect(a.weitereUnten['vater'], isFalse);
      // Für die Person in der Mitte gibt es nie einen Hinweis: Ihre Eltern
      // und Kinder sind genau das, was ringsum steht.
      expect(a.weitereOben['kind'], isFalse);
      expect(a.weitereUnten['kind'], isFalse);
      // Und für ein Geschwister ebenso wenig: Es hat dieselben Eltern,
      // und die stehen bereits im Bild.
      expect(a.weitereOben['schwester'], isFalse);
    });

    test('ein Halbgeschwister bekommt den Hinweis sehr wohl', () {
      // Sein zweiter Elternteil steht nicht im Bild – genau darauf soll
      // der Hinweis aufmerksam machen.
      final netz = Verwandtschaftsnetz([
        kante('kind', 'vater', Verwandtschaft.elternteil),
        kante('halb', 'vater', Verwandtschaft.elternteil),
        kante('halb', 'andereMutter', Verwandtschaft.elternteil),
      ]);
      final a = ausschnittUm(netz, 'kind', ['vater', 'kind', 'halb', 'andereMutter']);
      expect(a.geschwister, ['halb']);
      expect(a.weitereOben['halb'], isTrue);
    });

    test('ein Partner mit Kindern aus früherer Verbindung ebenso', () {
      final netz = Verwandtschaftsnetz([
        partnerKanteFuer('ich', 'du'),
        kante('unser', 'ich', Verwandtschaft.elternteil),
        kante('unser', 'du', Verwandtschaft.elternteil),
        kante('deins', 'du', Verwandtschaft.elternteil),
      ]);
      final a = ausschnittUm(netz, 'ich', ['ich', 'du', 'unser', 'deins']);
      expect(a.kinder, ['unser'], reason: 'nur die eigenen Kinder stehen unten');
      expect(a.weitereUnten['du'], isTrue);
    });

    test('ist leer, wenn nichts eingetragen ist', () {
      final a = ausschnittUm(Verwandtschaftsnetz([]), 'allein', ['allein']);
      expect(a.istLeer, isTrue);
    });
  });

  group('lebensspanne', () {
    test('nennt beide Jahre', () {
      expect(lebensspanne(DateTime(1931, 4, 2), DateTime(2004, 11, 9)), '1931–2004');
    });

    test('kommt mit nur einer Angabe aus', () {
      expect(lebensspanne(DateTime(1972, 6, 1), null), '*1972');
      expect(lebensspanne(null, DateTime(2004)), '†2004');
    });

    test('bleibt weg, wenn nichts bekannt ist', () {
      expect(lebensspanne(null, null), isNull);
    });
  });

  group('Seitenaeste', () {
    // Der Baum kannte genau fuenf Rollen: Eltern, Geschwister, Fokus,
    // Partner, Kinder. Wer wissen wollte, wo seine Tante steht, musste
    // erst auf sie ruecken.
    final netz = Verwandtschaftsnetz([
      kante('vater', 'opa', Verwandtschaft.elternteil),
      kante('vater', 'oma', Verwandtschaft.elternteil),
      kante('onkel', 'opa', Verwandtschaft.elternteil),
      kante('onkel', 'oma', Verwandtschaft.elternteil),
      kante('ich', 'vater', Verwandtschaft.elternteil),
      kante('ich', 'mutter', Verwandtschaft.elternteil),
      kante('schwester', 'vater', Verwandtschaft.elternteil),
      kante('schwester', 'mutter', Verwandtschaft.elternteil),
      kante('neffe', 'schwester', Verwandtschaft.elternteil),
      partnerKanteFuer('ich', 'gattin'),
      kante('gattin', 'schwiegervater', Verwandtschaft.elternteil),
      kante('kind', 'ich', Verwandtschaft.elternteil),
    ]);
    const alle = [
      'gattin', 'ich', 'kind', 'mutter', 'neffe', 'oma', 'onkel', 'opa',
      'schwester', 'schwiegervater', 'vater',
    ];

    test('ohne Anforderung bleibt der Ausschnitt so schmal wie bisher', () {
      final a = ausschnittUm(netz, 'ich', alle);
      expect(a.grosseltern, isEmpty);
      expect(a.onkelTanten, isEmpty);
      expect(a.neffenNichten, isEmpty);
      expect(a.schwiegereltern, isEmpty);
      expect(a.schwaeger, isEmpty);
      // Und der Kern ist unveraendert.
      expect(a.eltern, ['mutter', 'vater']);
      expect(a.geschwister, ['schwester']);
    });

    test('mit Anforderung kommen die Aeste dazu', () {
      final a = ausschnittUm(netz, 'ich', alle, seitenlinien: true);
      expect(a.grosseltern, ['oma', 'opa']);
      expect(a.onkelTanten, ['onkel']);
      expect(a.neffenNichten, ['neffe']);
      expect(a.schwiegereltern, ['schwiegervater']);
    });

    group('Schwager und Schwaegerin', () {
      // Der gemeldete Fehler: Der Verwandtschaftsrechner sagt „Schwager",
      // der Baum zeigte niemanden. Nachgestellt ist die Lage aus der
      // echten Bibliothek: Caesar und Dora sind Geschwister, Dora ist
      // mit Felix zusammen, Caesar mit Emma. Felix ist Caesars Schwager,
      // Dora ist Emmas Schwaegerin.
      final familie = Verwandtschaftsnetz([
        kante('caesar', 'berta', Verwandtschaft.elternteil),
        kante('dora', 'berta', Verwandtschaft.elternteil),
        partnerKanteFuer('dora', 'felix'),
        partnerKanteFuer('caesar', 'emma'),
      ]);
      const namen = ['dora', 'felix', 'caesar', 'emma', 'berta'];

      test('der Partner des Geschwisters', () {
        final a = ausschnittUm(familie, 'caesar', namen, seitenlinien: true);
        expect(a.geschwister, ['dora']);
        expect(a.partner, ['emma']);
        expect(a.schwaeger, ['felix']);
      });

      test('und das Geschwister des Partners – dieselbe Liste', () {
        // Aus Emmas Sicht fuehrt der Weg ueber den Partner statt ueber
        // das Geschwister. Herauskommen soll dasselbe: eine Person, die
        // im Bild steht.
        final a = ausschnittUm(familie, 'emma', namen, seitenlinien: true);
        expect(a.geschwister, isEmpty);
        expect(a.partner, ['caesar']);
        expect(a.schwaeger, ['dora']);
      });

      test('was der Rechner Schwager nennt, steht auch im Baum', () {
        // Die Gegenprobe gegen die zweite Quelle: Fuer jede Person, die
        // verwandtschaftsgrad als Schwager bezeichnet, muss der Ausschnitt
        // sie auch fuehren. Genau dieser Widerspruch war der Fehler.
        for (final ich in namen) {
          final a = ausschnittUm(familie, ich, namen, seitenlinien: true);
          for (final anderer in namen) {
            if (anderer == ich) continue;
            final grad = bestimmeGrad(familie, ich, anderer);
            if (grad.art == Gradart.schwager) {
              expect(a.schwaeger, contains(anderer),
                  reason: '$anderer ist $ich seine Schwaegerschaft');
            }
          }
        }
      });

      test('ein Schwager, der schon Geschwister ist, steht nur einmal', () {
        // Zwei Geschwister heiraten zwei Geschwister: Dann ist der
        // Schwager zugleich der Partner. Zwei Karten fuer einen Menschen
        // waeren kein Baum.
        final doppelt = Verwandtschaftsnetz([
          kante('ich', 'vater', Verwandtschaft.elternteil),
          kante('schwester', 'vater', Verwandtschaft.elternteil),
          partnerKanteFuer('ich', 'gattin'),
          kante('gattin', 'schwiegervater', Verwandtschaft.elternteil),
          kante('schwager', 'schwiegervater', Verwandtschaft.elternteil),
          partnerKanteFuer('schwester', 'schwager'),
        ]);
        const wer = [
          'gattin', 'ich', 'schwager', 'schwester', 'schwiegervater', 'vater'
        ];
        final a = ausschnittUm(doppelt, 'ich', wer, seitenlinien: true);
        // Zwei Wege zu derselben Person – „Partner meiner Schwester" und
        // „Bruder meiner Frau" – ergeben einen Eintrag, nicht zwei.
        expect(a.schwaeger, ['schwager']);
        // Und nicht zusaetzlich unter den Schwiegereltern oder sonstwo.
        expect(a.schwiegereltern, ['schwiegervater']);
        final alleGezeigt = [
          ...a.eltern, ...a.geschwister, ...a.partner, ...a.kinder,
          ...a.grosseltern, ...a.onkelTanten, ...a.neffenNichten,
          ...a.schwiegereltern, ...a.schwaeger,
        ];
        expect(alleGezeigt.toSet().length, alleGezeigt.length);
      });
    });

    test('niemand steht zweimal im Bild', () {
      // Der Fall, der in echten Familien vorkommt: Ein Kind ist zugleich
      // Neffe, weil zwei Geschwister zwei Geschwister geheiratet haben.
      // Zwei Karten fuer einen Menschen waeren kein Baum, sondern ein
      // Fehler.
      final verzwickt = Verwandtschaftsnetz([
        kante('ich', 'vater', Verwandtschaft.elternteil),
        kante('schwester', 'vater', Verwandtschaft.elternteil),
        kante('kind', 'ich', Verwandtschaft.elternteil),
        kante('kind', 'schwester', Verwandtschaft.elternteil),
      ]);
      final a = ausschnittUm(
          verzwickt, 'ich', const ['ich', 'kind', 'schwester', 'vater'],
          seitenlinien: true);
      expect(a.kinder, ['kind']);
      // „kind" steht schon als eigenes Kind da – nicht noch einmal als
      // Neffe.
      expect(a.neffenNichten, isEmpty);
    });

    test('die Reihenfolge ist dieselbe wie ueberall', () {
      final a = ausschnittUm(netz, 'ich', alle, seitenlinien: true);
      // Nach der uebergebenen Reihenfolge, nicht nach Zufall: 'oma' vor
      // 'opa', weil die Liste es so sagt.
      expect(a.grosseltern, ['oma', 'opa']);
    });

    test('auch Grosseltern stehen nur einmal', () {
      // Derselbe Weg wie beim doppelten Schwager, eine Generation hoeher:
      // Sind die Eltern Cousins, haben sie eine gemeinsame Grossmutter,
      // und die stand vorher zweimal in der Reihe.
      final cousins = Verwandtschaftsnetz([
        kante('ich', 'vater', Verwandtschaft.elternteil),
        kante('ich', 'mutter', Verwandtschaft.elternteil),
        kante('vater', 'ahnin', Verwandtschaft.elternteil),
        kante('mutter', 'ahnin', Verwandtschaft.elternteil),
      ]);
      final a = ausschnittUm(cousins, 'ich',
          const ['ahnin', 'ich', 'mutter', 'vater'],
          seitenlinien: true);
      expect(a.grosseltern, ['ahnin']);
    });

    test('Seitenaeste allein machen den Ausschnitt nicht „nicht leer"', () {
      // Sie koennen ohne Eltern gar nicht entstehen – aber die Regel soll
      // schwarz auf weiss dastehen.
      final einsam = Verwandtschaftsnetz([]);
      final a = ausschnittUm(einsam, 'ich', const ['ich'], seitenlinien: true);
      expect(a.istLeer, isTrue);
    });
  });
}
