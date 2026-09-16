import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Prüft die Datenbank-Grundlagen des automatischen Papierkorb-Ablaufs
/// (siehe LibraryState.purgeExpiredTrashIfDue): die Einstellungen-Tabelle
/// und [AppDatabase.expiredTrashAssets], das nach Ablaufdatum gefilterte
/// Assets liefert.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late ImportService import;
  var nextByte = 0;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('photo_vault_trash_expire_test_');
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

  Future<void> setTrashedAt(String assetId, DateTime when) =>
      (db.update(db.assets)..where((t) => t.id.equals(assetId)))
          .write(AssetsCompanion(isTrashed: const Value(true), trashedAt: Value(when)));

  test('trashSettingsRow ist standardmäßig deaktiviert und ohne Zeile vorhanden', () async {
    expect(await db.trashSettingsRow(), isNull);
  });

  test('setTrashAutoDeleteConfig legt die Zeile an und lässt einzelne Felder unangetastet', () async {
    await db.setTrashAutoDeleteConfig(enabled: true);
    var config = await db.trashSettingsRow();
    expect(config!.autoDeleteEnabled, isTrue);
    expect(config.autoDeleteAfterDays, 30); // Default

    await db.setTrashAutoDeleteConfig(enabled: true, afterDays: 7);
    config = await db.trashSettingsRow();
    expect(config!.autoDeleteAfterDays, 7);

    await db.setTrashAutoDeleteConfig(enabled: false);
    config = await db.trashSettingsRow();
    expect(config!.autoDeleteEnabled, isFalse);
    expect(config.autoDeleteAfterDays, 7); // bleibt erhalten, da afterDays: null
  });

  test('setLastTrashPurgeAt aktualisiert nur nach vorherigem setTrashAutoDeleteConfig', () async {
    await db.setTrashAutoDeleteConfig(enabled: true);
    final now = DateTime(2026, 8, 12, 10, 0);
    await db.setLastTrashPurgeAt(now);
    expect((await db.trashSettingsRow())!.lastPurgeAt, now);
  });

  test('expiredTrashAssets liefert nur vor dem Stichtag in den Papierkorb verschobene Assets', () async {
    final old = await importPhoto('old.jpg');
    await setTrashedAt(old.id, DateTime(2026, 1, 1));

    final recent = await importPhoto('recent.jpg');
    await setTrashedAt(recent.id, DateTime(2026, 8, 1));

    final notTrashed = await importPhoto('kept.jpg');

    final cutoff = DateTime(2026, 7, 1);
    final expired = await db.expiredTrashAssets(cutoff);

    expect(expired.map((a) => a.id).toList(), [old.id]);
    expect(expired.map((a) => a.id), isNot(contains(recent.id)));
    expect(expired.map((a) => a.id), isNot(contains(notTrashed.id)));
  });

  test('expiredTrashAssets erfasst auch gesperrte Assets (Löschen benötigt keinen PIN)', () async {
    final locked = await importPhoto('locked.jpg');
    await (db.update(db.assets)..where((t) => t.id.equals(locked.id)))
        .write(const AssetsCompanion(isLocked: Value(true)));
    await setTrashedAt(locked.id, DateTime(2026, 1, 1));

    final expired = await db.expiredTrashAssets(DateTime(2026, 7, 1));
    expect(expired.map((a) => a.id), contains(locked.id));
  });
}
