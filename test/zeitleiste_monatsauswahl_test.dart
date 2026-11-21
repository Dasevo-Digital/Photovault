import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/l10n/app_localizations_de.dart';
import 'package:photo_vault/screens/timeline_screen.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/month_grouped_asset_grid.dart';

/// **Die Monatsüberschrift wählt den ganzen Monat.**
///
/// Die Zeitleiste lädt die neuesten 600 Fotos. Endet das Ladefenster
/// mitten in einem Monat, wählte dessen Überschrift nur die geladenen –
/// und zeigte ihn trotzdem als ganz gewählt.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;
  final de = AppTexteDe();

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_monatswahl_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'l')),
      );
    AssetsCompanion foto(String id, DateTime wann) => AssetsCompanion.insert(
      id: id,
      originalFileName: '$id.jpg',
      relativePath: 'o/$id.jpg',
      checksum: 'c$id',
      type: 'IMAGE',
      fileCreatedAt: wann,
      importedAt: DateTime(2026),
      thumbnailRelativePath: Value('t/$id.jpg'),
    );
    await db.batch(
      (b) => b.insertAll(db.assets, [
        // 590 neuere Fotos von Februar bis Juni …
        for (var i = 0; i < 590; i++)
          foto('neu$i', DateTime(2026, 2 + i % 5, 1 + i % 27, 12, i % 60)),
        // … und 60 aus dem Januar: Nur zehn davon liegen im Ladefenster.
        for (var i = 0; i < 60; i++)
          foto('jan$i', DateTime(2026, 1, 1 + i % 28, 10, i % 60)),
      ]),
    );
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  testWidgets('auch die Fotos ausserhalb des Ladefensters', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: Scaffold(body: TimelineScreen(library: library)),
      ),
    );
    Future<void> warte() async {
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await warte();
    final raster = tester.widget<MonthGroupedAssetGrid>(
      find.byType(MonthGroupedAssetGrid),
    );
    expect(raster.assets, hasLength(600));
    final januar = [
      for (final a in raster.assets)
        if (a.fileCreatedAt.month == 1) a,
    ];
    expect(januar, hasLength(10));

    raster.onHeaderTap!(januar);
    await warte();
    expect(find.text(de.auswAnzahl(60)), findsOneWidget);

    // Ein zweiter Klick nimmt den ganzen Monat wieder heraus.
    tester
        .widget<MonthGroupedAssetGrid>(find.byType(MonthGroupedAssetGrid))
        .onHeaderTap!(januar);
    await warte();
    expect(find.text(de.auswAnzahl(60)), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
