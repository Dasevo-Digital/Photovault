import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/face_review_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:provider/provider.dart';

/// Favorisieren und Sperren in der Gesichts-Vollbildansicht.
///
/// Beides gab es im grossen Betrachter, aber nicht hier – und hier ist
/// die Stelle, an der man ein Foto beim Sichten der Gesichter zum ersten
/// Mal in Ruhe ansieht. Wer dann merkt, dass es ein gutes ist (oder eines,
/// das niemanden angeht), musste es sich merken und anderswo wiederfinden.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late LibraryState library;
  late List<AssetData> assets;

  final einPixel = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_gesicht_fav_');
    db = AppDatabase(NativeDatabase.memory());
    final paths =
        await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
    library = LibraryState()
      ..db = db
      ..paths = paths
      ..backupService = BackupService(db, paths);

    for (final id in ['a1', 'a2']) {
      final datei = paths.absolute('originals/$id.jpg');
      datei.parent.createSync(recursive: true);
      datei.writeAsBytesSync(einPixel);
      await db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'c_$id',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 3, 4),
            importedAt: DateTime(2026, 3, 4),
            widthPx: const Value(1000),
            heightPx: const Value(800),
          ));
    }
    assets = await db.assetsByIds(['a1', 'a2']);
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<void> zeige(WidgetTester tester) async {
    await tester.pumpWidget(ChangeNotifierProvider<LibraryState>.value(
      value: library,
      child: MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: FaceReviewScreen(library: library, assets: assets),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('der Favoritenknopf schaltet um und zeigt seinen Zustand',
      (tester) async {
    await zeige(tester);
    expect(find.byTooltip('Als Favorit markieren (F)'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);

    await tester.tap(find.byTooltip('Als Favorit markieren (F)'));
    await tester.pumpAndSettle();

    expect((await db.assetById('a1'))!.isFavorite, isTrue);
    // **Der Teil, der leicht vergessen wird:** Die Liste stammt aus dem
    // aufrufenden Bildschirm; ohne Nachziehen zeigte der Knopf weiter
    // das leere Herz, obwohl die Datenbank schon umgestellt ist.
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byTooltip('Favorit entfernen (F)'), findsOneWidget);

    await tester.tap(find.byTooltip('Favorit entfernen (F)'));
    await tester.pumpAndSettle();
    expect((await db.assetById('a1'))!.isFavorite, isFalse);
  });

  testWidgets('der Favorit gilt dem gezeigten Foto, nicht dem ersten',
      (tester) async {
    // Die Gegenprobe: Nach dem Weiterblättern muss der Knopf das zweite
    // Foto meinen.
    await zeige(tester);
    await tester.tap(find.byTooltip('Nächstes Foto (Pfeil rechts)'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Als Favorit markieren (F)'));
    await tester.pumpAndSettle();

    expect((await db.assetById('a2'))!.isFavorite, isTrue);
    expect((await db.assetById('a1'))!.isFavorite, isFalse);
  });

  testWidgets('der Weg in den gesperrten Ordner steht bereit',
      (tester) async {
    // Ausgeführt wird er hier nicht: Er verlangt eine entsperrte
    // Passphrase über einen Dialog, und das gehört in die Prüfung des
    // Tresors (locked_folder_test.dart). Hier zählt, dass der Weg
    // ueberhaupt von dieser Ansicht aus erreichbar ist – genau das
    // fehlte.
    await zeige(tester);
    expect(find.byTooltip('In gesperrten Ordner verschieben (verschlüsselt)'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('die Taste F haelt, was der Tooltip verspricht',
      (tester) async {
    // Der Tooltip nennt „(F)" – dieselbe Beschriftung wie im grossen
    // Betrachter. Ohne Tastenbindung waere das ein Versprechen, das die
    // Ansicht nicht haelt.
    await zeige(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    expect((await db.assetById('a1'))!.isFavorite, isTrue);
  });
}
