import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_service.dart';
import 'package:path/path.dart' as p;

/// SQLite nimmt je Anweisung höchstens 32766 Werte (#311). Darüber scheiterte
/// die erste Sicherung einer grossen Bibliothek, nachdem alle Dateien kopiert
/// waren; der Betrachter und das Leeren des Papierkorbs ebenso.
void main() {
  late AppDatabase db;
  final viele = [for (var i = 0; i < 40000; i++) 'gibt-es-nicht-$i'];

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> lege(String id, {String? partner}) => db.insertAsset(
    AssetsCompanion.insert(
      id: id,
      originalFileName: '$id.jpg',
      relativePath: 'originals/$id.jpg',
      checksum: id,
      type: 'IMAGE',
      fileCreatedAt: DateTime(2026),
      importedAt: DateTime(2026),
      linkedAssetId: Value(partner),
    ),
  );

  test('Portionen decken alles ab, ohne etwas doppelt zu nehmen', () {
    final stuecke = inStuecken(viele).toList();
    expect(stuecke, hasLength(4));
    expect(stuecke.expand((x) => x), viele);
    expect(inStuecken(<String>[]), isEmpty);
  });

  test('Massenänderungen vertragen mehr Werte, als SQLite nimmt', () async {
    await db.markBackedUp(viele);
    await db.markAutoBackedUp(viele);
    await db.setFavoriteBulk(viele, true);
    await db.setRatingBulk(viele, 3);
    await db.setColorLabelBulk(viele, 'rot');
    expect(await db.assetsByIds(viele), isEmpty);
    await db.moveToTrash(viele);
    await db.restoreFromTrash(viele);
    await db.deleteAssetRows(viele);
  });

  test('die Reihenfolge bleibt, und Partner finden sich', () async {
    await lege('b');
    await lege('a', partner: 'b');
    final mit = [...viele, 'a', 'b'];
    expect((await db.assetsByIds(mit)).map((x) => x.id), ['a', 'b']);
    expect(await db.zugehoerige(['b']), {'a', 'b'});
    await db.moveToTrash(['a']);
    expect((await db.assetById('b'))!.isTrashed, isTrue);
  });

  test('die Einschränkung einer Suche verträgt mehr als 32766 Treffer', () async {
    await lege('a');
    final treffer = await db
        .customSelect(
          'SELECT 1 AS x FROM assets WHERE id IN (SELECT value FROM json_each(?))',
          variables: [const Variable<String>('["a"]')],
        )
        .get();
    expect(treffer, hasLength(1));
    final q = db.select(db.assets)
      ..where((t) => kennungIn(t.id, [...viele, 'a']));
    expect((await q.get()).map((x) => x.id), ['a']);
  });

  test('Titelbilder aller Alben wie je Album einzeln', () async {
    await lege('alt');
    await lege('neu');
    await lege('fremd');
    await (db.update(db.assets)..where((t) => t.id.equals('neu'))).write(
      AssetsCompanion(fileCreatedAt: Value(DateTime(2027))),
    );
    await (db.update(db.assets)..where((t) => t.id.equals('fremd'))).write(
      const AssetsCompanion(isLocked: Value(true)),
    );
    await db
        .into(db.albums)
        .insert(
          AlbumsCompanion.insert(
            id: 'ohne',
            name: 'x',
            createdAt: DateTime(2026),
          ),
        );
    await db
        .into(db.albums)
        .insert(
          AlbumsCompanion.insert(
            id: 'mit',
            name: 'y',
            createdAt: DateTime(2026),
            coverAssetId: const Value('alt'),
          ),
        );
    await db
        .into(db.albums)
        .insert(
          AlbumsCompanion.insert(
            id: 'gesperrt',
            name: 'z',
            createdAt: DateTime(2026),
            coverAssetId: const Value('fremd'),
          ),
        );
    await db.addAssetsToAlbum('ohne', ['alt', 'neu']);
    await db.addAssetsToAlbum('mit', ['alt', 'neu']);
    await db.addAssetsToAlbum('gesperrt', ['fremd', 'alt']);
    final alben = await db.select(db.albums).get();
    final titel = await db.albumTitelbilder(alben);
    for (final a in alben) {
      expect(titel[a.id], (await db.albumTitelbild(a))?.id, reason: a.id);
    }
    expect(titel, {'ohne': 'neu', 'mit': 'alt', 'gesperrt': 'alt'});
  });

  test('Anzahlen zählen verwaiste Einträge nicht mit', () async {
    await lege('a');
    await db.addAssetsToAlbum('album', ['a', 'gibt-es-nicht']);
    expect(await db.albumAnzahlen(), {'album': 1});
  });

  test('ein Live Photo findet seinen Partner über den Namen', () async {
    await lege('IMG_1');
    await db
        .update(db.assets)
        .write(const AssetsCompanion(type: Value('VIDEO')));
    await (db.update(db.assets)..where((t) => t.id.equals('IMG_1'))).write(
      const AssetsCompanion(originalFileName: Value('IMG_1.MOV')),
    );
    await lege('IMG_10');
    await (db.update(db.assets)..where((t) => t.id.equals('IMG_10'))).write(
      const AssetsCompanion(
        originalFileName: Value('IMG_10.MOV'),
        type: Value('VIDEO'),
      ),
    );
    final treffer = await db.unverknuepfteMitStamm('VIDEO', 'img_1');
    expect(treffer.map((x) => x.id), ['IMG_1']);
  });

  test('die Reparatur findet Stapel ohne sichtbares Titelbild', () async {
    await lege('titel');
    await lege('mitglied');
    await (db.update(db.assets)..where((t) => t.id.equals('titel'))).write(
      const AssetsCompanion(
        stackId: Value('serie'),
        isStackCover: Value(true),
        isTrashed: Value(true),
      ),
    );
    await (db.update(db.assets)..where((t) => t.id.equals('mitglied'))).write(
      const AssetsCompanion(stackId: Value('serie')),
    );
    expect(await db.repariereVerdeckteZugehoerige(), 1);
    expect((await db.assetById('mitglied'))!.isStackCover, isTrue);
    expect(await db.repariereVerdeckteZugehoerige(), 0);
  });

  group('Pfade in der Sicherung', () {
    test('beide Trennzeichen, egal wo sie laufen', () {
      final erwartet = p.join('2024', '05', 'a.jpg');
      expect(pfadInDerSicherung('originals/2024/05/a.jpg'), erwartet);
      expect(pfadInDerSicherung(r'originals\2024\05\a.jpg'), erwartet);
    });
    test('ohne den Ordner bleibt der Pfad', () {
      expect(pfadInDerSicherung('a.jpg'), 'a.jpg');
    });
  });
}
