import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

/// **Das Titelbild eines Albums.**
///
/// Aus dem Bericht: "Titelbild setzen ist nicht moeglich." Die Spalte
/// `coverAssetId` stand seit dem ersten Commit in der Tabelle - gelesen
/// und geschrieben hat sie niemand, und in der Uebersicht sahen zwanzig
/// Alben aus wie zwanzigmal dasselbe Symbol.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<String> aufnahme(String id, DateTime wann) async {
    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'c_$id',
          type: 'IMAGE',
          fileCreatedAt: wann,
          importedAt: DateTime(2026, 1, 1),
        ));
    return id;
  }

  Future<AlbumData> album(String id, {List<String> mit = const []}) async {
    await db.createAlbum(AlbumsCompanion.insert(
        id: id, name: 'Album $id', createdAt: DateTime(2026, 1, 1)));
    if (mit.isNotEmpty) await db.addAssetsToAlbum(id, mit);
    return (await db.watchAlbums().first).firstWhere((a) => a.id == id);
  }

  test('ein leeres Album hat kein Titelbild', () async {
    expect(await db.albumTitelbild(await album('a')), isNull);
  });

  test('ohne Wahl steht die neueste Aufnahme vorn', () async {
    await aufnahme('alt', DateTime(2025, 5, 1));
    await aufnahme('neu', DateTime(2026, 5, 1));
    final a = await album('a', mit: ['alt', 'neu']);
    expect((await db.albumTitelbild(a))!.id, 'neu');
  });

  test('die Wahl schlaegt die Reihenfolge', () async {
    await aufnahme('alt', DateTime(2025, 5, 1));
    await aufnahme('neu', DateTime(2026, 5, 1));
    await album('a', mit: ['alt', 'neu']);
    await db.setzeAlbumTitelbild('a', 'alt');
    final a = (await db.watchAlbums().first).first;
    expect(a.coverAssetId, 'alt');
    expect((await db.albumTitelbild(a))!.id, 'alt');
  });

  test('ein Titelbild, das nicht mehr im Album liegt, wirbt nicht weiter',
      () async {
    await aufnahme('raus', DateTime(2025, 5, 1));
    await aufnahme('drin', DateTime(2024, 5, 1));
    await album('a', mit: ['raus', 'drin']);
    await db.setzeAlbumTitelbild('a', 'raus');
    await db.removeAssetFromAlbum('a', 'raus');
    final a = (await db.watchAlbums().first).first;
    // Die Wahl steht noch in der Spalte - gezeigt wird sie nicht mehr.
    expect(a.coverAssetId, 'raus');
    expect((await db.albumTitelbild(a))!.id, 'drin');
  });

  test('ein Titelbild im Papierkorb faellt zurueck', () async {
    await aufnahme('weg', DateTime(2026, 5, 1));
    await aufnahme('da', DateTime(2024, 5, 1));
    await album('a', mit: ['weg', 'da']);
    await db.setzeAlbumTitelbild('a', 'weg');
    await (db.update(db.assets)..where((t) => t.id.equals('weg')))
        .write(const AssetsCompanion(isTrashed: Value(true)));
    final a = (await db.watchAlbums().first).first;
    expect((await db.albumTitelbild(a))!.id, 'da');
  });

  test('die Wahl laesst sich zuruecknehmen', () async {
    await aufnahme('alt', DateTime(2025, 5, 1));
    await aufnahme('neu', DateTime(2026, 5, 1));
    await album('a', mit: ['alt', 'neu']);
    await db.setzeAlbumTitelbild('a', 'alt');
    await db.setzeAlbumTitelbild('a', null);
    final a = (await db.watchAlbums().first).first;
    expect(a.coverAssetId, isNull);
    expect((await db.albumTitelbild(a))!.id, 'neu');
  });
}
