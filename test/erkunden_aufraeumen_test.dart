import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/explore_screen.dart';
import 'package:photo_vault/services/rasterstufen.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/profilbild.dart';

/// **Die Übersicht handelte von sich selbst.**
///
/// Wer weder Alben noch Reisen noch Aktivitäten angelegt hatte, sah drei
/// Überschriften mit je einem Satz darunter, dass da nichts sei – und
/// daneben einen Knopf „Alle anzeigen", der in eine leere Liste führte.
///
/// Und sie füllte den Schirm nicht: zehn Personen, acht Alben, zwölf
/// Fotos, gleich ob das Fenster 900 oder 2000 Punkte breit war.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_erk_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'l')));
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });


  Future<void> zeige(WidgetTester tester, {double breite = 1000}) async {
    tester.view.physicalSize = Size(breite, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: Scaffold(body: ExploreScreen(library: library)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> abbauen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  group('Leere Abschnitte', () {
    testWidgets('eine frische Bibliothek zeigt keine leeren Ueberschriften',
        (tester) async {
      await zeige(tester);
      expect(find.text('Personen'), findsNothing);
      expect(find.text('Orte'), findsNothing);
      expect(find.text('Reisen'), findsNothing);
      expect(find.text('Aktivitäten'), findsNothing);
      expect(find.text('Zuletzt hinzugefügte Alben'), findsNothing);
      await abbauen(tester);
    });

    testWidgets('die letzten Fotos bleiben auch leer stehen', (tester) async {
      // Der eine Abschnitt mit einem Hinweis: Eine Bibliothek ganz ohne
      // Fotos ist eine Auskunft, kein Zufall.
      await zeige(tester);
      expect(find.text('Zuletzt hinzugefügte Fotos'), findsOneWidget);
      await abbauen(tester);
    });

    testWidgets('ein angelegtes Album bringt seinen Abschnitt zurueck',
        (tester) async {
      await db.createAlbum(AlbumsCompanion.insert(
          id: 'a1', name: 'Urlaub', createdAt: DateTime(2026, 5)));
      await zeige(tester);
      expect(find.text('Zuletzt hinzugefügte Alben'), findsOneWidget);
      expect(find.text('Urlaub'), findsOneWidget);
      await abbauen(tester);
    });
  });

  group('So viele, wie hineinpassen', () {
    /// Die Rechnung selbst – sie entscheidet, und sie ist ohne Bildschirm
    /// nachzurechnen.
    test('breiter heisst mehr', () {
      final schmal = streifenAnzahl(900,
          kachelbreite: 76, abstand: 12, hoechstens: 24);
      final breit = streifenAnzahl(2000,
          kachelbreite: 76, abstand: 12, hoechstens: 24);
      expect(breit, greaterThan(schmal));
    });

    test('die Obergrenze haelt', () {
      expect(
          streifenAnzahl(5000, kachelbreite: 76, abstand: 12, hoechstens: 24),
          24);
    });

    test('auf einem sehr schmalen Fenster bleibt trotzdem etwas stehen', () {
      // Lieber eine Kachel, die halb hineinragt, als ein leerer
      // Abschnitt.
      expect(
          streifenAnzahl(100, kachelbreite: 190, abstand: 12, hoechstens: 16),
          3);
    });

    test('die letzte Kachel braucht keinen Abstand hinter sich', () {
      // Zwei Kacheln zu 76 und ein Abstand von 12 sind 164 Punkte -
      // genau das muss passen, nicht 176.
      expect(
          streifenAnzahl(164,
              kachelbreite: 76, abstand: 12, hoechstens: 24, mindestens: 1),
          2);
      expect(
          streifenAnzahl(163,
              kachelbreite: 76, abstand: 12, hoechstens: 24, mindestens: 1),
          1);
    });

    testWidgets('im breiten Fenster stehen mehr Personen', (tester) async {
      for (var i = 0; i < 24; i++) {
        await db.createPerson(
            PeopleCompanion.insert(id: 'p$i', name: 'Person $i'));
      }
      await zeige(tester, breite: 900);
      final schmal = tester.widgetList<Profilbild>(find.byType(Profilbild)).length;
      await abbauen(tester);

      await zeige(tester, breite: 2000);
      final breit = tester.widgetList<Profilbild>(find.byType(Profilbild)).length;
      await abbauen(tester);

      expect(breit, greaterThan(schmal));
      expect(schmal, greaterThan(0));
    });
  });
}
