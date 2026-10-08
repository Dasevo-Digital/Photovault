import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/meldungsfenster.dart';
import 'package:photo_vault/widgets/selection_action_bar.dart';

/// Rückgängig für die Auswahlleiste: Zurück kommt der Zustand je Foto,
/// nicht ein gemeinsamer Wert.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
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
              fileCreatedAt: DateTime(2026),
              importedAt: DateTime(2026),
            ),
          );
    }
  });

  tearDown(() => db.close());

  Future<AssetData> aufnahme(String id) =>
      (db.select(db.assets)..where((t) => t.id.equals(id))).getSingle();

  test('Bewertung: jedes Foto bekommt seine eigene zurück', () async {
    await db.setRating('a', 5);
    await db.setColorLabel('b', 'rot');
    await db.setFavoriteBulk(['c'], true);
    final vorher = await db.markierungen(['a', 'b', 'c']);
    await db.setRatingBulk(['a', 'b', 'c'], 2);
    await db.setColorLabelBulk(['a', 'b', 'c'], 'gruen');
    await db.setFavoriteBulk(['a', 'b', 'c'], true);

    await db.setzeMarkierungen(vorher);
    expect((await aufnahme('a')).rating, 5);
    expect((await aufnahme('b')).rating, 0);
    expect((await aufnahme('b')).colorLabel, 'rot');
    expect((await aufnahme('a')).colorLabel, isNull);
    expect((await aufnahme('c')).isFavorite, isTrue);
    expect((await aufnahme('a')).isFavorite, isFalse);
  });

  test(
    'Schlagwort: nur wo es neu war, und ein neues verschwindet ganz',
    () async {
      await db.tagAssetsBulk(['a'], 'Urlaub');
      final schon = await db.tragenSchlagwort(['a', 'b'], 'Urlaub');
      expect(schon, {'a'});
      await db.tagAssetsBulk(['a', 'b'], 'Urlaub');
      await db.nimmSchlagwortAb(['b'], 'Urlaub');
      expect(await db.tragenSchlagwort(['a', 'b'], 'Urlaub'), {'a'});

      await db.tagAssetsBulk(['c'], 'Neu');
      await db.nimmSchlagwortAb(['c'], 'Neu');
      final tags = await db.select(db.tags).get();
      expect(tags.map((t) => t.name), isNot(contains('Neu')));
      expect(tags.map((t) => t.name), contains('Urlaub'));
    },
  );

  test(
    'Album: nur die neu hineingelegten; ein neues Album verschwindet',
    () async {
      await db.createAlbum(
        AlbumsCompanion.insert(
          id: 'alt',
          name: 'Alt',
          createdAt: DateTime(2026),
        ),
      );
      await db.addAssetsToAlbum('alt', ['a']);
      final schon = await db.imAlbum('alt', ['a', 'b']);
      await db.addAssetsToAlbum('alt', ['a', 'b']);
      await db.nimmAusAlbum('alt', [
        for (final id in ['a', 'b'])
          if (!schon.contains(id)) id,
      ]);
      expect(await db.imAlbum('alt', ['a', 'b']), {'a'});

      await db.createAlbum(
        AlbumsCompanion.insert(
          id: 'neu',
          name: 'Neu',
          createdAt: DateTime(2026),
        ),
      );
      await db.addAssetsToAlbum('neu', ['c']);
      await db.nimmAusAlbum('neu', ['c'], albumLoeschen: true);
      final alben = await db.select(db.albums).get();
      expect(alben.map((a) => a.id), ['alt']);
    },
  );

  test('ein unbekanntes Schlagwort abzunehmen ist kein Fehler', () async {
    await db.nimmSchlagwortAb(['a'], 'Gibtsnicht');
    expect(await db.tragenSchlagwort(['a'], 'Gibtsnicht'), isEmpty);
  });

  testWidgets('die Meldung nach dem Favorisieren nimmt es zurück', (
    tester,
  ) async {
    final wurzel = Directory.systemTemp.createTempSync('pv_rueck_');
    addTearDown(() {
      melde.verlaufLeeren();
      wurzel.deleteSync(recursive: true);
    });
    late final LibraryState library;
    await tester.runAsync(() async {
      library = LibraryState()
        ..db = db
        ..paths = await StoragePaths.forTesting(
          Directory(p.join(wurzel.path, 'lib')),
        );
      await db.setFavoriteBulk(['b'], true);
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        builder: (context, kind) => mitMeldungen(kind),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => runBatchFavorite(library, [
              'a',
              'b',
            ], texte: AppTexte.of(context)),
            child: const Text('Los'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Los'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(melde.sichtbare.single.text, '2 Fotos als Favorit markiert');
    expect(find.text('Rückgängig'), findsOneWidget);
    expect((await tester.runAsync(() => aufnahme('a')))!.isFavorite, isTrue);

    await tester.tap(find.text('Rückgängig'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect((await tester.runAsync(() => aufnahme('a')))!.isFavorite, isFalse);
    expect(
      (await tester.runAsync(() => aufnahme('b')))!.isFavorite,
      isTrue,
      reason: 'war schon vorher Favorit',
    );
  });
}
