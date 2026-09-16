import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// Prüft zwei Ebenen des Embedding-Caches (siehe LibraryState.cachedEmbeddings
/// und AppDatabase.embeddingsGeneration):
///
/// 1. AppDatabase.embeddingsGeneration erhöht sich GENAU bei den Mutationen,
///    die das Ergebnis von allEmbeddings() verändern können (neues Embedding,
///    Papierkorb/Wiederherstellen, endgültiges Löschen, Sperren/Entsperren) –
///    nicht bei unrelated Mutationen wie einem Favoriten-Toggle.
/// 2. LibraryState.cachedEmbeddings() liefert bei unverändertem
///    embeddingsGeneration dasselbe (gecachte) Ergebnis-Objekt zurück, ohne
///    erneut die DB abzufragen, und lädt korrekt neu, sobald sich die
///    Generation geändert hat.
void main() {
  group('AppDatabase.embeddingsGeneration', () {
    late Directory tempRoot;
    late AppDatabase db;
    late ImportService import;
    var nextByte = 0;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('photo_vault_embeddings_cache_test_');
      db = AppDatabase(NativeDatabase.memory());
      final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
      import = ImportService(db, paths);
    });

    tearDown(() async {
      await db.close();
      tempRoot.deleteSync(recursive: true);
    });

    Future<AssetData> importPhoto(String name) async {
      final incoming = Directory(p.join(tempRoot.path, 'incoming'))..createSync(recursive: true);
      final file = File(p.join(incoming.path, name))..writeAsBytesSync([1, 2, 3, nextByte++]);
      final result = await import.importFile(file.path);
      expect(result.outcome, ImportOutcome.imported);
      return (await db.assetById(result.assetId!))!;
    }

    test('erhöht sich bei saveEmbedding, moveToTrash, restoreFromTrash, setAssetsLocked, deleteAssetRows', () async {
      final asset = await importPhoto('a.jpg');
      final before = db.embeddingsGeneration;

      await db.saveEmbedding(asset.id, Float32List.fromList([1.0, 0.0]));
      expect(db.embeddingsGeneration, greaterThan(before));

      final afterSave = db.embeddingsGeneration;
      await db.moveToTrash([asset.id]);
      expect(db.embeddingsGeneration, greaterThan(afterSave));

      final afterTrash = db.embeddingsGeneration;
      await db.restoreFromTrash([asset.id]);
      expect(db.embeddingsGeneration, greaterThan(afterTrash));

      final afterRestore = db.embeddingsGeneration;
      await db.setAssetsLocked([asset.id], true);
      expect(db.embeddingsGeneration, greaterThan(afterRestore));

      final afterLock = db.embeddingsGeneration;
      await db.deleteAssetRows([asset.id]);
      expect(db.embeddingsGeneration, greaterThan(afterLock));
    });

    test('bleibt bei unrelated Mutationen (Favorit, Beschreibung) unverändert', () async {
      final asset = await importPhoto('b.jpg');
      final before = db.embeddingsGeneration;

      await db.setFavorite(asset.id, true);
      await db.setDescription(asset.id, 'Test');

      expect(db.embeddingsGeneration, before);
    });
  });

  group('LibraryState.cachedEmbeddings', () {
    late Directory tempRoot;
    late AppDatabase db;
    late ImportService import;
    late LibraryState library;
    var nextByte = 0;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('photo_vault_embeddings_cache_libstate_test_');
      db = AppDatabase(NativeDatabase.memory());
      final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
      import = ImportService(db, paths);
      library = LibraryState()
        ..db = db
        ..paths = paths;
    });

    tearDown(() async {
      await db.close();
      tempRoot.deleteSync(recursive: true);
    });

    Future<AssetData> importPhoto(String name) async {
      final incoming = Directory(p.join(tempRoot.path, 'incoming'))..createSync(recursive: true);
      final file = File(p.join(incoming.path, name))..writeAsBytesSync([1, 2, 3, nextByte++]);
      final result = await import.importFile(file.path);
      expect(result.outcome, ImportOutcome.imported);
      return (await db.assetById(result.assetId!))!;
    }

    test('liefert bei unverändertem embeddingsGeneration dasselbe gecachte Ergebnis', () async {
      final asset = await importPhoto('a.jpg');
      await db.saveEmbedding(asset.id, Float32List.fromList([1.0, 0.0]));

      final first = await library.cachedEmbeddings();
      final second = await library.cachedEmbeddings();

      // identical() prüft echte Objekt-Identität - beweist, dass die DB beim
      // zweiten Aufruf NICHT erneut abgefragt wurde.
      expect(identical(first, second), isTrue);
      expect(first.keys, contains(asset.id));
    });

    test('lädt neu, sobald sich embeddingsGeneration durch eine Mutation geändert hat', () async {
      final assetA = await importPhoto('a.jpg');
      await db.saveEmbedding(assetA.id, Float32List.fromList([1.0, 0.0]));

      final first = await library.cachedEmbeddings();
      expect(first.keys, {assetA.id});

      final assetB = await importPhoto('b.jpg');
      await db.saveEmbedding(assetB.id, Float32List.fromList([0.0, 1.0]));

      final second = await library.cachedEmbeddings();
      expect(identical(first, second), isFalse);
      expect(second.keys, {assetA.id, assetB.id});
    });

    test('gibt getrashte/gesperrte Assets nach Cache-Invalidierung korrekt nicht mehr zurück', () async {
      final asset = await importPhoto('a.jpg');
      await db.saveEmbedding(asset.id, Float32List.fromList([1.0, 0.0]));
      expect((await library.cachedEmbeddings()).keys, contains(asset.id));

      await db.moveToTrash([asset.id]);
      expect((await library.cachedEmbeddings()).keys, isNot(contains(asset.id)));
    });
  });
}
