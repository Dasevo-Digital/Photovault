import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/db/rasterzeile.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/timeline_screen.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/month_grouped_asset_grid.dart';
import 'package:photo_vault/widgets/timeline_grid_layout.dart';

/// **Näher heran und weiter weg.**
///
/// Die Zeitleiste hatte genau eine Kachelgrösse – 160 Punkte, als
/// Konstante an zwei Stellen, und an einer davon (dem Raster selbst) noch
/// einmal als blanke 160 daneben. Wer mehr Monate auf einmal sehen
/// wollte, hatte keinen Weg dorthin.
/// Eine Aufnahme, wie sie die Hoehenrechnung braucht - mehr als Masse und
/// Datum sieht sie nicht an.
Rasterzeile _quadratfoto(String id) => Rasterzeile.aus(AssetData(
      id: id,
      relativePath: 'originals/$id.jpg',
      originalFileName: '$id.jpg',
      type: 'IMAGE',
      fileSizeBytes: 1000,
      checksum: id,
      fileCreatedAt: DateTime(2026, 1, 1),
      importedAt: DateTime(2026, 1, 1),
      isFavorite: false,
      isTrashed: false,
      isLocked: false,
      faceScanExcluded: false,
      gpsGeprueft: false,
      datumGeschaetzt: false,
      datumGeprueft: false,
      ortGeerbt: false,
      videobilderGeprueft: false,
      backedUp: false,
      autoBackedUp: false,
      facesScanned: false,
      ocrScanned: false,
      aiCaptionScanned: false,
      aiCaptionEdited: false,
      aiTagsScanned: false,
      isStackCover: false,
      rating: 0,
    ));

void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_zoom_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'l')));
    for (var monat = 1; monat <= 6; monat++) {
      for (var k = 0; k < 4; k++) {
        final id = 'm${monat}_$k';
        await db.into(db.assets).insert(AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.jpg',
              relativePath: 'o/$id.jpg',
              checksum: 'c$id',
              type: 'IMAGE',
              fileCreatedAt: DateTime(2026, monat, 5 + k),
              importedAt: DateTime(2026),
              thumbnailRelativePath: Value('t/$id.jpg'),
            ));
      }
    }
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> zeige(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: Scaffold(body: TimelineScreen(library: library)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> abbauen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  double kachelbreite(WidgetTester tester) => tester
      .widget<MonthGroupedAssetGrid>(find.byType(MonthGroupedAssetGrid))
      .kachelbreite;

  group('die Stufen selbst', () {
    test('die Vorgabe ist genau die bisherige Groesse', () {
      // Wer nichts einstellt, sieht das Bisherige - sonst waere aus
      // einer neuen Moeglichkeit eine erzwungene Aenderung geworden.
      expect(zeitleisteKachelbreite(zeitleisteKachelstufeVorgabe),
          timelineGridMaxCrossAxisExtent);
    });

    test('sie steigen und enden an beiden Raendern', () {
      for (var i = 1; i < zeitleisteKachelstufen.length; i++) {
        expect(zeitleisteKachelstufen[i],
            greaterThan(zeitleisteKachelstufen[i - 1]));
      }
      expect(naechsteKachelstufe(0, groesser: false), 0);
      final letzte = zeitleisteKachelstufen.length - 1;
      expect(naechsteKachelstufe(letzte, groesser: true), letzte);
    });

    test('eine Stufe, die es nicht gibt, faellt auf die Vorgabe zurueck', () {
      expect(zeitleisteKachelbreite(-1),
          zeitleisteKachelbreite(zeitleisteKachelstufeVorgabe));
      expect(zeitleisteKachelbreite(99),
          zeitleisteKachelbreite(zeitleisteKachelstufeVorgabe));
    });
  });

  group('kleinere Kacheln, mehr Fotos', () {
    test('bei gleicher Breite passen mehr Spalten hinein', () {
      final gross = timelineColumnsForWidth(1200,
          kachelbreite: zeitleisteKachelstufen.last);
      final klein = timelineColumnsForWidth(1200,
          kachelbreite: zeitleisteKachelstufen.first);
      expect(klein, greaterThan(gross));
    });

    test('und ein Monat wird niedriger', () {
      // Der eigentliche Punkt: Mehr Monate passen ins Bild, weil jeder
      // weniger Platz braucht.
      final gruppe = [for (var i = 0; i < 40; i++) _quadratfoto('f$i')];
      final gross = timelineMonthGroupHeight(gruppe, 1200,
          kachelbreite: zeitleisteKachelstufen.last);
      final klein = timelineMonthGroupHeight(gruppe, 1200,
          kachelbreite: zeitleisteKachelstufen.first);
      expect(klein, lessThan(gross));
    });
  });

  group('die Knoepfe', () {
    testWidgets('verkleinern und vergroessern die Kacheln', (tester) async {
      await zeige(tester);
      final anfang = kachelbreite(tester);

      await tester.tap(find.byIcon(Icons.zoom_out));
      await tester.pump();
      expect(kachelbreite(tester), lessThan(anfang));

      await tester.tap(find.byIcon(Icons.zoom_in));
      await tester.pump();
      expect(kachelbreite(tester), anfang);
      await abbauen(tester);
    });

    testWidgets('an den Enden hoert es auf', (tester) async {
      await zeige(tester);
      for (var i = 0; i < 10; i++) {
        final knopf = tester.widget<IconButton>(find.ancestor(
            of: find.byIcon(Icons.zoom_out),
            matching: find.byType(IconButton)));
        if (knopf.onPressed == null) break;
        await tester.tap(find.byIcon(Icons.zoom_out));
        await tester.pump();
      }
      expect(kachelbreite(tester), zeitleisteKachelstufen.first);
      final knopf = tester.widget<IconButton>(find.ancestor(
          of: find.byIcon(Icons.zoom_out), matching: find.byType(IconButton)));
      expect(knopf.onPressed, isNull);
      await abbauen(tester);
    });

    testWidgets('die Stufe ueberdauert', (tester) async {
      await zeige(tester);
      await tester.tap(find.byIcon(Icons.zoom_out));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(await db.zeitleisteKachelstufeWert(),
          zeitleisteKachelstufeVorgabe - 1);
      await abbauen(tester);

      await zeige(tester);
      expect(kachelbreite(tester),
          zeitleisteKachelbreite(zeitleisteKachelstufeVorgabe - 1));
      await abbauen(tester);
    });

    testWidgets('in der Liste stehen sie nicht', (tester) async {
      // Dieselbe Regel wie bei der Gliederung: In der Liste steht alles
      // untereinander, ein Knopf ohne Wirkung waere irrefuehrend.
      await zeige(tester);
      expect(find.byIcon(Icons.zoom_out), findsOneWidget);
      await tester.tap(find.byIcon(Icons.view_list_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.zoom_out), findsNothing);
      await abbauen(tester);
    });
  });
}
