import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Schema 98: die Löschaktion im Papierkorb (#389).
void main() {
  test('Migration 97 auf 98 legt die Spalte an, Gelöschtes bleibt', () async {
    final dir = await Directory.systemTemp.createTemp('photo_vault_v97_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/library.sqlite');

    final initial = AppDatabase(NativeDatabase(file));
    for (final id in ['haupt', 'variante']) {
      await initial.insertAsset(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: id,
          type: 'IMAGE',
          fileCreatedAt: DateTime(2024),
          importedAt: DateTime(2024),
        ),
      );
    }
    await initial.fuehreAus(
      const VariantenBilden('probe', ['haupt', 'variante'], 'haupt'),
    );
    await (initial.update(initial.assets)).write(
      AssetsCompanion(
        isTrashed: const Value(true),
        trashedAt: Value(DateTime(2026, 10, 30)),
      ),
    );
    await initial.close();

    final alt = sqlite.sqlite3.open(file.path);
    alt.execute('ALTER TABLE assets DROP COLUMN papierkorb_aktion');
    alt.execute('PRAGMA user_version = 97');
    alt.close();

    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final v = await db.assetById('variante');
    expect(v!.isTrashed, isTrue);
    expect(v.papierkorbAktion, isNull);
    // Ohne Aktion zählt wie bisher der Zeitpunkt.
    await db.fuehreAus(const AusDemPapierkorb(['haupt']));
    expect((await db.assetById('variante'))!.isTrashed, isFalse);
  });
}
