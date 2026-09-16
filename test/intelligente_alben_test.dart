import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/albums_screen.dart';
import 'package:photo_vault/screens/search_screen.dart';
import 'package:photo_vault/services/search_filters.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';

/// **„Intelligentes Album: geht nicht."**
///
/// Es gab sie – aber nur als Chipreihe UNTER dem Suchfeld, also erst,
/// wenn man ohnehin schon in der Suche stand. Wer im Albenreiter nach
/// einem intelligenten Album sah, fand nichts, und nichts sagte ihm,
/// dass es so etwas gibt.
///
/// Jetzt stehen die gespeicherten Suchen dort als eigene Kacheln, und
/// ein Tipp darauf fuehrt in die Suche mit genau diesen Filtern – das
/// ist der Punkt eines intelligenten Albums: Seine Treffer entstehen
/// jedes Mal neu.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_klugalbum_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths =
          await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')));
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> aufnahme(String id, {String type = 'IMAGE'}) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'c_$id',
            type: type,
            fileCreatedAt: DateTime(2026, 1, 1),
            importedAt: DateTime(2026, 1, 1),
          ));

  Future<void> takte(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> zeige(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: AlbumsScreen(library: library),
    ));
    await takte(tester);
  }

  testWidgets('ohne alles sagt der Reiter auch, was ein kluges Album ist',
      (tester) async {
    await tester.runAsync(() async {
      await zeige(tester);
      expect(find.text('Noch keine Alben vorhanden.'), findsOneWidget);
      expect(find.textContaining('Ein intelligentes Album ist eine gespeicherte Suche'),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  testWidgets('eine gespeicherte Suche steht als Kachel im Albenreiter',
      (tester) async {
    await tester.runAsync(() async {
      await aufnahme('f1');
      await aufnahme('v1', type: 'VIDEO');
      await db.createSavedSearch('s1', 'Nur Videos',
          const SearchFilters(mediaType: MediaTypeFilter.video));
      await zeige(tester);

      expect(find.text('Nur Videos'), findsOneWidget);
      // Nur eine Gruppe, also keine Ueberschriften - eine einzelne
      // Ueberschrift ueber allem sagt nichts.
      expect(find.text('Intelligente Alben'), findsNothing);

      // Antippen fuehrt in die Suche, mit genau diesen Filtern, und die
      // laeuft von selbst los.
      await tester.tapAt(tester.getCenter(find.text('Nur Videos')));
      await takte(tester);
      await takte(tester);

      expect(find.byType(SearchScreen), findsOneWidget);
      final kacheln = tester
          .widgetList<AssetThumbnailTile>(find.byType(AssetThumbnailTile))
          .map((k) => k.asset.id)
          .toList();
      expect(kacheln, ['v1'], reason: 'nur das Video, nicht das Foto');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  testWidgets('neben gewoehnlichen Alben bekommen beide eine Ueberschrift',
      (tester) async {
    await tester.runAsync(() async {
      await db.createAlbum(AlbumsCompanion.insert(
          id: 'a1', name: 'Urlaub', createdAt: DateTime(2026, 1, 1)));
      await db.createSavedSearch('s1', 'Nur Videos',
          const SearchFilters(mediaType: MediaTypeFilter.video));
      await zeige(tester);

      expect(find.text('Intelligente Alben'), findsOneWidget);
      expect(find.text('Alben'), findsOneWidget);
      expect(find.text('Urlaub'), findsOneWidget);
      expect(find.text('Nur Videos'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}
