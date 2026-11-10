import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Schema 97: das Archiv (#304).
void main() {
  test('Migration 96 auf 97 legt die Spalte an, nichts im Archiv', () async {
    final dir = await Directory.systemTemp.createTemp('photo_vault_v96_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/library.sqlite');

    final initial = AppDatabase(NativeDatabase(file));
    await initial.insertAsset(
      AssetsCompanion.insert(
        id: 'a',
        originalFileName: 'a.jpg',
        relativePath: 'originals/a.jpg',
        checksum: 'a',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2024),
        importedAt: DateTime(2024),
      ),
    );
    await initial.close();

    final alt = sqlite.sqlite3.open(file.path);
    alt.execute('DROP INDEX IF EXISTS idx_assets_sichtbar');
    alt.execute('ALTER TABLE assets DROP COLUMN is_archived');
    alt.execute('PRAGMA user_version = 96');
    alt.close();

    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final a = await db.assetById('a');
    expect(a, isNotNull);
    expect(a!.isArchived, isFalse);
    expect((await db.watchRasterzeilen().first).map((z) => z.id), ['a']);
  });
}
