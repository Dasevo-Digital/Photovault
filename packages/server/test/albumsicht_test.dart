import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:kern/db/database.dart';
import 'package:photo_vault_server/src/albumsicht.dart';
import 'package:test/test.dart';

/// Zählen und Suchen im Album in der Datenbank (#436) zeigt genau das,
/// was albumAufnahmen zeigt – ohne alle Zeilen des Albums zu laden.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    Future<void> lege(
      String id, {
      String typ = 'IMAGE',
      bool gesperrt = false,
      bool weg = false,
      String? stapel,
      bool deckel = false,
      String? verknuepft,
    }) => db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'pruef-$id',
            type: typ,
            fileCreatedAt: DateTime(2025),
            importedAt: DateTime(2026),
            isLocked: Value(gesperrt),
            isTrashed: Value(weg),
            stackId: Value(stapel),
            isStackCover: Value(deckel),
            linkedAssetId: Value(verknuepft),
          ),
        );
    await lege('sichtbar');
    await lege('gesperrt', gesperrt: true);
    await lege('weg', weg: true);
    await lege('deckel', stapel: 's', deckel: true);
    await lege('darunter', stapel: 's');
    await lege('livevideo', typ: 'VIDEO', verknuepft: 'sichtbar');
    await lege('draussen');
    await db.createAlbum(
      AlbumsCompanion.insert(id: 'a', name: 'A', createdAt: DateTime(2026)),
    );
    await db.addAssetsToAlbum('a', [
      'sichtbar',
      'gesperrt',
      'weg',
      'deckel',
      'darunter',
      'livevideo',
    ]);
  });
  tearDown(() => db.close());

  test('dieselben wie albumAufnahmen', () async {
    final soll = {for (final a in await db.albumAufnahmen('a')) a.id};
    expect(soll, {'sichtbar', 'deckel'});
    expect(await db.sichtbareAnzahl('a'), soll.length);
    const alle = [
      'sichtbar',
      'gesperrt',
      'weg',
      'deckel',
      'darunter',
      'livevideo',
      'draussen',
      'gibtsnicht',
    ];
    expect(await db.sichtbarIn('a', alle), soll);
    for (final id in alle) {
      expect(await db.sichtbarImAlbum('a', id), soll.contains(id), reason: id);
    }
    expect(await db.sichtbareAnzahl('leer'), 0);
    expect(await db.sichtbarIn('a', const []), isEmpty);
  });
}
