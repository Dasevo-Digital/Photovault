import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:flutter_map/flutter_map.dart';
import 'package:photo_vault/widgets/asset_info_sheet.dart';
import 'package:photo_vault/widgets/color_label_picker.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';
import 'package:photo_vault/widgets/star_rating.dart';
import 'package:provider/provider.dart';

/// Die kleine Karte der Info-Leiste holt keine Kacheln aus dem Netz.
class _LeereKacheln extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_pixel);
}

final _pixel = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0B, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00,
  0x00, 0x05, 0x00, 0x01, 0x7A, 0x5E, 0xAB, 0x3F, 0x00, 0x00, 0x00, 0x00,
  0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// Die Tasten der Einzelansicht und die offene Info-Leiste.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths pfade;
  late LibraryState bibliothek;
  late List<AssetData> fotos;
  final de = AppTexteDe();

  setUp(() async {
    kachelAnbieterFuerTest = _LeereKacheln();
    wurzel = Directory.systemTemp.createTempSync('pv_tasten_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(wurzel.path, 'lib')),
    );
    bibliothek = LibraryState()
      ..db = db
      ..paths = pfade
      ..backupService = BackupService(db, pfade);
    for (final id in ['a', 'b']) {
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
      for (final id in ['a', 'b']) (await db.assetById(id))!,
    ];
  });

  tearDown(() async {
    kachelAnbieterFuerTest = null;
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> warte(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> zeigeMitInfo(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
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
            onToggleFavorite: (a) async {
              await db.setFavorite(a.id, !a.isFavorite);
            },
          ),
        ),
      ),
    );
    await warte(tester);
    await tester.tap(find.byTooltip(de.viewerInfo));
    await warte(tester);
    expect(find.byType(AssetInfoSheet), findsOneWidget);
  }

  Future<AssetData> aufnahme(WidgetTester tester, String id) async =>
      (await tester.runAsync(() => db.assetById(id)))!;

  int seite(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView)).controller!.page!.round();

  testWidgets('Tippen in der Info-Leiste löst keine Tastenkürzel aus', (
    tester,
  ) async {
    await zeigeMitInfo(tester);
    final feld = find.descendant(
      of: find.byType(AssetInfoSheet),
      matching: find.widgetWithText(TextField, de.infoBeschreibungHinzufuegen),
    );
    await tester.tap(feld);
    await tester.pump();
    for (final taste in [
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.keyF,
      LogicalKeyboardKey.space,
    ]) {
      final erledigt = await tester.sendKeyEvent(taste);
      expect(erledigt, isFalse, reason: '$taste gehört dem Feld');
    }
    // Den Pfeil nimmt das Feld selbst (Schreibmarke) – blättern darf er
    // nicht.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await warte(tester);

    final a = await aufnahme(tester, 'a');
    expect(a.rating, 0);
    expect(a.colorLabel, isNull);
    expect(a.isFavorite, isFalse);
    expect(seite(tester), 0, reason: 'blättert nicht weiter');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Bewertung und Farbmarke per Taste erscheinen in der offenen '
      'Info-Leiste', (tester) async {
    await zeigeMitInfo(tester);
    int sterne() => tester
        .widget<StarRating>(
          find.descendant(
            of: find.byType(AssetInfoSheet),
            matching: find.byType(StarRating),
          ),
        )
        .value;
    String? marke() => tester
        .widget<ColorLabelPicker>(
          find.descendant(
            of: find.byType(AssetInfoSheet),
            matching: find.byType(ColorLabelPicker),
          ),
        )
        .value;
    expect(sterne(), 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await warte(tester);
    expect((await aufnahme(tester, 'a')).rating, 4);
    expect(sterne(), 4);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit7);
    await warte(tester);
    expect(marke(), 'yellow');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit7);
    await warte(tester);
    expect(marke(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await warte(tester);
    expect(sterne(), 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
