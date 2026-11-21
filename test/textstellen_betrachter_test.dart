import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/textstellen.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/asset_viewer_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/textrahmen.dart';
import 'package:provider/provider.dart';

/// „Erkannten Text hervorheben“ im Betrachter (KI-098).
///
/// Die Kästen sind als Anteile des Bildes gespeichert und brauchen seine
/// Masse. Die holte der Betrachter nur für die Gesichter oder das
/// Drittel-Raster – mit dem Text allein erschien kein Rahmen.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths pfade;
  late LibraryState bibliothek;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_textstellen_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(wurzel.path, 'lib')),
    );
    bibliothek = LibraryState()
      ..db = db
      ..paths = pfade
      ..backupService = BackupService(db, pfade);
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  testWidgets('die Rahmen erscheinen auch ohne „Gesichter zeigen“', (
    tester,
  ) async {
    final t = lookupAppTexte(const Locale('de'));
    final asset = (await tester.runAsync(() async {
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: 'f1',
              originalFileName: 'f1.jpg',
              relativePath: 'originals/f1.jpg',
              checksum: 'pruef-f1',
              type: 'IMAGE',
              fileCreatedAt: DateTime(2026, 6, 14),
              importedAt: DateTime(2026),
              widthPx: const Value(1000),
              heightPx: const Value(800),
              ocrText: const Value('Zeile Eins\nZeile Zwei'),
              ocrBoxen: Value(
                textstellenNachJson(const [
                  Textstelle(
                    text: 'Zeile Eins',
                    links: 0.1,
                    oben: 0.1,
                    breite: 0.4,
                    hoehe: 0.08,
                  ),
                  Textstelle(
                    text: 'Zeile Zwei',
                    links: 0.1,
                    oben: 0.3,
                    breite: 0.4,
                    hoehe: 0.08,
                  ),
                ]),
              ),
            ),
          );
      return db.assetById('f1');
    }))!;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: bibliothek,
        child: MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          theme: buildDarkTheme(),
          home: AssetViewerScreen(
            assets: [asset],
            initialIndex: 0,
            paths: pfade,
            db: db,
            library: bibliothek,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Textrahmen), findsNothing);

    await tester.tap(find.byTooltip(t.viewerTextZeigen));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(Textrahmen), findsNWidgets(2));
  });
}
