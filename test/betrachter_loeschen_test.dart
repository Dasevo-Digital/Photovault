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
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:provider/provider.dart';

/// **Eine gehaltene Taste leerte die Sichtung.** Delete wiederholt sich
/// beim Halten, und in der Sichtung fragt die Taste bewusst nicht nach. Dazu
/// hing der Zustand einer Seite am Index, und ein Wechsel der Datei zeigte
/// weiter das alte Bild: Gesehen wurde das eine Foto, gelöscht das nächste.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths pfade;
  late LibraryState bibliothek;
  late List<AssetData> fotos;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_betrachter_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(wurzel.path, 'lib')),
    );
    bibliothek = LibraryState()
      ..db = db
      ..paths = pfade
      ..backupService = BackupService(db, pfade);
    for (final id in ['a', 'b', 'c']) {
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.jpg',
              relativePath: 'originals/$id.jpg',
              checksum: 'pruef-$id',
              type: 'IMAGE',
              fileCreatedAt: DateTime(2026, 6, 14),
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

  Future<void> zeige(WidgetTester tester) async {
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
            cullingMode: true,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> warte(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }

  Future<List<String>> imPapierkorb(WidgetTester tester) async {
    final alle = await tester.runAsync(() => db.select(db.assets).get());
    return [
      for (final a in alle!)
        if (a.isTrashed) a.id,
    ];
  }

  int? seiten(WidgetTester tester) => tester
      .widget<PageView>(find.byType(PageView))
      .childrenDelegate
      .estimatedChildCount;

  testWidgets('die gehaltene Taste löscht genau ein Foto', (tester) async {
    await zeige(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.delete);
    await warte(tester);
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.delete);
      await warte(tester);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.delete);
    await warte(tester);

    expect(await imPapierkorb(tester), ['a']);
  });

  testWidgets('die Meldung holt das Foto zurück', (tester) async {
    await zeige(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.delete);
    await warte(tester);
    expect(await imPapierkorb(tester), ['a']);
    expect(seiten(tester), 2);

    final meldung = melde.verlauf.first;
    expect(meldung.text, 'In den Papierkorb gelegt.');
    meldung.aktion!.beiDruck();
    await warte(tester);
    await warte(tester);

    expect(await imPapierkorb(tester), isEmpty);
    expect(seiten(tester), 3, reason: 'wieder an seinem Platz');
  });
}
