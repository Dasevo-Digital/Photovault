import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> asset(
    String id, {
    bool favorit = false,
    int bewertung = 0,
    String? beschreibung,
    String? farbe,
  }) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'checksum_$id',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 1, 1),
            importedAt: DateTime(2026, 1, 1),
            isFavorite: Value(favorit),
            rating: Value(bewertung),
            description: Value(beschreibung),
            colorLabel: Value(farbe),
          ));

  test('vereinigt Metadaten und legt nur die Kopie in den Papierkorb',
      () async {
    await asset('behalten', beschreibung: 'Hauptnotiz');
    await asset('kopie',
        favorit: true,
        bewertung: 4,
        beschreibung: 'Zusatznotiz',
        farbe: 'blue');
    await db.createAlbum(AlbumsCompanion.insert(
        id: 'urlaub', name: 'Urlaub', createdAt: DateTime(2026)));
    await db.addAssetsToAlbum('urlaub', ['kopie']);
    await db.tagAsset('behalten', 'Meer', quelle: Tagquelle.ki);
    await db.tagAsset('kopie', 'Meer');
    await db.tagAsset('kopie', 'Sonnenuntergang');

    await db.fuehreDuplikateZusammen(
        behaltenId: 'behalten', duplikatIds: ['behalten', 'kopie']);

    final behalten = (await db.assetById('behalten'))!;
    final kopie = (await db.assetById('kopie'))!;
    expect(behalten.isFavorite, isTrue);
    expect(behalten.rating, 4);
    expect(behalten.colorLabel, 'blue');
    expect(behalten.description, 'Hauptnotiz\n\nZusatznotiz');
    expect(kopie.isTrashed, isTrue);
    expect(
        (await db.assetsInAlbumOnce('urlaub')).map((a) => a.id), ['behalten']);
    expect((await db.tagsForAsset('behalten')).map((tag) => tag.name),
        containsAll(['Meer', 'Sonnenuntergang']));
    final meer = await db.tagsForAsset('behalten');
    expect(meer.where((tag) => tag.name == 'Meer'), hasLength(1));
  });
}
