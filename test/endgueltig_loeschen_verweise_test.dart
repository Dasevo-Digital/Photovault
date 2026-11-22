import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';

/// **Endgültig löschen räumt alles ab, was an der Aufnahme hängt.**
///
/// SQLite prüft die Fremdschlüssel nicht; bis 3.67 blieben Gesichter,
/// Zuordnungen zu Alben, Schlagwörtern und Reisen, Entwicklungsangaben und
/// Masken einer gelöschten Aufnahme liegen, und Titelbilder zeigten auf
/// nichts.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    for (final id in ['weg', 'bleibt']) {
      await db.insertAsset(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'c-$id',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2026),
          importedAt: DateTime(2026),
        ),
      );
    }
    await db
        .into(db.people)
        .insert(
          PeopleCompanion.insert(
            id: 'p',
            name: 'Anna',
            coverFaceCropPath: const Value('faces/f-weg.jpg'),
          ),
        );
    for (final (id, asset) in [('f-weg', 'weg'), ('f-bleibt', 'bleibt')]) {
      await db
          .into(db.faces)
          .insert(
            FacesCompanion.insert(
              id: id,
              assetId: asset,
              boxX: 0.1,
              boxY: 0.1,
              boxW: 0.2,
              boxH: 0.2,
              personId: const Value('p'),
              cropRelativePath: Value('faces/$id.jpg'),
            ),
          );
    }
    await db
        .into(db.albums)
        .insert(
          AlbumsCompanion.insert(
            id: 'a',
            name: 'Urlaub',
            createdAt: DateTime(2026),
            coverAssetId: const Value('weg'),
          ),
        );
    await db
        .into(db.tags)
        .insert(TagsCompanion.insert(id: 't', name: 'Strand'));
    await db
        .into(db.reisen)
        .insert(
          ReisenCompanion.insert(
            id: 'r',
            name: 'Sommer',
            von: DateTime(2026),
            bis: DateTime(2026, 1, 5),
            angelegtAm: DateTime(2026),
            titelbildAssetId: const Value('weg'),
          ),
        );
    for (final asset in ['weg', 'bleibt']) {
      await db
          .into(db.albumAssets)
          .insert(AlbumAssetsCompanion.insert(albumId: 'a', assetId: asset));
      await db
          .into(db.assetTags)
          .insert(AssetTagsCompanion.insert(assetId: asset, tagId: 't'));
      await db
          .into(db.reiseAufnahmen)
          .insert(ReiseAufnahmenCompanion.insert(reiseId: 'r', assetId: asset));
      await db
          .into(db.developMasks)
          .insert(
            DevelopMasksCompanion.insert(
              assetId: asset,
              maskRelativePath: 'masks/$asset.png',
              label: 'Himmel',
              createdAt: DateTime(2026),
            ),
          );
    }
  });

  tearDown(() => db.close());

  Future<List<String>> spalte(String sql) async => [
    for (final z in await db.customSelect(sql).get()) '${z.data.values.first}',
  ];

  test('Gesichter, Zuordnungen und Masken gehen mit', () async {
    await db.deleteAssetRows(['weg']);
    expect(await spalte('SELECT asset_id FROM faces'), ['bleibt']);
    expect(await spalte('SELECT asset_id FROM album_assets'), ['bleibt']);
    expect(await spalte('SELECT asset_id FROM asset_tags'), ['bleibt']);
    expect(await spalte('SELECT asset_id FROM reise_aufnahmen'), ['bleibt']);
    expect(await spalte('SELECT asset_id FROM develop_masks'), ['bleibt']);
  });

  test('Titelbilder zeigen danach nicht ins Leere', () async {
    await db.deleteAssetRows(['weg']);
    expect(await spalte('SELECT cover_asset_id FROM albums'), [
      'null',
    ], reason: 'Album ohne gewähltes Titelbild statt mit einem gelöschten');
    expect(await spalte('SELECT titelbild_asset_id FROM reisen'), ['null']);
    expect(await spalte('SELECT cover_face_crop_path FROM people'), [
      'faces/f-bleibt.jpg',
    ], reason: 'ein anderes Gesicht der Person übernimmt das Profilbild');
  });
  test('Reste aus älteren Fassungen räumt das nächste Löschen weg', () async {
    // So hinterliess es das Löschen bis 3.67: die Aufnahme weg, ihre
    // Zeilen noch da.
    await db.customStatement("DELETE FROM assets WHERE id = 'weg'");
    expect(await spalte('SELECT count(*) FROM faces'), ['2']);
    await db.raeumeVerwaisteZeilen();
    expect(await spalte('SELECT asset_id FROM faces'), ['bleibt']);
    expect(await spalte('SELECT asset_id FROM album_assets'), ['bleibt']);
    expect(await spalte('SELECT asset_id FROM asset_tags'), ['bleibt']);
    expect(await spalte('SELECT asset_id FROM reise_aufnahmen'), ['bleibt']);
    expect(await spalte('SELECT asset_id FROM develop_masks'), ['bleibt']);
    expect(await spalte('SELECT cover_asset_id FROM albums'), ['null']);
    expect(await spalte('SELECT titelbild_asset_id FROM reisen'), ['null']);
  });
}
