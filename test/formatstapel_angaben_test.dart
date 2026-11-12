import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/asset_info_sheet.dart';
import 'package:provider/provider.dart';

/// Welche Formate in einem Formatstapel liegen, sah man nirgends, und an
/// ein bestimmtes kam man nur über das Auflösen (#374).
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths paths;
  late LibraryState library;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pv_formatangaben_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory(p.join(temp.path, 'l')));
    library = LibraryState()
      ..db = db
      ..paths = paths;
  });

  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  Future<void> lege(String id, String name, int bytes) => db.insertAsset(
    AssetsCompanion.insert(
      id: id,
      relativePath: 'originals/$id${p.extension(name).toLowerCase()}',
      originalFileName: name,
      type: 'IMAGE',
      checksum: id,
      fileCreatedAt: DateTime(2026, 5, 1, 12),
      importedAt: DateTime(2026, 5, 1, 12),
      dateiformat: Value(p.extension(name).substring(1).toLowerCase()),
      fileSizeBytes: Value(bytes),
    ),
  );

  Future<void> zeige(WidgetTester tester, AssetData asset) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryState>.value(
        value: library,
        child: MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          home: Scaffold(
            body: AssetInfoSheet(
              asset: asset,
              db: db,
              paths: paths,
              onUpdated: (_) {},
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('die Angaben nennen die Formate, jedes zum Exportieren', (
    tester,
  ) async {
    await lege('h', 'IMG_1.HEIC', 2 * 1024 * 1024);
    await lege('j', 'IMG_1.JPG', 3 * 1024 * 1024);
    await lege('r', 'IMG_1.CR3', 25 * 1024 * 1024);
    await db.stapleFormate();
    final titel = (await db.assetById('h'))!;
    expect(titel.isStackCover, isTrue);
    await zeige(tester, titel);

    expect(find.textContaining('Formate: HEIC, CR3, JPG'), findsOneWidget);
    expect(find.byType(ActionChip), findsNWidgets(3));
    expect(find.text('CR3 · 25.0 MB'), findsOneWidget);
  });

  testWidgets('Serien und andere Stapel bleiben, wie sie waren', (
    tester,
  ) async {
    await lege('a', 'A.JPG', 1000);
    await lege('b', 'B.JPG', 1000);
    await db.fuehreAus(const VariantenBilden('v', ['a', 'b'], 'a'));
    await zeige(tester, (await db.assetById('a'))!);

    expect(find.textContaining('Formate:'), findsNothing);
    expect(find.byType(ActionChip), findsNothing);
  });
}
