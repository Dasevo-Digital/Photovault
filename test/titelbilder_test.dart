import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/albums_screen.dart';
import 'package:photo_vault/screens/calendar_screen.dart';
import 'package:photo_vault/screens/reisen_screen.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';
import 'package:photo_vault/widgets/ortskachel.dart';

/// #433: Titelbilder wurden einmal geholt und nie wieder. Ohne Schlüssel
/// wanderten sie beim Wegfallen einer Kachel auf die nächste, und was sich
/// am Inhalt änderte, kam nicht an.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_titelbild_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'lib')),
      );
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> aufnahme(String id, DateTime wann) => db
      .into(db.assets)
      .insert(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'pruef-$id',
          type: 'IMAGE',
          fileCreatedAt: wann,
          importedAt: DateTime(2026),
          thumbnailRelativePath: Value('thumbs/$id.jpg'),
        ),
      );

  Future<void> zeige(WidgetTester tester, Widget was) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: was,
      ),
    );
    await warte(tester);
  }

  Future<void> abbauen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Die Vorschaubilder, die gerade dastehen, als Dateinamen.
  List<String> bilder(WidgetTester tester) => [
    for (final bild in tester.widgetList<Image>(find.byType(Image)))
      switch (bild.image) {
        ResizeImage(imageProvider: final FileImage f) => p.basename(
          f.file.path,
        ),
        final FileImage f => p.basename(f.file.path),
        _ => '?',
      },
  ];

  testWidgets('Monatsübersicht: Kacheln behalten ihr Bild, und ein neueres '
      'Foto kommt an', (tester) async {
    await aufnahme('maerz', DateTime(2026, 3, 5, 10));
    await aufnahme('februar', DateTime(2026, 2, 5, 10));
    await zeige(tester, MonatsuebersichtScreen(library: library, jahr: 2026));
    expect(bilder(tester), ['maerz.jpg', 'februar.jpg']);

    // Der März wird leer: Die Februar-Kachel rückt an die erste Stelle.
    await tester.runAsync(() => db.fuehreAus(InDenPapierkorb(['maerz'])));
    await warte(tester);
    expect(find.text('März'), findsNothing);
    expect(bilder(tester), ['februar.jpg'], reason: 'nicht das Bild des März');

    // Ein neueres Foto im Februar wird sein Titelbild.
    await tester.runAsync(() => aufnahme('neu', DateTime(2026, 2, 20, 10)));
    await warte(tester);
    expect(bilder(tester), ['neu.jpg']);
    await abbauen(tester);
  });

  testWidgets('Reisekachel: ein neu gewähltes Titelbild kommt an', (
    tester,
  ) async {
    await aufnahme('a', DateTime(2026, 5, 1, 10));
    await aufnahme('b', DateTime(2026, 5, 2, 10));
    ReisenData reise(String titelbild) => ReisenData(
      id: 'r1',
      name: 'Küste',
      von: DateTime(2026, 5, 1),
      bis: DateTime(2026, 5, 3),
      art: 'urlaub',
      titelbildAssetId: titelbild,
      angelegtAm: DateTime(2026, 5, 4),
    );
    Widget kachel(String titelbild) => Scaffold(
      body: SizedBox(
        width: 300,
        height: 240,
        child: Reisekachel(
          key: const ValueKey('r1'),
          reise: reise(titelbild),
          library: library,
          ort: null,
          onTippen: () {},
        ),
      ),
    );
    await zeige(tester, kachel('a'));
    expect(tester.widget<Ortskachel>(find.byType(Ortskachel)).bild?.id, 'a');

    await zeige(tester, kachel('b'));
    expect(tester.widget<Ortskachel>(find.byType(Ortskachel)).bild?.id, 'b');
    await abbauen(tester);
  });

  testWidgets('Alben: nach der Rückkehr aus einem Album stimmt das '
      'Titelbild', (tester) async {
    await aufnahme('a', DateTime(2026, 5, 1, 10));
    await db.fuehreAus(AlbumAnlegen('alb', 'Leer', DateTime(2026)));
    await zeige(tester, AlbumsScreen(library: library));
    expect(find.byType(AssetThumbnailTile), findsNothing);

    await tester.tap(find.text('Leer'));
    await warte(tester);
    // Im Album gefüllt, wie über „Fotos hinzufügen“.
    await tester.runAsync(() => db.fuehreAus(const AlbumFuellen('alb', ['a'])));
    await warte(tester);
    Navigator.of(tester.element(find.text('Leer').last)).pop();
    await warte(tester);
    await warte(tester);
    expect(find.byType(AssetThumbnailTile), findsOneWidget);
    await abbauen(tester);
  });
}

Future<void> warte(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
