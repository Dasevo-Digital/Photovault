import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:kern/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/timeline_screen.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/month_grouped_asset_grid.dart';

/// **„Foto in der Timeline anzeigen“ aus einem anderen Bereich.**
///
/// Die Hülle reicht den Wunsch nur in einem einzigen Aufbau herein: Sie
/// verbraucht ihn und schaltet erst danach auf die Zeitleiste um, der
/// nächste Aufbau bringt `null`. Das Raster bekam das Ziel deshalb nie
/// zu sehen, wenn man aus der Suche oder dem Archiv kam – weder Sprung
/// noch Meldung „nicht gefunden“.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_sprung_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'l')),
      );
    for (var monat = 1; monat <= 6; monat++) {
      for (var k = 0; k < 4; k++) {
        final id = 'm${monat}_$k';
        await db
            .into(db.assets)
            .insert(
              AssetsCompanion.insert(
                id: id,
                originalFileName: '$id.jpg',
                relativePath: 'o/$id.jpg',
                checksum: 'c$id',
                type: 'IMAGE',
                fileCreatedAt: DateTime(2026, monat, 5 + k),
                importedAt: DateTime(2026),
                thumbnailRelativePath: Value('t/$id.jpg'),
              ),
            );
      }
    }
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> zeige(WidgetTester tester, {String? ziel}) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: Scaffold(
          body: TimelineScreen(library: library, highlightAssetId: ziel),
        ),
      ),
    );
  }

  String? rasterZiel(WidgetTester tester) => tester
      .widget<MonthGroupedAssetGrid>(find.byType(MonthGroupedAssetGrid))
      .highlightAssetId;

  testWidgets('das Ziel kommt im Raster an, auch wenn der nächste Aufbau '
      'keins mehr bringt', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Erster Aufbau mit dem Wunsch, gleich danach einer ohne – so, wie
    // die Hülle umschaltet.
    await zeige(tester, ziel: 'm2_1');
    await zeige(tester);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(MonthGroupedAssetGrid), findsOneWidget);
    expect(rasterZiel(tester), 'm2_1');

    // Nach dem Blinken ist der Wunsch erledigt.
    await tester.pump(const Duration(seconds: 4));
    expect(rasterZiel(tester), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
