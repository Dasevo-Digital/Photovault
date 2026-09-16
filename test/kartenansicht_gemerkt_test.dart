import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/screens/map_screen.dart';

/// Die zuletzt gewählte Kartenansicht überdauert das Schliessen.
///
/// Anlass: Sie lag nur im Bildschirmzustand. Wer die Topografiekarte
/// einstellte und die Ansicht verliess, fand beim nächsten Öffnen wieder
/// die dunkle vor – ohne dass das irgendwo stand. Genau derselbe Fall wie
/// seinerzeit bei der Gesichts-Ähnlichkeitsschwelle.
void main() {
  group('Vom Text zur Ansicht und zurueck', () {
    test('jede Ansicht traegt einen eigenen Text', () {
      final texte = Kartenansicht.values.map((a) => a.alsText).toSet();
      expect(texte, hasLength(Kartenansicht.values.length),
          reason: 'zwei gleiche Texte hiessen, dass eine Wahl eine andere '
              'zurueckliest');
    });

    test('was gespeichert wurde, kommt zurueck', () {
      for (final a in Kartenansicht.values) {
        expect(Kartenansicht.ausText(a.alsText), a);
      }
    });

    test('Unbekanntes faellt auf die dunkle Karte zurueck', () {
      // Der Fall, der sonst den Start verhindert: eine Angabe aus einer
      // neueren Fassung, oder eine leere Spalte.
      expect(Kartenansicht.ausText('satellit'), Kartenansicht.dunkel);
      expect(Kartenansicht.ausText(null), Kartenansicht.dunkel);
      expect(Kartenansicht.ausText(''), Kartenansicht.dunkel);
    });

    test('die Texte haengen nicht an der Reihenfolge', () {
      // Wuerde der Index gespeichert, verschoebe ein spaeter
      // dazwischengeschobener Eintrag stillschweigend jede gemerkte Wahl.
      expect(Kartenansicht.topo.alsText, 'topo');
      expect(Kartenansicht.globus.alsText, 'globus');
    });
  });

  group('In der Datenbank', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('ohne Zutun steht dort die dunkle Karte', () async {
      expect(Kartenansicht.ausText(await db.kartenansicht()),
          Kartenansicht.dunkel);
    });

    test('eine Wahl bleibt stehen', () async {
      await db.setzeKartenansicht(Kartenansicht.topo.alsText);
      expect(Kartenansicht.ausText(await db.kartenansicht()),
          Kartenansicht.topo);
    });

    test('eine zweite Wahl ueberschreibt die erste, ohne Zeile zu doppeln',
        () async {
      await db.setzeKartenansicht(Kartenansicht.hell.alsText);
      await db.setzeKartenansicht(Kartenansicht.globus.alsText);
      expect(Kartenansicht.ausText(await db.kartenansicht()),
          Kartenansicht.globus);
    });

    test('das Merken loescht die uebrigen Einstellungen nicht', () async {
      // `insertOnConflictUpdate` mit einem halb gefuellten Companion ist
      // die Stelle, an der so etwas passiert: Wuerden die uebrigen Spalten
      // mitgeschrieben, faende der Nutzer nach einem Kartenwechsel seine
      // Spracheinstellung zurueckgesetzt.
      await db.setzeUebersetzeBeschreibungen(true);
      await db.setzeKartenansicht(Kartenansicht.topo.alsText);
      expect(await db.uebersetzeBeschreibungen(), isTrue);
    });
  });
}
