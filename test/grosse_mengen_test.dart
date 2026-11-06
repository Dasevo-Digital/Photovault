import 'package:drift/drift.dart' show Value;
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
