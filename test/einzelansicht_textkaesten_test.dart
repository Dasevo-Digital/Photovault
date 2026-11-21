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
import 'package:photo_vault/screens/asset_viewer_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/textrahmen.dart';
import 'package:provider/provider.dart';

/// **„Erkannten Text hervorheben“ zeigte keine Kästen.**
///
/// Die Kästen brauchen die Masse des Bildes – ohne sie ist der Anteil 0,1
/// kein Ort. Geholt wurden die Masse aber nur für das Drittel-Raster und
/// die Gesichtsrahmen; wer allein den Text einschaltete, sah nichts.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths pfade;
  late LibraryState bibliothek;
  final de = AppTexteDe();

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_textkaesten_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(wurzel.path, 'lib')),
    );
    bibliothek = LibraryState()
      ..db = db
      ..paths = pfade
      ..backupService = BackupService(db, pfade);
    final datei = pfade.absolute('originals/schild.jpg');
    datei.parent.createSync(recursive: true);
    datei.writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'schild',
            originalFileName: 'schild.jpg',
            relativePath: 'originals/schild.jpg',
            checksum: 'pruef-schild',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2025),
            importedAt: DateTime(2025),
            widthPx: const Value(1200),
            heightPx: const Value(900),
            ocrScanned: const Value(true),
            ocrText: const Value('BAHNHOF'),
            ocrBoxen: const Value(
              '[{"t":"BAHNHOF","x":0.1,"y":0.2,"b":0.4,"h":0.1}]',
            ),
          ),
        );
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  testWidgets('die Kästen erscheinen, auch ohne Gesichter und Raster', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final foto = (await tester.runAsync(() => db.assetById('schild')))!;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: bibliothek,
        child: MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          theme: buildDarkTheme(),
          home: AssetViewerScreen(
            assets: [foto],
            initialIndex: 0,
            paths: pfade,
            db: db,
            library: bibliothek,
          ),
        ),
      ),
    );
    Future<void> warte() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    await warte();
    expect(find.byType(Textrahmen), findsNothing);
    await tester.tap(find.byTooltip(de.viewerTextZeigen));
    await warte();
    expect(find.byType(Textrahmen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
