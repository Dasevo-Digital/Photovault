import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/asset_viewer_screen.dart';
import 'package:photo_vault/screens/familienfotos_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';
import 'package:provider/provider.dart';

/// Die Familienfotos sind eine fertig übergebene Liste. Wer im Vollbild
/// ein Foto in den Papierkorb legte oder sperrte, sah es danach weiter im
/// Raster – ein gesperrtes als kaputte Kachel – und konnte es aus dem
/// Papierkorb heraus erneut öffnen.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths pfade;
  late LibraryState bibliothek;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_familienfotos_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(wurzel.path, 'lib')),
    );
    bibliothek = LibraryState()
      ..db = db
      ..paths = pfade
      ..backupService = BackupService(db, pfade);
    for (final id in ['a', 'b']) {
      final vorschau = pfade.absolute('thumbnails/$id.jpg');
      vorschau.parent.createSync(recursive: true);
      vorschau.writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.jpg',
              relativePath: 'originals/$id.jpg',
              checksum: 'pruef-$id',
              type: 'IMAGE',
              fileCreatedAt: DateTime(2017),
              importedAt: DateTime(2017),
              thumbnailRelativePath: Value('thumbnails/$id.jpg'),
            ),
          );
    }
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  testWidgets('ein im Vollbild gelöschtes Foto verschwindet aus dem Raster', (
    tester,
  ) async {
    final fotos = (await tester.runAsync(() => db.assetsByIds(['a', 'b'])))!;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: bibliothek,
        child: MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          theme: buildDarkTheme(),
          home: FamilienfotosScreen(
            library: bibliothek,
            titel: 'Familie',
            assets: fotos,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(AssetThumbnailTile), findsNWidgets(2));

    await tester.tap(find.byType(AssetThumbnailTile).first);
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byType(AssetViewerScreen), findsOneWidget);

    // Was „In den Papierkorb“ im Vollbild tut, danach schliesst es sich.
    await tester.runAsync(() => db.fuehreAus(InDenPapierkorb(['a'])));
    Navigator.of(tester.element(find.byType(AssetViewerScreen))).pop();
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(AssetViewerScreen), findsNothing);
    expect(find.byType(AssetThumbnailTile), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
