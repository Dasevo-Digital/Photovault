import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/search_filters.dart';

/// Das Archiv (#304): aus der Zeitleiste und den Erinnerungen, aber in
/// Alben, Favoriten und Suche weiter da.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  final zeit = DateTime(2024, 6, 1, 12);

  Future<void> lege(
    String id, {
    String? name,
    DateTime? am,
    bool favorit = false,
    bool archiv = false,
  }) => db.insertAsset(
    AssetsCompanion.insert(
      id: id,
      originalFileName: name ?? '$id.jpg',
      relativePath: 'originals/$id',
      checksum: id,
      type: 'IMAGE',
      fileCreatedAt: am ?? zeit,
      importedAt: zeit,
      dateiformat: Value((name ?? '$id.jpg').split('.').last.toLowerCase()),
      isFavorite: Value(favorit),
      isArchived: Value(archiv),
    ),
  );

  Future<Set<String>> zeitleiste() async => {
    for (final z in await db.watchRasterzeilen().first) z.id,
  };
  Future<Set<String>> imArchiv() async => {
    for (final z in await db.watchRasterzeilen(archiv: true).first) z.id,
  };

  test('archivieren nimmt aus der Zeitleiste, nicht aus Favoriten', () async {
    await lege('a', favorit: true);
    await lege('b');
    await db.fuehreAus(const ArchivSetzen(['a'], true));
    expect(await zeitleiste(), {'b'});
    expect(await imArchiv(), {'a'});
    expect(
      {
        for (final z in await db.watchRasterzeilen(favoritesOnly: true).first)
          z.id,
      },
      {'a'},
    );
    expect({for (final a in await db.watchTimeline().first) a.id}, {'b'});
    expect(
      {for (final a in await db.watchTimeline(archiv: true).first) a.id},
      {'a'},
    );
    await db.fuehreAus(const ArchivSetzen(['a'], false));
    expect(await zeitleiste(), {'a', 'b'});
    expect(await imArchiv(), isEmpty);
  });

  test('Alben und Suche zeigen das Archiv weiter', () async {
    await lege('a', archiv: true);
    await lege('b');
    await db
        .into(db.albums)
        .insert(AlbumsCompanion.insert(id: 'al', name: 'A', createdAt: zeit));
    await db.addAssetsToAlbum('al', ['a', 'b']);
    expect(
      {for (final a in await db.assetsInAlbumOnce('al')) a.id},
      {'a', 'b'},
    );
    expect(
      {
        for (final a in await db.searchAssets(
          const SearchFilters(nurArchiv: true),
        ))
          a.id,
      },
      {'a'},
    );
  });

  test('Monate, Jahre und Erinnerungen ohne Archiv', () async {
    // Nicht auf voller Stunde: Solche Zeiten gelten als geraten.
    await lege('a', archiv: true, am: DateTime(2020, 6, 1, 12, 34, 56));
    await lege('b', am: DateTime(2020, 6, 2, 12, 34, 56));
    expect((await db.watchAssetCountsByMonth(2020).first)[6], 1);
    expect(
      {for (final a in await db.watchTimelineForMonth(2020, 6).first) a.id},
      {'b'},
    );
    expect({
      for (final a in await db.assetsOnThisDay(DateTime(2026, 6, 1))) a.id,
    }, isEmpty);
    expect(
      {for (final a in await db.assetsOnThisDay(DateTime(2026, 6, 2))) a.id},
      {'b'},
    );
  });

  test(
    'ein neues Titelbild übernimmt, ob der Stapel im Archiv liegt',
    () async {
      await lege('a', archiv: true);
      await lege('b');
      await db.fuehreAus(const VariantenBilden('v', ['a', 'b'], 'a'));
      expect(await zeitleiste(), isEmpty);
      await db.fuehreAus(const VariantenHauptbildSetzen('variante:v', 'b'));
      expect(await zeitleiste(), isEmpty, reason: 'weiter im Archiv');
      expect(await imArchiv(), {'b'});
    },
  );

  test('aufgelöst bleibt im Archiv, was im Stapel dort lag (#372)', () async {
    await lege('a');
    await lege('b');
    await lege('c');
    await lege('d');
    await db.fuehreAus(const VariantenBilden('v', ['a', 'b'], 'a'));
    await db.fuehreAus(const SerieBilden('s', ['c', 'd'], 'c'));
    await db.fuehreAus(const ArchivSetzen(['a', 'c'], true));
    await db.fuehreAus(const VariantenAufloesen('variante:v'));
    await db.fuehreAus(const SerieAufloesen('s'));
    expect(await zeitleiste(), isEmpty);
    expect(await imArchiv(), {'a', 'b', 'c', 'd'});
  });

  test(
    'was vor dem Stapeln im Archiv lag, bleibt beim Auflösen dort',
    () async {
      await lege('a', archiv: true);
      await lege('b');
      await db.fuehreAus(const VariantenBilden('v', ['a', 'b'], 'b'));
      expect(await zeitleiste(), {'b'});
      await db.fuehreAus(const VariantenAufloesen('variante:v'));
      expect(await zeitleiste(), {'b'});
      expect(await imArchiv(), {'a'});
    },
  );

  test('Formatstapel liegen nur im Archiv, wenn alles dort lag', () async {
    await lege('h', name: 'IMG_1.HEIC', archiv: true);
    await lege('j', name: 'IMG_1.JPG');
    await db.stapleFormate();
    expect(await zeitleiste(), {'h'}, reason: 'das JPG war zu sehen');
    await lege('h2', name: 'IMG_2.HEIC', archiv: true);
    await lege('j2', name: 'IMG_2.JPG', archiv: true);
    await db.stapleFormate();
    expect(await imArchiv(), {'h2'});
  });

  test('der Zeitleistenindex trägt das Archiv mit', () async {
    Future<Set<String>> spalten() async => {
      for (final z
          in await db
              .customSelect(
                "SELECT name FROM pragma_index_info('idx_assets_sichtbar')",
              )
              .get())
        z.read<String>('name'),
    };
    expect(await spalten(), contains('is_archived'));
    // Ein Index von davor wird ersetzt.
    await db.customStatement('DROP INDEX idx_assets_sichtbar');
    await db.customStatement(
      'CREATE INDEX idx_assets_sichtbar ON assets (is_trashed, is_locked, '
      'file_created_at DESC, id DESC, type, linked_asset_id, stack_id, '
      'is_stack_cover)',
    );
    expect(await spalten(), isNot(contains('is_archived')));
    await db.indizesOhneStufe();
    expect(await spalten(), contains('is_archived'));
  });
}
