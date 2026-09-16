import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/search_filters.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Prüft die Serien-/Burst-Stapel-DB-Logik: createStack/unstackAssets/
/// assetsInStack, und dass nicht-Titelbild-Mitglieder aus den Grid-Abfragen
/// verschwinden (watchTimeline, searchAssets) – exakt wie das
/// Video-Gegenstück eines Live-Photo-Paares heute schon verschwindet.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late ImportService import;
  var nextByte = 0;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('photo_vault_stacking_test_');
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

  test('createStack markiert nur das Titelbild als Cover und setzt stackSize dort', () async {
    final a = await importPhoto('a.jpg');
    final b = await importPhoto('b.jpg');
    final c = await importPhoto('c.jpg');

    await db.createStack('stack-1', [a.id, b.id, c.id], b.id);

    final refreshedA = (await db.assetById(a.id))!;
    final refreshedB = (await db.assetById(b.id))!;
    final refreshedC = (await db.assetById(c.id))!;

    expect(refreshedA.stackId, 'stack-1');
    expect(refreshedA.isStackCover, isFalse);
    expect(refreshedA.stackSize, isNull);

    expect(refreshedB.stackId, 'stack-1');
    expect(refreshedB.isStackCover, isTrue);
    expect(refreshedB.stackSize, 3);

    expect(refreshedC.stackId, 'stack-1');
    expect(refreshedC.isStackCover, isFalse);
    expect(refreshedC.stackSize, isNull);
  });

  test('assetsInStack liefert alle Mitglieder eines Stapels', () async {
    final a = await importPhoto('a.jpg');
    final b = await importPhoto('b.jpg');
    await importPhoto('unrelated.jpg');
    await db.createStack('stack-1', [a.id, b.id], a.id);

    final members = await db.assetsInStack('stack-1');

    expect(members.map((m) => m.id).toSet(), {a.id, b.id});
  });

  test('unstackAssets löst den Stapel wieder auf – alle Mitglieder wieder einzeln sichtbar', () async {
    final a = await importPhoto('a.jpg');
    final b = await importPhoto('b.jpg');
    await db.createStack('stack-1', [a.id, b.id], a.id);

    await db.unstackAssets('stack-1');

    for (final id in [a.id, b.id]) {
      final asset = (await db.assetById(id))!;
      expect(asset.stackId, isNull);
      expect(asset.isStackCover, isFalse);
      expect(asset.stackSize, isNull);
    }
  });

  test('watchTimeline zeigt nur das Titelbild eines Stapels, nicht die übrigen Mitglieder', () async {
    final cover = await importPhoto('cover.jpg');
    final hidden = await importPhoto('hidden.jpg');
    final unrelated = await importPhoto('unrelated.jpg');
    await db.createStack('stack-1', [cover.id, hidden.id], cover.id);

    final timeline = await db.watchTimeline().first;

    expect(timeline.map((a) => a.id).toSet(), {cover.id, unrelated.id});
  });

  test('searchAssets zeigt nur das Titelbild eines Stapels', () async {
    final cover = await importPhoto('cover.jpg');
    final hidden = await importPhoto('hidden.jpg');
    await db.createStack('stack-1', [cover.id, hidden.id], cover.id);

    final results = await db.searchAssets(const SearchFilters());

    expect(results.map((a) => a.id), [cover.id]);
  });

  test('nach unstackAssets tauchen wieder alle Mitglieder einzeln in watchTimeline auf', () async {
    final a = await importPhoto('a.jpg');
    final b = await importPhoto('b.jpg');
    await db.createStack('stack-1', [a.id, b.id], a.id);
    await db.unstackAssets('stack-1');

    final timeline = await db.watchTimeline().first;

    expect(timeline.map((t) => t.id).toSet(), {a.id, b.id});
  });
}
