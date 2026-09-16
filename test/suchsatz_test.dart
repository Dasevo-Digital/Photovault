import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/search_screen.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/services/search_filters.dart';
import 'package:photo_vault/services/suchsatz.dart';

/// Der Satzleser übersetzt „Bergfotos vom letzten Sommer mit 5 Sternen" in
/// die vorhandenen Suchkriterien. Kein Sprachmodell, sondern zehn Muster –
/// und die Zusage, dass alles Unverstandene unangetastet an die bisherige
/// Suche weitergeht.

const _vokabular = Suchvokabular(
  personen: {'p-anna': 'Anna', 'p-bernd': 'Bernd', 'p-ml': 'Marie Luise'},
  schlagwoerter: {'t-strand': 'Strand', 't-berg': 'Berge'},
  kameras: ['Canon EOS R10', 'iPhone 13 Pro'],
  laender: ['Italien'],
  regionen: ['Toskana'],
  staedte: ['Berlin', 'Berlin-Tegel', 'Rom'],
);

final _heute = DateTime(2026, 5, 20);

Satzdeutung deute(String satz, {SearchFilters grundlage = const SearchFilters()}) =>
    deuteSuchsatz(satz, vokabular: _vokabular, heute: _heute, grundlage: grundlage);

void main() {
  /// Drei Felder, die der Satzleser bis zur 7. Vergleichsauflage nicht
  /// erreichte, obwohl die Suche sie kennt.
  group('Schaerfe, ISO, Datumsherkunft', () {
    test('„unscharfe Fotos" setzt die Schaerfeschwelle', () {
      // Die Sichtung fragt genau danach; bis hierher gab es dafuer nur
      // das Kreuz im Optionenfenster.
      for (final satz in ['unscharfe Fotos', 'verwackelte Bilder']) {
        final d = deute(satz);
        expect(d.filter.maxSharpnessScore, isNotNull, reason: satz);
        expect(d.rest, isEmpty, reason: satz);
      }
    });

    test('„ab ISO 1600" grenzt nach unten ab, „bis ISO 400" nach oben', () {
      final ab = deute('ab ISO 1600');
      expect(ab.filter.minIso, 1600);
      expect(ab.filter.maxIso, isNull);

      final bis = deute('bis ISO 400');
      expect(bis.filter.maxIso, 400);
      expect(bis.filter.minIso, isNull);
    });

    test('„ISO 100" allein meint genau diesen Wert', () {
      final d = deute('ISO 100');
      expect(d.filter.minIso, 100);
      expect(d.filter.maxIso, 100);
      expect(d.rest, isEmpty);
    });

    test('eine Blende bleibt unangetastet stehen', () {
      // Bewusst NICHT gedeutet: Bei „Blende 2,8" ist nicht entschieden, ob
      // genau 2,8 oder „mindestens so offen" gemeint ist. Ein
      // halbverstandener Wert ist schlimmer als gar keiner – er liefert
      // etwas anderes, ohne dass man es der Trefferliste ansieht.
      final d = deute('Blende 2.8');
      expect(d.filter.minFNumber, isNull);
      expect(d.filter.maxFNumber, isNull);
      expect(d.rest, contains('2.8'));
    });

    test('„geschätztes Datum" findet die geratenen Zeitstempel', () {
      for (final satz in ['geschätztes Datum', 'geschaetzte Daten']) {
        final d = deute(satz);
        expect(d.filter.nurGeschaetztesDatum, isTrue, reason: satz);
        expect(d.rest, isEmpty, reason: satz);
      }
    });

    test('ein Satz aus mehreren neuen Feldern faellt nicht auseinander', () {
      final d = deute('unscharfe Fotos ab ISO 3200 aus Berlin');
      expect(d.filter.maxSharpnessScore, isNotNull);
      expect(d.filter.minIso, 3200);
      expect(d.filter.locationCity, 'Berlin');
      expect(d.rest, isEmpty);
      // Die Marken zeichnen den Satz nach, nicht die Pruefreihenfolge.
      expect([for (final f in d.funde) f.art], [
        Satzfundart.schaerfe,
        Satzfundart.medienart,
        Satzfundart.iso,
        Satzfundart.ort,
      ]);
    });
  });

  group('Bewertung, Farbe, Art', () {
    test('„5 Sterne" wird zur Mindestbewertung', () {
      final d = deute('Fotos mit 5 Sternen');
      expect(d.filter.minRating, 5);
      expect(d.rest, isEmpty, reason: 'nichts soll als Suchbegriff übrig bleiben');
    });

    test('englische Schreibweise ebenso', () {
      expect(deute('4 stars').filter.minRating, 4);
      expect(deute('3*').filter.minRating, 3);
    });

    test('eine Jahreszahl ist keine Bewertung', () {
      final d = deute('2019');
      expect(d.filter.minRating, isNull);
      expect(d.filter.startDate, DateTime(2019));
    });

    test('Farbwörter werden zur Farbmarke', () {
      expect(deute('rot markierte Fotos').filter.colorLabels, {'red'});
      expect(deute('grüne Marke').filter.colorLabels, {'green'});
      expect(deute('blue label').filter.colorLabels, {'blue'});
    });

    test('Videos und Fotos trennen die Medienart', () {
      expect(deute('Videos aus 2020').filter.mediaType, MediaTypeFilter.video);
      expect(deute('Fotos aus 2020').filter.mediaType, MediaTypeFilter.image);
      expect(deute('2020').filter.mediaType, MediaTypeFilter.all);
    });

    test('Favoriten', () {
      expect(deute('meine Favoriten').filter.favoritesOnly, isTrue);
      expect(deute('Berlin').filter.favoritesOnly, isFalse);
    });
  });

  group('Zeit', () {
    test('nackte Jahreszahl ergibt das ganze Jahr', () {
      final d = deute('2019');
      expect(d.filter.startDate, DateTime(2019));
      expect(d.filter.endDate, DateTime(2019, 12, 31));
    });

    test('„letztes Jahr" rechnet vom übergebenen Heute', () {
      final d = deute('letztes Jahr');
      expect(d.filter.startDate, DateTime(2025));
      expect(d.filter.endDate, DateTime(2025, 12, 31));
    });

    test('„dieses Jahr" ebenso', () {
      expect(deute('dieses Jahr').filter.startDate, DateTime(2026));
    });

    test('„Sommer 2019" sind Juni bis August', () {
      final d = deute('Sommer 2019');
      expect(d.filter.startDate, DateTime(2019, 6));
      expect(d.filter.endDate, DateTime(2019, 8, 31));
    });

    test('„letzten Sommer" ist der Sommer des Vorjahres', () {
      final d = deute('letzten Sommer');
      expect(d.filter.startDate, DateTime(2025, 6));
      expect(d.filter.endDate, DateTime(2025, 8, 31));
    });

    test('der Winter läuft über den Jahreswechsel', () {
      // „Winter 2020" schliesst den Dezember 2019 ein – das ist die
      // Lesart, die man meint, wenn man von einem Winter spricht.
      final d = deute('Winter 2020');
      expect(d.filter.startDate, DateTime(2019, 12));
      expect(d.filter.endDate, DateTime(2020, 2, 29));
    });

    test('„Juli 2020" ist genau der Monat', () {
      final d = deute('Juli 2020');
      expect(d.filter.startDate, DateTime(2020, 7));
      expect(d.filter.endDate, DateTime(2020, 7, 31));
    });

    test('„im Juli" ohne Jahr meint den letzten vergangenen Juli', () {
      // Heute ist der 20. Mai 2026 – der Juli liegt in der Zukunft, gemeint
      // ist also der von 2025.
      expect(deute('im Juli').filter.startDate, DateTime(2025, 7));
      // Der März dagegen liegt hinter uns.
      expect(deute('im März').filter.startDate, DateTime(2026, 3));
    });

    test('die genauere Angabe gewinnt vor der gröberen', () {
      // Käme die nackte Jahreszahl zuerst dran, bliebe „Sommer" als
      // Suchbegriff stehen und die Bildsuche liefe darauf los.
      final d = deute('Sommer 2019');
      expect(d.rest, isEmpty);
    });
  });

  group('Vokabular aus der Bibliothek', () {
    test('erkennt eine Person', () {
      final d = deute('Anna am Strand');
      expect(d.filter.personIds, ['p-anna']);
      expect(d.filter.tagIds, ['t-strand']);
      expect(d.rest, isEmpty);
    });

    test('erkennt mehrere Personen', () {
      // Die Reihenfolge in personIds trägt nichts – die Abfrage verknüpft
      // sie ohnehin. Geprüft wird deshalb die Menge.
      expect(deute('Anna und Bernd').filter.personIds,
          unorderedEquals(['p-anna', 'p-bernd']));
    });

    test('die Funde stehen in der Reihenfolge des Satzes', () {
      final d = deute('Bernd und Anna 2019');
      expect([for (final f in d.funde) f.wert], ['Bernd', 'Anna', '2019']);
    });

    test('ein Name aus zwei Wörtern geht vor dem kürzeren', () {
      final d = deute('Marie Luise');
      expect(d.filter.personIds, ['p-ml']);
    });

    test('der längere Ortsname gewinnt', () {
      // Sonst schnappt „Berlin" den Ausschnitt weg, den „Berlin-Tegel"
      // gebraucht hätte.
      expect(deute('Berlin-Tegel').filter.locationCity, 'Berlin-Tegel');
      expect(deute('Berlin').filter.locationCity, 'Berlin');
    });

    test('trennt Stadt, Region und Land', () {
      final d = deute('Rom Toskana Italien');
      expect(d.filter.locationCity, 'Rom');
      expect(d.filter.locationState, 'Toskana');
      expect(d.filter.locationCountry, 'Italien');
    });

    test('erkennt die Kamera', () {
      expect(deute('mit der Canon EOS R10').filter.cameraModel, 'Canon EOS R10');
    });

    test('ein Wortteil ist kein Treffer', () {
      // „Anna" darf nicht in „Ananas" anschlagen.
      final d = deute('Ananas');
      expect(d.filter.personIds, isEmpty);
      expect(d.rest, 'Ananas');
    });
  });

  group('Was übrig bleibt', () {
    test('geht unverändert an die bisherige Suche', () {
      final d = deute('Sonnenuntergang am Meer 2019');
      expect(d.filter.startDate, DateTime(2019));
      expect(d.rest, 'Sonnenuntergang Meer');
      expect(d.filter.query, 'Sonnenuntergang Meer');
    });

    test('Füllwörter allein sind kein Suchbegriff', () {
      expect(deute('zeige mir alle Fotos von 2019').rest, isEmpty);
    });

    test('ein Satz ohne jedes Muster bleibt vollständig stehen', () {
      final d = deute('Sonnenuntergang am Meer');
      expect(d.hatVerstanden, isFalse);
      expect(d.rest, 'Sonnenuntergang Meer');
      expect(d.filter.isEmpty, isFalse, reason: 'die Anfrage steht als query da');
    });

    test('eine leere Eingabe ergibt einen leeren Filter', () {
      final d = deute('');
      expect(d.hatVerstanden, isFalse);
      expect(d.filter.isEmpty, isTrue);
    });
  });

  group('Der Weg dorthin', () {
    // Die Rechnung allein zu pruefen sagt nichts darueber, ob sie jemals
    // aufgerufen wird - genau das war der Fehler in 1.9.6.
    late Directory wurzel;
    late AppDatabase db;
    late LibraryState library;

    setUp(() async {
      wurzel = Directory.systemTemp.createTempSync('pv_suchsatz_');
      db = AppDatabase(NativeDatabase.memory());
      library = LibraryState()
        ..db = db
        ..paths = await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')));
      await db.createPerson(PeopleCompanion.insert(id: 'p-anna', name: 'Anna'));
      await db.insertAsset(AssetsCompanion.insert(
        id: 'a1',
        relativePath: 'originals/a1.jpg',
        originalFileName: 'a1.jpg',
        type: 'IMAGE',
        fileSizeBytes: const Value(10),
        checksum: 'a1',
        fileCreatedAt: DateTime(2019, 7, 4),
        importedAt: DateTime(2019, 7, 5),
        rating: const Value(5),
      ));
    });

    tearDown(() async {
      await db.close();
      wurzel.deleteSync(recursive: true);
    });

    testWidgets('ein getippter Satz wird gedeutet und zeigt seine Marken',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(body: SearchScreen(library: library)),
      ));
      // Kein pumpAndSettle: Der Bildschirm haengt an einem drift-Strom
      // (gespeicherte Suchen), und der kommt nie zur Ruhe - der Test bliebe
      // wortlos stehen statt durchzufallen. Feste Takte statt zu warten.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextField).first, 'Anna 2019 mit 5 Sternen');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Die Marken stehen unter dem Feld, benannt und mit ihrem Wert.
      expect(find.text('Bewertung: 5'), findsOneWidget);
      expect(find.text('Zeitraum: 2019'), findsOneWidget);
      expect(find.text('Personen: Anna'), findsOneWidget);
      expect(find.byTooltip('Deutung zurücknehmen und wörtlich suchen'),
          findsOneWidget);

      // Den Strom abbauen, sonst bleibt sein Zeitgeber liegen und der Lauf
      // haengt am Ende (siehe kachelmitschnitt_ansicht_test.dart).
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  group('Der ganze Satz', () {
    test('„Bergfotos vom letzten Sommer mit 5 Sternen"', () {
      final d = deute('Berge vom letzten Sommer mit 5 Sternen');
      expect(d.filter.minRating, 5);
      expect(d.filter.startDate, DateTime(2025, 6));
      expect(d.filter.endDate, DateTime(2025, 8, 31));
      expect(d.filter.tagIds, ['t-berg']);
      expect(d.rest, isEmpty);
      expect(d.funde.length, 3);
    });

    test('jeder Fund nennt Wortlaut und Wert, damit man es nachlesen kann', () {
      final d = deute('Anna 2019 mit 4 Sternen');
      final nachArt = {for (final f in d.funde) f.art: f};
      expect(nachArt[Satzfundart.bewertung]!.wert, '4');
      expect(nachArt[Satzfundart.zeitraum]!.wert, '2019');
      expect(nachArt[Satzfundart.person]!.wert, 'Anna');
      expect(nachArt[Satzfundart.person]!.wortlaut, 'Anna');
    });

    test('von Hand gesetzte Kriterien bleiben stehen', () {
      final d = deute('2019', grundlage: const SearchFilters(favoritesOnly: true));
      expect(d.filter.favoritesOnly, isTrue);
      expect(d.filter.startDate, DateTime(2019));
    });
  });
}
