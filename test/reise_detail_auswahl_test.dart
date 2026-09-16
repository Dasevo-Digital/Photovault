import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/reise_detail_screen.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';
import 'package:photo_vault/widgets/meldungsfenster.dart';
import 'package:photo_vault/widgets/zuordnung_auswahlleiste.dart';

/// Fotos einer Reise auswaehlen und herausnehmen.
///
/// **Herausnehmen ist kein Loeschen**, und das ist der Punkt: Das Foto
/// bleibt in der Bibliothek, es gehoert nur nicht mehr zu dieser Reise.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_reised_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths =
          await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')));
  });

  tearDown(() async {
    melde.verlaufLeeren();
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<ReisenData> anlegen() async {
    for (var i = 0; i < 5; i++) {
      await db.into(db.assets).insert(AssetsCompanion.insert(
            id: 'r$i',
            originalFileName: 'r$i.jpg',
            relativePath: 'originals/r$i.jpg',
            checksum: 'pruef-r$i',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 6, 14, 9 + i),
            importedAt: DateTime(2026),
            latitude: const Value(41.9),
            longitude: const Value(12.5),
            locationCity: const Value('Roma'),
          ));
    }
    await db.reiseAnlegen(
      ReisenCompanion.insert(
        id: 'reise1',
        name: 'Rom',
        von: DateTime(2026, 6, 14, 9),
        bis: DateTime(2026, 6, 14, 13),
        angelegtAm: DateTime(2026, 7, 1),
      ),
      ['r0', 'r1', 'r2', 'r3', 'r4'],
    );
    return (await db.alleReisen()).single;
  }

  Future<void> zeige(WidgetTester tester, ReisenData reise) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      builder: (context, kind) => mitMeldungen(kind),
      home: ReiseDetailScreen(library: library, reise: reise),
    ));
    await tester.pumpAndSettle();
  }

  /// Waehlt ueber das Bildmenue aus – der lange Druck oeffnet hier das
  /// Menue, weil es das schon vorher gab (Titelbild setzen).
  Future<void> waehle(WidgetTester tester, int i) async {
    await tester.longPress(find.byType(AssetThumbnailTile).at(i));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auswählen'));
    await tester.pumpAndSettle();
  }

  testWidgets('ohne Auswahl gibt es keine Leiste', (tester) async {
    await zeige(tester, await anlegen());
    expect(find.byType(ZuordnungAuswahlleiste), findsNothing);
  });

  testWidgets('das Bildmenue kann auswaehlen, ohne das Titelbild zu verlieren',
      (tester) async {
    await zeige(tester, await anlegen());
    await tester.longPress(find.byType(AssetThumbnailTile).first);
    await tester.pumpAndSettle();
    // Beide Wege stehen im selben Menue.
    expect(find.text('Auswählen'), findsOneWidget);
    expect(find.text('Als Titelbild'), findsOneWidget);
  });

  testWidgets('auswaehlen zeigt die Leiste mit der Reise-Beschriftung',
      (tester) async {
    await zeige(tester, await anlegen());
    await waehle(tester, 0);
    expect(find.byType(ZuordnungAuswahlleiste), findsOneWidget);
    expect(find.text('1 ausgewählt'), findsOneWidget);
    expect(find.text('Aus der Reise entfernen'), findsOneWidget);
  });

  testWidgets('bei laufender Auswahl waehlt ein Tipp weitere dazu',
      (tester) async {
    await zeige(tester, await anlegen());
    await waehle(tester, 0);
    await tester.tap(find.byType(AssetThumbnailTile).at(1));
    await tester.pumpAndSettle();
    expect(find.text('2 ausgewählt'), findsOneWidget);
  });

  testWidgets('der Knopf nimmt sie wirklich aus der Reise', (tester) async {
    final reise = await anlegen();
    await zeige(tester, reise);
    await waehle(tester, 0);
    await tester.tap(find.byType(AssetThumbnailTile).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aus der Reise entfernen'));
    await tester.pumpAndSettle();

    final uebrig = await db.zuordnungenDerReise(reise.id);
    expect(uebrig, hasLength(3));
    expect(uebrig, isNot(contains('r0')));
    expect(uebrig, isNot(contains('r1')));
    // Die Fotos bleiben in der Bibliothek.
    expect(await db.select(db.assets).get(), hasLength(5));
    expect(find.byType(ZuordnungAuswahlleiste), findsNothing);
  });

  testWidgets('eine gesperrte Zuordnung ueberlebt das Herausnehmen',
      (tester) async {
    // An der gewachsenen Bibliothek standen 33 Zuordnungen genau so auf
    // dem Spiel: Die Liste im Bild laesst Gesperrtes weg, die Zuordnung
    // besteht aber.
    final reise = await anlegen();
    await (db.update(db.assets)..where((t) => t.id.equals('r4')))
        .write(const AssetsCompanion(isLocked: Value(true)));
    await zeige(tester, reise);
    expect(find.byType(AssetThumbnailTile), findsNWidgets(4));

    await waehle(tester, 0);
    await tester.tap(find.text('Aus der Reise entfernen'));
    await tester.pumpAndSettle();

    final uebrig = await db.zuordnungenDerReise(reise.id);
    expect(uebrig, contains('r4'),
        reason: 'die gesperrte Zuordnung darf nicht mit verschwinden');
    expect(uebrig, hasLength(4));
  });

  testWidgets('Auswahl aufheben laesst alles stehen', (tester) async {
    final reise = await anlegen();
    await zeige(tester, reise);
    await waehle(tester, 0);
    await tester.tap(find.byTooltip('Auswahl aufheben'));
    await tester.pumpAndSettle();
    expect(find.byType(ZuordnungAuswahlleiste), findsNothing);
    expect(await db.zuordnungenDerReise(reise.id), hasLength(5));
  });

  testWidgets('der Knopf zum Hinzufuegen heisst auch so', (tester) async {
    await zeige(tester, await anlegen());
    expect(find.byTooltip('Fotos hinzufügen'), findsOneWidget);
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsOneWidget);
  });
}
