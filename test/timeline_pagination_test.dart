import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

/// Fügt [count] synthetische Assets in einem einzigen Batch ein – der volle
/// Import-Pfad (Thumbnail/EXIF/Prüfsumme aus echten Bytes) wäre für einen
/// Test mit zehntausenden Zeilen viel zu langsam; hier sind nur die für
/// Timeline-Abfragen relevanten Spalten gesetzt.
Future<void> insertSyntheticAssets(
  AppDatabase db,
  int count, {
  DateTime? baseDate,
  int idOffset = 0,
}) async {
  final base = baseDate ?? DateTime(2015, 1, 1);
  final rows = List.generate(count, (i) {
    final n = idOffset + i;
    // Zeitstempel über den GLOBALEN Index [n] statt des batch-lokalen [i]
    // gestaffelt, damit bei mehreren Aufrufen mit verschiedenen [idOffset]
    // (siehe 100k-Test unten) eine eindeutige, monoton steigende
    // Gesamtreihenfolge über alle Batches hinweg entsteht statt sich
    // überlappender Zeitbereiche.
    return AssetsCompanion.insert(
      id: 'asset_$n',
      originalFileName: 'IMG_$n.jpg',
      relativePath: 'originals/synthetic/asset_$n.jpg',
      checksum: 'checksum_$n',
      type: 'IMAGE',
      fileCreatedAt: base.add(Duration(minutes: n)),
      importedAt: base,
    );
  });
  await db.batch((b) => b.insertAll(db.assets, rows));
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('watchTimeline(limit:) liefert nur die neuesten N Fotos, korrekt sortiert', () async {
    await insertSyntheticAssets(db, 50);
    final page = await db.watchTimeline(limit: 10).first;
    expect(page, hasLength(10));
    // asset_49 hat den spätesten fileCreatedAt (base + 49 Minuten) - absteigend sortiert.
    expect(page.first.id, 'asset_49');
    expect(page.last.id, 'asset_40');
  });

  test('watchTimeline ohne limit liefert weiterhin alles (unverändertes Verhalten)', () async {
    await insertSyntheticAssets(db, 30);
    final all = await db.watchTimeline().first;
    expect(all, hasLength(30));
  });

  test('watchTimelineForYear liefert nur Assets des angegebenen Jahres', () async {
    await db.batch((b) => b.insertAll(db.assets, [
          AssetsCompanion.insert(
            id: 'a2019',
            originalFileName: 'a.jpg',
            relativePath: 'a.jpg',
            checksum: 'c1',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2019, 12, 31, 23, 59),
            importedAt: DateTime(2019, 12, 31),
          ),
          AssetsCompanion.insert(
            id: 'a2020a',
            originalFileName: 'b.jpg',
            relativePath: 'b.jpg',
            checksum: 'c2',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2020, 6, 1),
            importedAt: DateTime(2020, 6, 1),
          ),
          AssetsCompanion.insert(
            id: 'a2020b',
            originalFileName: 'c.jpg',
            relativePath: 'c.jpg',
            checksum: 'c3',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2020, 12, 31, 23, 59),
            importedAt: DateTime(2020, 12, 31),
          ),
          AssetsCompanion.insert(
            id: 'a2021',
            originalFileName: 'd.jpg',
            relativePath: 'd.jpg',
            checksum: 'c4',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2021, 1, 1, 0, 1),
            importedAt: DateTime(2021, 1, 1),
          ),
        ]));

    final year2020 = await db.watchTimelineForYear(2020).first;
    expect(year2020.map((a) => a.id).toSet(), {'a2020a', 'a2020b'});
    // Absteigend sortiert.
    expect(year2020.first.id, 'a2020b');
  });

  test('watchAssetCountsByYear zählt korrekt pro Jahr', () async {
    await insertSyntheticAssets(db, 3, baseDate: DateTime(2018, 6, 1));
    await insertSyntheticAssets(db, 5, baseDate: DateTime(2022, 6, 1), idOffset: 100);

    final counts = await db.watchAssetCountsByYear().first;
    expect(counts[2018], 3);
    expect(counts[2022], 5);
    expect(counts.containsKey(2019), isFalse);
  });

  test('newestAssetForYear liefert das zeitlich späteste Foto des Jahres', () async {
    await insertSyntheticAssets(db, 10, baseDate: DateTime(2023, 1, 1));
    final newest = await db.newestAssetForYear(2023);
    expect(newest?.id, 'asset_9'); // base + 9 Minuten = das späteste
  });

  test('newestAssetForYear liefert null für ein Jahr ohne Fotos', () async {
    final newest = await db.newestAssetForYear(1999);
    expect(newest, isNull);
  });

  test('timelineRankOfAsset zählt korrekt, wie viele Fotos neuer sind', () async {
    await insertSyntheticAssets(db, 20, baseDate: DateTime(2024, 1, 1));
    // asset_19 ist das neueste -> Rang 0.
    expect(await db.timelineRankOfAsset('asset_19'), 0);
    // asset_10 hat noch 9 neuere Fotos (asset_11..asset_19) -> Rang 9.
    expect(await db.timelineRankOfAsset('asset_10'), 9);
    // asset_0 ist das älteste -> alle anderen 19 sind neuer.
    expect(await db.timelineRankOfAsset('asset_0'), 19);
  });

  test('timelineRankOfAsset liefert null für ein nicht existierendes Asset', () async {
    expect(await db.timelineRankOfAsset('does-not-exist'), isNull);
  });

  test(
    'watchTimeline(limit:) bleibt auch bei 100.000 Fotos schnell (indexgestützte Seite statt Volllader)',
    () async {
      const total = 100000;
      const batchSize = 5000;
      for (var offset = 0; offset < total; offset += batchSize) {
        await insertSyntheticAssets(db, batchSize, idOffset: offset, baseDate: DateTime(2010, 1, 1));
      }

      final stopwatch = Stopwatch()..start();
      final page = await db.watchTimeline(limit: 500).first;
      stopwatch.stop();

      expect(page, hasLength(500));
      // asset_99999 hat den spätesten Zeitstempel alle Batches zusammen.
      expect(page.first.id, 'asset_99999');
      // ignore: avoid_print
      print('watchTimeline(limit: 500) bei 100.000 Zeilen: ${stopwatch.elapsedMilliseconds} ms');
      // Grosszügige Grenze (die Seite selbst braucht in der Praxis nur
      // wenige Millisekunden dank idx_assets_trashed_locked_created) – bewusst
      // nicht knapper gewählt, um auf einer langsamen/ausgelasteten
      // CI-Maschine nicht flaky zu werden.
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
