import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/asset_viewer_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:provider/provider.dart';

/// #428: Die Diaschau blätterte unter einer Rückfrage weiter, und die
/// Aktion las das gezeigte Foto erst nach der Rückfrage. Bestätigt wurde
/// das Löschen von Foto 1, in den Papierkorb ging Foto 2.
void main() {
  final de = lookupAppTexte(const Locale('de'));
  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths pfade;
  late LibraryState bibliothek;
  late List<AssetData> fotos;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_diaschau_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(wurzel.path, 'lib')),
    );
    bibliothek = LibraryState()
      ..db = db
      ..paths = pfade
      ..backupService = BackupService(db, pfade);
    // Je ein anderer Tag: Der Titel der Ansicht zeigt das Datum und
    // verrät so, welches Foto zu sehen ist.
    for (final (i, id) in ['a', 'b', 'c'].indexed) {
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.jpg',
              relativePath: 'originals/$id.jpg',
              checksum: 'pruef-$id',
              type: 'IMAGE',
              fileCreatedAt: DateTime(2026, 6, 14 + i),
              importedAt: DateTime(2026),
            ),
          );
    }
    fotos = [
      for (final id in ['a', 'b', 'c']) (await db.assetById(id))!,
    ];
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<List<String>> zeige(WidgetTester tester) async {
    final geloescht = <String>[];
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: bibliothek,
        child: MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          theme: buildDarkTheme(),
          home: AssetViewerScreen(
            assets: fotos,
            initialIndex: 0,
            paths: pfade,
            db: db,
            library: bibliothek,
            onDelete: (a) async => geloescht.add(a.id),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip(de.viewerDiaschauStarten));
    await tester.pump();
    return geloescht;
  }

  /// Lässt [sekunden] vergehen, in kleinen Schritten, damit auch das
  /// Blättern selbst durchläuft.
  Future<void> vergehen(WidgetTester tester, int sekunden) async {
    for (var i = 0; i < sekunden * 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('die Diaschau blättert selbst weiter', (tester) async {
    await zeige(tester);
    expect(find.text('14.6.2026'), findsOneWidget);
    await vergehen(tester, 5);
    expect(find.text('15.6.2026'), findsOneWidget);
  });

  testWidgets('⌫ bei laufender Diaschau löscht das Foto, nach dem gefragt '
      'wurde', (tester) async {
    final geloescht = await zeige(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    await vergehen(tester, 9);
    expect(find.text('14.6.2026'), findsOneWidget, reason: 'nicht geblättert');

    await tester.tap(find.widgetWithText(FilledButton, de.allgLoeschen));
    await vergehen(tester, 1);
    expect(geloescht, ['a']);
    // Danach steht die Diaschau: Löschen ist eine bewusste Handlung.
    await vergehen(tester, 9);
    expect(find.text('15.6.2026'), findsOneWidget);
    expect(find.byTooltip(de.viewerDiaschauStarten), findsOneWidget);
  });

  testWidgets('der Papierkorb-Knopf bei laufender Diaschau trifft das '
      'gefragte Foto', (tester) async {
    final geloescht = await zeige(tester);
    await tester.tap(find.byTooltip(de.viewerInPapierkorb));
    await tester.pump();
    await vergehen(tester, 9);
    await tester.tap(find.widgetWithText(FilledButton, de.allgLoeschen));
    await vergehen(tester, 1);
    expect(geloescht, ['a']);
  });

  testWidgets('wer in einem Feld der Ansicht schreibt, hält die Diaschau an', (
    tester,
  ) async {
    await zeige(tester);
    await tester.tap(find.byTooltip(de.viewerInfo));
    await tester.pump();
    final feld = find.byType(TextField).first;
    await tester.tap(feld);
    await tester.pump();
    await vergehen(tester, 9);
    expect(find.text('14.6.2026'), findsOneWidget, reason: 'nicht geblättert');

    // Ohne Fokus geht es von selbst weiter.
    FocusManager.instance.primaryFocus?.unfocus();
    await vergehen(tester, 5);
    expect(find.text('15.6.2026'), findsOneWidget);
  });
}
