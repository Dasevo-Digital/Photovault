import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/meldungsdienst.dart';

/// Die Regeln der Meldungszentrale.
///
/// Sie stehen als reine Funktionen über dem Dienst, damit sie ohne
/// Fenster prüfbar sind: Was verblasst wann, was geht ineinander auf,
/// was bleibt liegen.
void main() {
  group('wie lange etwas stehen bleibt', () {
    test('ein Fehler verblasst nicht von selbst', () {
      // Der einzige Fall, in dem das Verpassen etwas kostet: Wer nicht
      // erfährt, dass ein Export fehlschlug, hält ihn für erledigt.
      expect(meldungsdauer(Meldungsart.fehler), isNull);
      expect(meldungsdauer(Meldungsart.fehler, mitAktion: true), isNull);
    });

    test('mit Knopf dauert es doppelt so lang', () {
      // Vier Sekunden reichen zum Lesen, nicht zum Lesen *und* Handeln.
      expect(meldungsdauer(Meldungsart.hinweis), const Duration(seconds: 4));
      expect(meldungsdauer(Meldungsart.hinweis, mitAktion: true),
          const Duration(seconds: 8));
    });

    test('eine Warnung bleibt auch ohne Knopf länger', () {
      expect(meldungsdauer(Meldungsart.warnung), const Duration(seconds: 8));
      expect(meldungsdauer(Meldungsart.erfolg), const Duration(seconds: 4));
    });
  });

  group('was ineinander aufgeht', () {
    final steht = Meldung(
      nummer: 1,
      art: Meldungsart.warnung,
      text: 'Datei nicht lesbar',
      zeit: DateTime(2026, 8, 26),
    );

    test('gleicher Wortlaut und gleiche Art', () {
      expect(
          gehtAufIn(steht, Meldungsart.warnung, 'Datei nicht lesbar',
              hatAktion: false),
          isTrue);
    });

    test('andere Art ist eine andere Meldung', () {
      expect(
          gehtAufIn(steht, Meldungsart.fehler, 'Datei nicht lesbar',
              hatAktion: false),
          isFalse);
    });

    test('eine Meldung mit Knopf geht nie auf – in keine Richtung', () {
      // Der Knopf gehört zu genau einem Vorgang. „Rückgängig" an einer
      // zusammengefassten Meldung nähme die falsche Löschung zurück.
      expect(
          gehtAufIn(steht, Meldungsart.warnung, 'Datei nicht lesbar',
              hatAktion: true),
          isFalse);
      final mitKnopf = Meldung(
        nummer: 2,
        art: Meldungsart.warnung,
        text: 'Datei nicht lesbar',
        zeit: DateTime(2026, 8, 26),
        aktion: (beschriftung: 'Rückgängig', beiDruck: () {}),
      );
      expect(
          gehtAufIn(mitKnopf, Meldungsart.warnung, 'Datei nicht lesbar',
              hatAktion: false),
          isFalse);
    });
  });

  group('der Dienst', () {
    late Meldungsdienst d;
    setUp(() {
      d = Meldungsdienst();
      // Ein Zuhörer, weil die Fristen nur laufen, solange jemand zusieht
      // (siehe `_stelleUhr`). Ohne ihn verblasst hier nichts.
      d.addListener(() {});
    });
    tearDown(() => d.dispose());

    test('eine Meldung steht da und liegt im Verlauf', () {
      d.erfolg('Fertig');
      expect(d.sichtbare.single.text, 'Fertig');
      expect(d.verlauf.single.art, Meldungsart.erfolg);
      expect(d.ungelesen, 1);
    });

    test('dieselbe Meldung dreimal ist eine Karte mit einer Zahl', () {
      for (var i = 0; i < 3; i++) {
        d.warnung('Datei nicht lesbar');
      }
      expect(d.sichtbare, hasLength(1));
      expect(d.sichtbare.single.anzahl, 3);
      // Auch der Verlauf führt sie einmal – sonst stünde dreimal
      // dasselbe untereinander.
      expect(d.verlauf, hasLength(1));
      expect(d.verlauf.single.anzahl, 3);
      // Gezählt wird trotzdem jedes Mal: Es ist dreimal passiert.
      expect(d.ungelesen, 3);
    });

    test('zwei Meldungen mit Knopf stehen nebeneinander', () {
      d.hinweis('Gelöscht', aktion: (beschriftung: 'Zurück', beiDruck: () {}));
      d.hinweis('Gelöscht', aktion: (beschriftung: 'Zurück', beiDruck: () {}));
      expect(d.sichtbare, hasLength(2));
    });

    test('über vier weicht die älteste, bleibt aber im Verlauf', () {
      for (var i = 1; i <= 6; i++) {
        d.hinweis('Meldung $i');
      }
      expect(d.sichtbare.map((m) => m.text),
          ['Meldung 3', 'Meldung 4', 'Meldung 5', 'Meldung 6']);
      expect(d.verlauf, hasLength(6));
      // Neueste zuerst – so liest man einen Verlauf.
      expect(d.verlauf.first.text, 'Meldung 6');
    });

    test('der Verlauf läuft nicht über', () {
      for (var i = 0; i < verlaufsLaenge + 20; i++) {
        d.hinweis('Nummer $i');
      }
      expect(d.verlauf, hasLength(verlaufsLaenge));
      expect(d.verlauf.last.text, 'Nummer 20');
    });

    test('wegklicken nimmt sie aus der Anzeige, nicht aus dem Verlauf', () {
      final m = d.fehler('Kaputt');
      d.schliesse(m.nummer);
      expect(d.sichtbare, isEmpty);
      expect(d.verlauf.single.text, 'Kaputt');
    });

    test('ein Fehler bekommt keine Ablaufzeit mit', () {
      // Der Balken an der Karte liest genau dieses Feld – ohne Dauer
      // zeichnet er nicht, und die Karte bleibt stehen.
      expect(d.fehler('Kaputt').dauer, isNull);
      expect(d.hinweis('Gut').dauer, const Duration(seconds: 4));
    });

    test('ein Blick in den Verlauf setzt die Zahl zurück', () {
      d.hinweis('Eins');
      d.hinweis('Zwei');
      expect(d.ungelesen, 2);
      d.verlaufGelesen();
      expect(d.ungelesen, 0);
      // Der Verlauf selbst bleibt.
      expect(d.verlauf, hasLength(2));
    });

    test('sichtbare und Verlauf sind nicht von aussen änderbar', () {
      d.hinweis('Eins');
      expect(() => d.sichtbare.clear(), throwsUnsupportedError);
      expect(() => d.verlauf.clear(), throwsUnsupportedError);
    });

    test('nach der Frist verschwindet sie von selbst', () {
      fakeAsync((zeit) {
        d.hinweis('Kurz');
        expect(d.sichtbare, hasLength(1));
        zeit.elapse(const Duration(seconds: 5));
        expect(d.sichtbare, isEmpty);
        expect(d.verlauf, hasLength(1));
      });
    });

    test('ein Fehler steht auch nach Minuten noch da', () {
      fakeAsync((zeit) {
        d.fehler('Bleibt');
        zeit.elapse(const Duration(minutes: 5));
        expect(d.sichtbare, hasLength(1));
      });
    });

    test('eine Wiederholung stellt die Uhr neu', () {
      fakeAsync((zeit) {
        d.hinweis('Nochmal');
        zeit.elapse(const Duration(seconds: 3));
        d.hinweis('Nochmal');
        // Ohne das Neustellen wäre sie eine Sekunde später weg.
        zeit.elapse(const Duration(seconds: 2));
        expect(d.sichtbare, hasLength(1));
        zeit.elapse(const Duration(seconds: 3));
        expect(d.sichtbare, isEmpty);
      });
    });
  });
}
