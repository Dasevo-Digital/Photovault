import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';

/// Schreibt jede Abfrage mit, damit ihr Plan sich zeigen lässt.
class _Mitschnitt extends QueryInterceptor {
  QueryExecutor? _ausfuehrer;
  final abfragen = <(String, List<Object?>)>[];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _ausfuehrer = executor;
    abfragen.add((statement, args));
    return executor.runSelect(statement, args);
  }

  Future<String> plan(String sql, List<Object?> args) async => [
    for (final z in await _ausfuehrer!.runSelect(
      'EXPLAIN QUERY PLAN $sql',
      args,
    ))
      z['detail'],
  ].join(' | ');
}

/// Kalender und Jahresübersicht seit der Datierung (#435): Die Titelbilder
/// suchen über einen Bereich im Index, die Zählungen lesen nur den Index.
void main() {
  late _Mitschnitt mitschnitt;
  late AppDatabase db;

  setUp(() async {
    mitschnitt = _Mitschnitt();
    db = AppDatabase(NativeDatabase.memory().interceptWith(mitschnitt));
    for (var i = 0; i < 600; i++) {
      await db.insertAsset(
        AssetsCompanion.insert(
          id: 'a$i',
          originalFileName: 'a$i.jpg',
          relativePath: 'originals/a$i.jpg',
          checksum: 'pruef$i',
          type: 'IMAGE',
          fileCreatedAt: DateTime(1990 + i % 30, 1 + i % 12, 3),
          importedAt: DateTime(2026),
        ),
      );
    }
    await db.statistikPflegen();
  });
  tearDown(() => db.close());

  /// Die Pläne aller Abfragen auf `assets`, die [abfrage] stellt.
  Future<List<String>> plaene(Future<Object?> Function() abfrage) async {
    mitschnitt.abfragen.clear();
    await abfrage();
    return [
      for (final (sql, args) in [...mitschnitt.abfragen])
        if (sql.contains('"assets"') || sql.contains('FROM assets'))
          await mitschnitt.plan(sql, args),
    ];
  }

  test('Titelbilder und Listen eines Jahres oder Monats suchen über einen '
      'Bereich im Index', () async {
    for (final abfrage in <Future<Object?> Function()>[
      () => db.newestAssetForYear(1991),
      () => db.newestAssetForMonth(1991, 3),
      () => db.watchTimelineForYear(1991).first,
      () => db.aufnahmenImMonat(1991, 3),
    ]) {
      final p = await plaene(abfrage);
      expect(p, isNotEmpty);
      expect(
        p.single,
        allOf(contains('idx_assets_kalender'), contains('<expr><?')),
      );
    }
  });

  test('die Zählungen je Jahr lesen nur den Index der Zeitleiste', () async {
    final p = await plaene(db.assetCountsByYear);
    expect(p.single, contains('COVERING INDEX idx_assets_sichtbar'));
    expect(p.single, isNot(contains('SCAN assets |')));
  });

  test('ein Index der Zeitleiste ohne die Spalten der Datierung wird '
      'ersetzt', () async {
    await db.customStatement('DROP INDEX idx_assets_sichtbar');
    await db.customStatement(
      'CREATE INDEX idx_assets_sichtbar ON assets ('
      'is_trashed, is_locked, file_created_at DESC, id DESC, '
      'type, linked_asset_id, stack_id, is_stack_cover, is_archived)',
    );
    await db.indizesOhneStufe();
    final spalten = [
      for (final z
          in await db
              .customSelect(
                "SELECT name FROM pragma_index_info('idx_assets_sichtbar')",
              )
              .get())
        z.read<String>('name'),
    ];
    expect(spalten, containsAll(['datum_von', 'datum_genauigkeit']));
  });

  test('die Grenze lässt nichts aus: Ortszeit und UTC an der '
      'Jahreswende', () async {
    // Ohne Datierung zählt die Ortszeit, mit Datierung UTC.
    await db.insertAsset(
      AssetsCompanion.insert(
        id: 'ort',
        originalFileName: 'ort.jpg',
        relativePath: 'originals/ort.jpg',
        checksum: 'ort',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2030),
        importedAt: DateTime(2026),
      ),
    );
    await db.insertAsset(
      AssetsCompanion.insert(
        id: 'utc',
        originalFileName: 'utc.jpg',
        relativePath: 'originals/utc.jpg',
        checksum: 'utc',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2026),
        importedAt: DateTime(2026),
        datumVon: Value(DateTime.utc(2031)),
        datumGenauigkeit: const Value('tag'),
      ),
    );
    expect((await db.newestAssetForYear(2030))?.id, 'ort');
    expect((await db.newestAssetForYear(2031))?.id, 'utc');
    expect((await db.newestAssetForMonth(2030, 1))?.id, 'ort');
    expect((await db.newestAssetForMonth(2031, 1))?.id, 'utc');
    expect((await db.assetCountsByMonth(2031))[1], 1);
  });
}
