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

  test('die Fotos eines Schlagworts kommen aus einem Index', () async {
    // Die Suche am Handy und im Browser fragt je Wort nach den Fotos der
    // passenden Schlagwörter, das Aufräumen unbenutzter Schlagwörter je
    // Kandidat, ob ihn noch ein Foto trägt. Der Primärschlüssel beginnt
    // mit asset_id; beide Fragen lasen die ganze Tabelle.
    final suche = await plan(
      "SELECT asset_id FROM asset_tags WHERE tag_id IN ('t1', 't2')",
    );
    expect(suche, contains('idx_asset_tags_tag'));
    expect(suche, isNot(contains('SCAN')));
    final aufraeumen = await plan(
      "SELECT id FROM tags t WHERE id IN ('t1') AND NOT EXISTS "
      '(SELECT 1 FROM asset_tags a WHERE a.tag_id = t.id)',
    );
    expect(aufraeumen, contains('idx_asset_tags_tag'));
    expect(aufraeumen, isNot(contains('SCAN')));
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
