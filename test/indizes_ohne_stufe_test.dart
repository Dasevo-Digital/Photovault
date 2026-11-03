import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';

/// Stapel und Live-Photo-Partner lasen ohne Index die ganze Tabelle der
/// Aufnahmen (#268). Die Indizes kommen beim Öffnen, ohne eigene
/// Schemastufe – für neue wie für bestehende Bibliotheken.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<String> plan(String sql) async => [
    for (final z in await db.customSelect('EXPLAIN QUERY PLAN $sql').get())
      z.read<String>('detail'),
  ].join(' | ');

  test('Stapel und Partner finden ihre Zeilen über einen Index', () async {
    expect(
      await plan("SELECT id FROM assets WHERE stack_id = 's1'"),
      contains('idx_assets_stack_id'),
    );
    expect(
      await plan("SELECT id FROM assets WHERE linked_asset_id = 'a1'"),
      contains('idx_assets_linked_asset_id'),
    );
  });

  test('ein zweites Öffnen legt nichts doppelt an', () async {
    await db.indizesOhneStufe();
    final n = await db
        .customSelect(
          "SELECT count(*) AS n FROM sqlite_master WHERE type = 'index' "
          "AND name IN ('idx_assets_stack_id', 'idx_assets_linked_asset_id')",
        )
        .getSingle();
    expect(n.read<int>('n'), 2);
  });
}
