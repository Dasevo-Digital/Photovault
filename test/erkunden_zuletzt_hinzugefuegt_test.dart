import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/explore_screen.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';

/// **„Zuletzt hinzugefügte Fotos“ ordnet nach der Importzeit.**
///
/// Der Streifen kam aus der Zeitleiste und ordnete damit nach dem
/// Aufnahmedatum: Ein gerade eingelesenes Foto von 2001 stand hinten.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_erk_neu_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'l')),
      );
    Future<void> foto(String id, DateTime aufnahme, DateTime import) => db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'o/$id.jpg',
            checksum: 'c$id',
            type: 'IMAGE',
            fileCreatedAt: aufnahme,
            importedAt: import,
            thumbnailRelativePath: Value('t/$id.jpg'),
          ),
        );
    for (var i = 0; i < 3; i++) {
      await foto('neu$i', DateTime(2025, 6, 1 + i), DateTime(2026, 1, 1 + i));
    }
    // Zuletzt eingelesen, aber 2001 aufgenommen.
    await foto('altimport', DateTime(2001, 5, 1), DateTime(2026, 2, 1));
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  testWidgets('das zuletzt importierte alte Foto steht vorn', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: Scaffold(body: ExploreScreen(library: library)),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    final namen = [
      for (final e in find.byType(AssetThumbnailTile).evaluate())
        (e.widget as AssetThumbnailTile).asset.originalFileName,
    ];
    expect(namen, ['altimport.jpg', 'neu2.jpg', 'neu1.jpg', 'neu0.jpg']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
