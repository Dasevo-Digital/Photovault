import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:photo_vault_server/src/zeilen_json.dart';
import 'package:test/test.dart';

/// Das Merkmal, das der Browser an seine Bildadressen hängt (#259).
///
/// Bis 3.50.0 lud er Miniatur, Ansicht und volle Auflösung nur über die
/// Kennung und durfte sie einen Tag lang behalten: Nach einer Bearbeitung
/// – auch gleich nach dem Speichern im Browser – sah man das alte Bild.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.insertAsset(
      AssetsCompanion.insert(
        id: 'a',
        originalFileName: 'a.heic',
        relativePath: 'originals/a.heic',
        thumbnailRelativePath: const Value('thumbnails/a.jpg'),
        previewRelativePath: const Value('previews/a.jpg'),
        checksum: 'c',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2026),
        importedAt: DateTime(2026),
      ),
    );
  });

  tearDown(() => db.close());

  Future<void> setze(AssetsCompanion c) =>
      (db.update(db.assets)..where((t) => t.id.equals('a'))).write(c);

  Future<String> ausZeile() async {
    final z = await db
        .customSelect("SELECT $rasterSpalten FROM assets WHERE id = 'a'")
        .getSingle();
    return bildstand(Rasterzeile.ausZeile(z));
  }

  Future<String> ausAufnahme() async =>
      bildstand(Rasterzeile.aus((await db.assetById('a'))!));

  test('wechselt mit jeder neuen Fassung, sonst nicht', () async {
    final vorschau = await ausZeile();
    expect(await ausZeile(), vorschau, reason: 'gleich bleibt gleich');
    expect(await ausAufnahme(), vorschau, reason: 'beide Wege rechnen gleich');

    await setze(
      const AssetsCompanion(developedRelativePath: Value('developed/a-1.jpg')),
    );
    final entwickelt = await ausZeile();
    expect(entwickelt, isNot(vorschau));
    expect(await ausAufnahme(), entwickelt);

    await setze(
      const AssetsCompanion(developedRelativePath: Value('developed/a-2.jpg')),
    );
    expect(await ausZeile(), isNot(entwickelt), reason: 'neu entwickelt');

    await setze(
      const AssetsCompanion(thumbnailRelativePath: Value('thumbnails/a-2.jpg')),
    );
    final miniatur = await ausZeile();
    expect(miniatur, isNot(entwickelt), reason: 'neue Miniatur');
    expect(
      (await db.assetById('a'))!.developedRelativePath,
      'developed/a-2.jpg',
    );
  });

  test('steht in jeder Zeile der Schnittstelle', () async {
    final z = zeileAlsJson(Rasterzeile.aus((await db.assetById('a'))!));
    expect(z['stand'], isA<String>());
    expect(z['stand'], hasLength(10));
  });
}
