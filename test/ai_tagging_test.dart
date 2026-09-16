import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/ai_tagging_service.dart' show defaultAiTagVocabulary;
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Prüft die DB-Bausteine des KI-Tagging-Backfills (siehe
/// LibraryState.backfillAiTags): welche Fotos als "ungetaggt" gelten, dass
/// gesperrte/gelöschte Fotos nie vorgeschlagen werden, und dass ein
/// gespeichertes Embedding unverändert wieder ausgelesen werden kann.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late ImportService import;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('photo_vault_ai_tagging_test_');
    db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
    import = ImportService(db, paths);
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<String> importPhoto(String name, List<int> bytes) async {
    final incoming = Directory(p.join(tempRoot.path, 'incoming'))..createSync(recursive: true);
    final file = File(p.join(incoming.path, name))..writeAsBytesSync(bytes);
    final result = await import.importFile(file.path);
    expect(result.outcome, ImportOutcome.imported);
    return result.assetId!;
  }

  test('assetsForAiTagging(onlyUntagged: true) findet nur Fotos ganz ohne Tags', () async {
    final untaggedId = await importPhoto('a.jpg', [1, 2, 3]);
    final taggedId = await importPhoto('b.jpg', [4, 5, 6]);
    await db.tagAsset(taggedId, 'Urlaub');

    final onlyUntagged = await db.assetsForAiTagging(onlyUntagged: true);
    expect(onlyUntagged.map((a) => a.id), contains(untaggedId));
    expect(onlyUntagged.map((a) => a.id), isNot(contains(taggedId)));

    final all = await db.assetsForAiTagging(onlyUntagged: false);
    expect(all.map((a) => a.id), containsAll([untaggedId, taggedId]));
  });

  test('gesperrte und gelöschte Fotos werden nie für KI-Tagging vorgeschlagen', () async {
    final lockedId = await importPhoto('locked.jpg', [7, 8, 9]);
    final trashedId = await importPhoto('trashed.jpg', [10, 11, 12]);
    await db.setAssetsLocked([lockedId], true);
    await db.moveToTrash([trashedId]);

    for (final onlyUntagged in [true, false]) {
      final candidates = await db.assetsForAiTagging(onlyUntagged: onlyUntagged);
      expect(candidates.map((a) => a.id), isNot(contains(lockedId)));
      expect(candidates.map((a) => a.id), isNot(contains(trashedId)));
    }
  });

  test('embeddingForAsset liefert ein zuvor gespeichertes Embedding unverändert zurück', () async {
    final assetId = await importPhoto('c.jpg', [1, 2, 3]);
    expect(await db.embeddingForAsset(assetId), isNull);

    final vector = Float32List.fromList([0.1, 0.2, 0.3, 0.4]);
    await db.saveEmbedding(assetId, vector);

    final loaded = await db.embeddingForAsset(assetId);
    expect(loaded, isNotNull);
    expect(loaded, orderedEquals(vector));
  });

  group('AiTagVocabulary (editierbares KI-Tagging-Vokabular)', () {
    test('eine frisch angelegte DB wird mit dem ursprünglichen 48-Begriffe-Vokabular bestückt', () async {
      final terms = await db.aiTagVocabularyTerms();
      expect(terms, containsAll(['Baby', 'Familie', 'Hund', 'Weihnachten']));
      expect(terms.length, defaultAiTagVocabulary.length);
    });

    test('addAiTagTerm fügt einen neuen Begriff hinzu und ist idempotent bei Wiederholung', () async {
      await db.addAiTagTerm('Drachenfliegen');
      await db.addAiTagTerm('Drachenfliegen');

      final terms = await db.aiTagVocabularyTerms();
      expect(terms.where((t) => t == 'Drachenfliegen'), hasLength(1));
    });

    test('addAiTagTerm trimmt Leerzeichen und ignoriert leere Eingaben', () async {
      final before = await db.aiTagVocabularyTerms();
      await db.addAiTagTerm('   ');
      final afterEmpty = await db.aiTagVocabularyTerms();
      expect(afterEmpty.length, before.length);

      await db.addAiTagTerm('  Angeln  ');
      final afterTrim = await db.aiTagVocabularyTerms();
      expect(afterTrim, contains('Angeln'));
      expect(afterTrim, isNot(contains('  Angeln  ')));
    });

    test('removeAiTagTerm entfernt genau den angegebenen Begriff', () async {
      final rows = await db.select(db.aiTagVocabulary).get();
      final babyRow = rows.firstWhere((r) => r.term == 'Baby');

      await db.removeAiTagTerm(babyRow.id);

      final terms = await db.aiTagVocabularyTerms();
      expect(terms, isNot(contains('Baby')));
      expect(terms.length, defaultAiTagVocabulary.length - 1);
    });

    test('watchAiTagVocabulary liefert reaktiv den aktuellen Stand', () async {
      final stream = db.watchAiTagVocabulary();
      final first = await stream.first;
      expect(first.length, defaultAiTagVocabulary.length);

      final updates = stream.skip(1).first;
      await db.addAiTagTerm('Segeln');
      final afterAdd = await updates;
      expect(afterAdd.length, defaultAiTagVocabulary.length + 1);
    });
  });
}
