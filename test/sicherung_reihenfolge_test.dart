import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';

/// Die Sicherung nimmt die Originale in fester Reihenfolge: die neuesten
/// Aufnahmen zuerst, bei gleichem Aufnahmedatum nach Kennung (#468).
///
/// Mit einer Menge je Lauf kommt nur der Anfang der Liste ins Ziel. Vorher
/// fragte die Sicherung ohne Reihenfolge ab, und was zuerst gesichert
/// wurde, hing an der Statistik von SQLite.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> aufnahme(
    String id,
    DateTime datei, {
    DateTime? datumVon,
    bool papierkorb = false,
    bool gesperrt = false,
  }) => db
      .into(db.assets)
      .insert(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: id,
          type: 'IMAGE',
          fileCreatedAt: datei,
          importedAt: DateTime(2026),
          datumVon: Value(datumVon),
          isTrashed: Value(papierkorb),
          isLocked: Value(gesperrt),
        ),
      );

  test('die neuesten zuerst, bei Gleichstand nach Kennung', () async {
    // Absichtlich nicht in der erwarteten Reihenfolge angelegt.
    await aufnahme('b', DateTime(2024), datumVon: DateTime(2019));
    await aufnahme('a', DateTime(2020));
    await aufnahme('d', DateTime(2023, 5));
    await aufnahme('x', DateTime(2025), papierkorb: true);
    await aufnahme('c', DateTime(2023, 5));
    await aufnahme('y', DateTime(2025), gesperrt: true);

    final reihe = await db.assetsFuerSicherung();
    // Das Aufnahmedatum (datum_von) geht dem Dateidatum vor.
    expect(reihe.map((a) => a.id), ['c', 'd', 'a', 'b']);
  });

  test(
    'mit Mengengrenze sichert der Lauf von Hand die neueste zuerst',
    () async {
      final temp = await Directory.systemTemp.createTemp('pv_reihenfolge_');
      addTearDown(() => temp.delete(recursive: true));
      final pfade = await StoragePaths.forTesting(
        Directory(p.join(temp.path, 'library')),
      );
      final importe = ImportService(db, pfade);
      // Die älteste zuerst importiert, die neueste in der Mitte.
      for (final (name, jahr, inhalt) in [
        ('erstes', 2018, 1),
        ('zweites', 2024, 2),
        ('drittes', 2021, 3),
      ]) {
        final f = File(p.join(temp.path, '$name.jpg'))
          ..writeAsBytesSync(List.filled(32 * 1024, inhalt));
        await f.setLastModified(DateTime(jahr, 3, 1));
        await importe.importFile(f.path);
      }
      final ziel = Directory(p.join(temp.path, 'stick'))..createSync();

      await BackupService(
        db,
        pfade,
      ).performBackup(ziel.path, maxBytesPerRun: 1).drain<void>();

      final gesichert = (await db.select(db.assets).get())
          .where((a) => a.backedUp)
          .map((a) => a.originalFileName);
      expect(gesichert, ['zweites.jpg']);
    },
  );
}
