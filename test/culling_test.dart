import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Prüft [AppDatabase.assetsForCulling] – die Grundlage des Sichtungs-Modus
/// (Culling): nur unbewertete, nicht gelöschte, nicht gesperrte Fotos/Videos,
/// neueste zuerst. Sobald ein Foto eine Bewertung, eine Papierkorb- oder eine
/// Sperr-Markierung erhält, muss es aus der Liste verschwinden.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late ImportService import;
  var nextByte = 0;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('photo_vault_culling_test_');
    db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
    import = ImportService(db, paths);
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<AssetData> importPhoto(String name, {DateTime? createdAt}) async {
    final incoming = Directory(p.join(tempRoot.path, 'incoming'))..createSync(recursive: true);
    final file = File(p.join(incoming.path, name))..writeAsBytesSync([1, 2, 3, nextByte++]);
    final result = await import.importFile(file.path);
    expect(result.outcome, ImportOutcome.imported);
    if (createdAt != null) await db.setFileCreatedAt(result.assetId!, createdAt);
    return (await db.assetById(result.assetId!))!;
  }

  test('findet nur unbewertete Fotos, neueste zuerst', () async {
    final older = await importPhoto('a.jpg', createdAt: DateTime(2026, 1, 1));
    final newer = await importPhoto('b.jpg', createdAt: DateTime(2026, 6, 1));

    final results = await db.assetsForCulling();

    expect(results.map((a) => a.id), [newer.id, older.id]);
  });

  test('bewertete Fotos verschwinden aus der Liste', () async {
    final rated = await importPhoto('a.jpg');
    final unrated = await importPhoto('b.jpg');
    await db.setRating(rated.id, 3);

    final results = await db.assetsForCulling();

    expect(results.map((a) => a.id), [unrated.id]);
  });

  test('Fotos im Papierkorb oder gesperrte Fotos tauchen nie auf', () async {
    final trashed = await importPhoto('a.jpg');
    final locked = await importPhoto('b.jpg');
    final normal = await importPhoto('c.jpg');
    await db.moveToTrash([trashed.id]);
    await db.setAssetsLocked([locked.id], true);

    final results = await db.assetsForCulling();

    expect(results.map((a) => a.id), [normal.id]);
  });
}
