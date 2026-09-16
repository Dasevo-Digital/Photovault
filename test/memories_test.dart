import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Prüft [AppDatabase.assetsOnThisDay] – die Grundlage der "Erinnerungen"-
/// Sektion im Erkunden-Tab: findet Fotos vom selben Monat+Tag in früheren
/// Jahren, aber weder von heute selbst noch von einem anderen Kalendertag.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late ImportService import;
  var nextByte = 0;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('photo_vault_memories_test_');
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

  test('findet denselben Monat/Tag aus früheren Jahren, aber nicht heute oder andere Tage', () async {
    final today = DateTime(2026, 8, 11);

    final oneYearAgo = await importPhoto('a.jpg');
    await db.setFileCreatedAt(oneYearAgo.id, DateTime(2025, 8, 11, 14, 30));

    final threeYearsAgo = await importPhoto('b.jpg');
    await db.setFileCreatedAt(threeYearsAgo.id, DateTime(2023, 8, 11, 9, 41));

    final sameDayThisYear = await importPhoto('c.jpg');
    await db.setFileCreatedAt(sameDayThisYear.id, today);

    final differentDay = await importPhoto('d.jpg');
    await db.setFileCreatedAt(differentDay.id, DateTime(2025, 8, 12, 9, 41));

    final results = await db.assetsOnThisDay(today);

    expect(results.map((a) => a.id).toList(), [oneYearAgo.id, threeYearsAgo.id]);
  });

  test('schließt gelöschte und gesperrte Fotos aus', () async {
    final today = DateTime(2026, 8, 11);

    final trashed = await importPhoto('trashed.jpg');
    await db.setFileCreatedAt(trashed.id, DateTime(2025, 8, 11, 9, 41));
    await db.moveToTrash([trashed.id]);

    final results = await db.assetsOnThisDay(today);

    expect(results, isEmpty);
  });
}
