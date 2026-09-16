import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/db/rasterzeile.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/search_screen.dart';
import 'package:photo_vault/screens/timeline_screen.dart';
import 'package:photo_vault/services/search_filters.dart';
import 'package:photo_vault/services/sortierung.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';
import 'package:photo_vault/widgets/month_grouped_asset_grid.dart';
import 'package:photo_vault/widgets/timeline_scrubber.dart';

/// **Die Zeitleiste und die Suche lassen sich umsortieren.**
///
/// Bis hierher stand `ORDER BY file_created_at DESC` fest in der Abfrage;
/// wer die aeltesten Aufnahmen zuerst sehen wollte, musste bis ans Ende
/// scrollen.
///
/// Zwei Dinge sind dabei leicht zu uebersehen, und beide stehen unten als
/// eigener Fall: Die **Monatsgliederung** darf nur bei einer Reihenfolge
/// nach dem Aufnahmedatum ueberhaupt stattfinden – sonst behauptet eine
/// Ueberschrift „Maerz 2019" ueber einer Gruppe, in der jedes Jahr
/// vorkommt. Und die **zwei Fassungen derselben Reihenfolge** (SQL fuer
/// die Zeitleiste, Vergleicher in Dart fuer die Suche) muessen dasselbe
/// sagen.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_sort_');
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

  Future<void> aufnahme(
    String id, {
    required DateTime wann,
    DateTime? importiert,
    String? name,
    int rating = 0,
    int bytes = 0,
  }) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: name ?? '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'pruef-$id',
            type: 'IMAGE',
            fileCreatedAt: wann,
            importedAt: importiert ?? wann,
            rating: Value(rating),
            fileSizeBytes: Value(bytes),
          ));

  /// Drei Aufnahmen, bei denen jede Reihenfolge eine andere Abfolge ergibt.
  Future<void> dreiVerschiedene() async {
    await aufnahme('alt',
        wann: DateTime(2019, 3, 4),
        importiert: DateTime(2026, 1, 1),
        name: 'ccc.jpg',
        rating: 5,
        bytes: 100);
    await aufnahme('mitte',
        wann: DateTime(2022, 7, 9),
        importiert: DateTime(2024, 1, 1),
        name: 'aaa.jpg',
        rating: 1,
        bytes: 900);
    await aufnahme('neu',
        wann: DateTime(2025, 11, 2),
        importiert: DateTime(2025, 1, 1),
        name: 'bbb.jpg',
        rating: 3,
        bytes: 500);
  }

  Future<List<String>> ausDb(Rastersortierung s) async {
    final zeilen =
        await db.watchRasterzeilen(sortierung: s).first;
    return [for (final z in zeilen) z.id];
  }

  const erwartet = <Rastersortierung, List<String>>{
    Rastersortierung.aufnahmeNeu: ['neu', 'mitte', 'alt'],
    Rastersortierung.aufnahmeAlt: ['alt', 'mitte', 'neu'],
    Rastersortierung.importNeu: ['alt', 'neu', 'mitte'],
    Rastersortierung.name: ['mitte', 'neu', 'alt'],
    Rastersortierung.bewertung: ['alt', 'neu', 'mitte'],
    Rastersortierung.groesse: ['mitte', 'neu', 'alt'],
  };

  test('jede Reihenfolge ordnet die Kachelwand anders', () async {
    await dreiVerschiedene();
    for (final eintrag in erwartet.entries) {
      expect(await ausDb(eintrag.key), eintrag.value,
          reason: 'watchRasterzeilen mit ${eintrag.key.name}');
    }
  });

  test('watchTimeline ordnet wie watchRasterzeilen', () async {
    await dreiVerschiedene();
    for (final s in Rastersortierung.values) {
      final voll = await db.watchTimeline(sortierung: s).first;
      expect([for (final a in voll) a.id], erwartet[s],
          reason: 'watchTimeline mit ${s.name}');
    }
  });

  test('der Vergleicher in Dart sagt dasselbe wie das SQL', () async {
    await dreiVerschiedene();
    final alle = await db.watchTimeline().first;
    for (final s in Rastersortierung.values) {
      final sortiert = List<AssetData>.of(alle)
        ..sort(sortierungVergleicher(s));
      expect([for (final a in sortiert) a.id], erwartet[s],
          reason: 'Vergleicher fuer ${s.name}');
    }
  });

  test('die eingestellte Reihenfolge ueberlebt einen Neustart', () async {
    expect(await db.zeitleisteSortierungWert(), rastersortierungVorgabe);
    await db.setzeZeitleisteSortierung(Rastersortierung.groesse);
    expect(await db.zeitleisteSortierungWert(), Rastersortierung.groesse);
    // Eine Zahl, die es in dieser Fassung nicht gibt, darf den
    // Bildschirm nicht verhindern.
    expect(rastersortierung(99), rastersortierungVorgabe);
    expect(rastersortierung(-1), rastersortierungVorgabe);
  });

  test('nur das Aufnahmedatum gliedert nach Monaten', () {
    expect(nachAufnahmedatum(Rastersortierung.aufnahmeNeu), isTrue);
    expect(nachAufnahmedatum(Rastersortierung.aufnahmeAlt), isTrue);
    for (final s in [
      Rastersortierung.importNeu,
      Rastersortierung.name,
      Rastersortierung.bewertung,
      Rastersortierung.groesse,
    ]) {
      expect(nachAufnahmedatum(s), isFalse, reason: s.name);
    }
    expect(sortierungAbsteigend(Rastersortierung.aufnahmeAlt), isFalse);
    expect(sortierungAbsteigend(Rastersortierung.aufnahmeNeu), isTrue);
  });

  test('die Monate laufen in dieselbe Richtung wie die Fotos', () {
    Rasterzeile z(String id, DateTime wann) => Rasterzeile(
          id: id,
          type: 'IMAGE',
          originalFileName: '$id.jpg',
          relativePath: 'o/$id.jpg',
          thumbnailRelativePath: null,
          fileCreatedAt: wann,
          durationSeconds: null,
          isFavorite: false,
          isStackCover: false,
          stackId: null,
          stackSize: null,
          linkedAssetId: null,
          rating: 0,
          colorLabel: null,
          widthPx: null,
          heightPx: null,
          latitude: null,
          longitude: null,
          cameraMake: null,
          isLocked: false,
        );
    final liste = [
      z('a', DateTime(2020, 1, 5)),
      z('b', DateTime(2021, 6, 5)),
      z('c', DateTime(2022, 9, 5)),
    ];
    expect(monatsgruppen(liste).schluessel, [202209, 202106, 202001]);
    expect(monatsgruppen(liste, absteigend: false).schluessel,
        [202001, 202106, 202209]);
  });

  Widget rahmen(Widget kind) => MaterialApp(
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        locale: const Locale('de'),
        home: kind,
      );

  Future<void> abbauen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('das Raster nimmt die gemerkte Reihenfolge an', (tester) async {
    await dreiVerschiedene();
    await db.setzeZeitleisteSortierung(Rastersortierung.aufnahmeAlt);

    await tester.pumpWidget(
        rahmen(Scaffold(body: TimelineScreen(library: library))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final raster =
        tester.widget<MonthGroupedAssetGrid>(find.byType(MonthGroupedAssetGrid));
    expect([for (final a in raster.assets) a.id], ['alt', 'mitte', 'neu']);
    // Aufsteigend heisst: auch die Monate laufen vorwaerts.
    expect(raster.absteigend, isFalse);
    expect(raster.gliedern, isTrue);
    await abbauen(tester);
  });

  testWidgets('ohne Zeitbezug faellt die Monatsgliederung weg',
      (tester) async {
    await dreiVerschiedene();
    await db.setzeZeitleisteSortierung(Rastersortierung.groesse);

    await tester.pumpWidget(
        rahmen(Scaffold(body: TimelineScreen(library: library))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final raster =
        tester.widget<MonthGroupedAssetGrid>(find.byType(MonthGroupedAssetGrid));
    expect([for (final a in raster.assets) a.id], ['mitte', 'neu', 'alt']);
    // Der eigentliche Fund: Eine Ueberschrift „Juli 2022" ueber einer nach
    // Dateigroesse sortierten Gruppe waere eine falsche Auskunft.
    expect(raster.gliedern, isFalse);
    // Und ohne Gliederung darf auch kein Zeitstrahl daneben stehen.
    expect(find.byType(TimelineScrubber), findsNothing);
    await abbauen(tester);
  });

  testWidgets('die Suche ordnet ihre Treffer um', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await dreiVerschiedene();

    await db.createSavedSearch('s1', 'nur Fotos',
        const SearchFilters(mediaType: MediaTypeFilter.image));

    await tester
        .pumpWidget(rahmen(Scaffold(body: SearchScreen(library: library))));
    // Kein pumpAndSettle: Der Bildschirm haengt an einem drift-Strom
    // (gespeicherte Suchen), und der kommt nie zur Ruhe.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Ueber eine gespeicherte Suche, weil die Kontextsuche ein
    // CLIP-Modell braeuchte: nur Fotos, also alle drei. Die
    // Fundreihenfolge ist die von searchAssets - Aufnahmedatum
    // absteigend.
    await tester.tap(find.text('nur Fotos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Der Eintrag selbst und nicht nur seine Beschriftung: Die
    // Beschriftung sitzt im Menue neben dem Haken, und ein Tipp auf ihre
    // Mitte trifft die Schaltflaeche nur zufaellig.
    Finder menueEintrag(String text) => find.ancestor(
        of: find.text(text),
        matching: find.byType(CheckedPopupMenuItem<Object>));

    List<String> kacheln() => [
          for (final k in tester.widgetList<AssetThumbnailTile>(
              find.byType(AssetThumbnailTile)))
            k.asset.id
        ];
    expect(kacheln(), ['neu', 'mitte', 'alt']);

    // Umstellen auf Dateiname A-Z.
    await tester.tap(find.byTooltip('Reihenfolge'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(menueEintrag('Dateiname, A–Z'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(kacheln(), ['mitte', 'neu', 'alt']);

    // Und zurueck auf die Fundreihenfolge - die liesse sich durch keine
    // Spalte nachbilden, deshalb steht sie im Menue.
    await tester.tap(find.byTooltip('Reihenfolge'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(menueEintrag('Fundreihenfolge'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(kacheln(), ['neu', 'mitte', 'alt']);

    await abbauen(tester);
  });
}
