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
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/meldungsfenster.dart';
import 'package:photo_vault/widgets/panorama_360_view.dart';
import 'package:provider/provider.dart';

/// **Die Glocke lag über den Knöpfen der 360°-Ansicht.**
///
/// Solange es ungelesene Meldungen gibt, steht die Glocke des
/// Meldungsfensters oben rechts unter der Titelleiste. Genau dort lagen
/// in der Einzelansicht die Knöpfe „Flaches Schwenken“ und „Flache
/// Vorschau“; ein Klick öffnete den Meldungsverlauf.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths pfade;
  late LibraryState bibliothek;
  late Meldungsdienst dienst;
  final de = AppTexteDe();

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_glocke_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(wurzel.path, 'lib')),
    );
    bibliothek = LibraryState()
      ..db = db
      ..paths = pfade
      ..backupService = BackupService(db, pfade);
    dienst = Meldungsdienst();
    final datei = pfade.absolute('originals/kugel.jpg');
    datei.parent.createSync(recursive: true);
    datei.writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'kugel',
            originalFileName: 'kugel.jpg',
            relativePath: 'originals/kugel.jpg',
            checksum: 'pruef-kugel',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2025),
            importedAt: DateTime(2025),
            widthPx: const Value(2000),
            heightPx: const Value(1000),
          ),
        );
  });

  tearDown(() async {
    dienst.dispose();
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  testWidgets('die Knöpfe der Kugel bleiben bei ungelesener Meldung '
      'bedienbar', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final foto = (await tester.runAsync(() => db.assetById('kugel')))!;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: bibliothek,
        child: MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          theme: buildDarkTheme(),
          builder: (context, kind) => mitMeldungen(kind, dienst: dienst),
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
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.byType(Panorama360View), findsOneWidget);

    dienst.hinweis('Probemeldung');
    await tester.pump();
    dienst.alleSchliessen();
    await tester.pump();
    expect(dienst.ungelesen, greaterThan(0));
    expect(find.byTooltip(de.meldungenGlocke), findsOneWidget);

    final knopf = find.byTooltip(de.viewerFlacheVorschau);
    await tester.tapAt(tester.getCenter(knopf));
    await tester.pump();
    expect(
      find.byType(Panorama360View),
      findsNothing,
      reason: 'flache Vorschau statt Meldungsverlauf',
    );
    expect(find.text(de.meldungenVerlaufLeeren), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });
}
