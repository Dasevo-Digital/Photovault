import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/db/rasterzeile.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/calendar_screen.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/month_grouped_asset_grid.dart';
import 'package:photo_vault/widgets/timeline_scrubber.dart';

/// **Der Kalender hatte zwei Stufen, gebraucht werden drei.**
///
/// Ein Klick aufs Jahr führte unmittelbar in alle Aufnahmen des Jahres.
/// An einem Jahrgang von über tausend Bildern ist das keine Übersicht
/// mehr; ein bestimmter Monat war darin nur durch Scrollen zu finden.
///
/// Dazwischen steht jetzt die Monatsübersicht, und **im Monat wird nach
/// Tagen gegliedert** – sonst gäbe es dort genau eine Gruppe und der
/// Zeitstrahl fiele mangels zweiter Gruppe weg.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_kal_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths =
          await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')));
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> aufnahme(String id, DateTime wann) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'pruef-$id',
            type: 'IMAGE',
            fileCreatedAt: wann,
            importedAt: DateTime(2026),
            thumbnailRelativePath: Value('thumbs/$id.jpg'),
          ));

  Future<void> zeige(WidgetTester tester, Widget was) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: was,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> abbauen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  group('Die Monatsübersicht', () {
    testWidgets('zeigt nur Monate, in denen etwas liegt', (tester) async {
      await aufnahme('a', DateTime(2026, 3, 5, 10));
      await aufnahme('b', DateTime(2026, 3, 9, 10));
      await aufnahme('c', DateTime(2026, 7, 1, 10));
      await zeige(tester,
          MonatsuebersichtScreen(library: library, jahr: 2026));

      expect(find.text('März'), findsOneWidget);
      expect(find.text('Juli'), findsOneWidget);
      // Zwölf Kacheln, von denen zehn leer sind, sagen weniger als zwei
      // volle.
      expect(find.text('Januar'), findsNothing);
      await abbauen(tester);
    });

    testWidgets('zählt richtig und stellt den jüngsten Monat nach vorn',
        (tester) async {
      await aufnahme('a', DateTime(2026, 3, 5, 10));
      await aufnahme('b', DateTime(2026, 3, 9, 10));
      await aufnahme('c', DateTime(2026, 7, 1, 10));
      // Ein Nachbarjahr, das nicht mitzählen darf.
      await aufnahme('d', DateTime(2025, 3, 4, 10));
      await zeige(tester,
          MonatsuebersichtScreen(library: library, jahr: 2026));

      // Beide Kacheln stehen in derselben Zeile - „vorn" heisst hier
      // also links, nicht oben.
      final juli = tester.getRect(find.text('Juli'));
      final maerz = tester.getRect(find.text('März'));
      expect(juli.top, closeTo(maerz.top, 0.5));
      expect(juli.left, lessThan(maerz.left));

      // Und gezaehlt wird nur innerhalb des Jahres: Der Maerz 2025 darf
      // den Maerz 2026 nicht mitzaehlen.
      expect(find.text('2 Fotos/Videos'), findsOneWidget);
      expect(find.text('1 Foto/Video'), findsOneWidget);
      await abbauen(tester);
    });

    testWidgets('ein Monat führt in seine Aufnahmen', (tester) async {
      await aufnahme('a', DateTime(2026, 3, 5, 10));
      await zeige(tester,
          MonatsuebersichtScreen(library: library, jahr: 2026));
      await tester.tap(find.text('März'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(YearDetailScreen), findsOneWidget);
      expect(find.text('März 2026'), findsWidgets);
      await abbauen(tester);
    });

    testWidgets('das ganze Jahr bleibt erreichbar', (tester) async {
      await aufnahme('a', DateTime(2026, 3, 5, 10));
      await zeige(tester,
          MonatsuebersichtScreen(library: library, jahr: 2026));
      await tester.tap(find.text('Ganzes Jahr'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('2026'), findsWidgets);
      await abbauen(tester);
    });
  });

  group('Im Monat wird nach Tagen gegliedert', () {
    testWidgets('jeder Tag bekommt eine Überschrift', (tester) async {
      await aufnahme('a', DateTime(2026, 3, 5, 10));
      await aufnahme('b', DateTime(2026, 3, 5, 14));
      await aufnahme('c', DateTime(2026, 3, 9, 10));
      await zeige(tester,
          YearDetailScreen(library: library, year: 2026, monat: 3));

      expect(find.textContaining('5. März 2026'), findsOneWidget);
      expect(find.textContaining('9. März 2026'), findsOneWidget);
      await abbauen(tester);
    });

    testWidgets('und der Zeitstrahl steht daneben', (tester) async {
      // Der eigentliche Grund für die Tagesgliederung: Nach Monaten
      // gegliedert gäbe es hier eine einzige Gruppe, und der Zeitstrahl
      // erscheint erst ab zweien.
      await aufnahme('a', DateTime(2026, 3, 5, 10));
      await aufnahme('b', DateTime(2026, 3, 9, 10));
      await zeige(tester,
          YearDetailScreen(library: library, year: 2026, monat: 3));
      expect(find.byType(TimelineScrubber), findsOneWidget);
      await abbauen(tester);
    });

    testWidgets('über ein ganzes Jahr bleibt es bei den Monaten',
        (tester) async {
      await aufnahme('a', DateTime(2026, 3, 5, 10));
      await aufnahme('b', DateTime(2026, 7, 9, 10));
      await zeige(tester, YearDetailScreen(library: library, year: 2026));
      expect(find.text('März 2026'), findsOneWidget);
      expect(find.textContaining('5. März'), findsNothing);
      await abbauen(tester);
    });

    testWidgets('ein Monat zeigt nur seine eigenen Aufnahmen',
        (tester) async {
      await aufnahme('a', DateTime(2026, 3, 5, 10));
      await aufnahme('b', DateTime(2026, 4, 5, 10));
      await zeige(tester,
          YearDetailScreen(library: library, year: 2026, monat: 3));
      expect(find.textContaining('5. März 2026'), findsOneWidget);
      expect(find.textContaining('April'), findsNothing);
      await abbauen(tester);
    });
  });

  group('Die Gruppierung selbst', () {
    test('tagesgruppen trennt nach Tagen und sortiert absteigend', () async {
      // Die Aufnahmen kommen aus der Datenbank und nicht aus einem von
      // Hand gebauten AssetData: Der Datentyp hat zwanzig Pflichtfelder,
      // und keines davon hat mit dieser Rechnung zu tun.
      await aufnahme('1', DateTime(2026, 3, 9, 8));
      await aufnahme('2', DateTime(2026, 3, 5, 23, 59));
      await aufnahme('3', DateTime(2026, 3, 5, 0, 1));
      final alle = await db.watchTimelineForMonth(2026, 3).first;

      final g = tagesgruppen([for (final x in alle) Rasterzeile.aus(x)]);
      expect(g.schluessel, [20260309, 20260305]);
      expect(g.gruppen[20260305], hasLength(2));
      expect(g.gruppen[20260309], hasLength(1));
    });

    test('ueber Mitternacht hinweg sind es zwei Tage', () async {
      // Der Fall, der eine Gruppierung nach Kalendertag von einer nach
      // 24-Stunden-Abstand unterscheidet.
      await aufnahme('spaet', DateTime(2026, 3, 5, 23, 50));
      await aufnahme('frueh', DateTime(2026, 3, 6, 0, 10));
      final alle = await db.watchTimelineForMonth(2026, 3).first;
      expect(tagesgruppen([for (final x in alle) Rasterzeile.aus(x)]).schluessel, hasLength(2));
    });
  });
}
