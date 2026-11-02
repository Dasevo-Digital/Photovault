import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/entwicklung_ablegen.dart';

/// Jede Entwicklung bekommt einen neuen Namen (#258).
///
/// Bis 3.50.0 schrieb der Rechner jedes Mal `developed/<id>.jpg`.
/// Verbundene Geräte holen eine Datei nur, wenn sie unter ihrem Namen
/// fehlt – nach erneutem Entwickeln am Mac zeigte das Handy deshalb
/// dauerhaft die alte Fassung.
void main() {
  late Directory ordner;
  late AppDatabase db;
  late StoragePaths paths;
  late List<String> abgelegt;

  setUp(() async {
    ordner = Directory.systemTemp.createTempSync('pv_entw_ablegen_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(
      Directory(p.join(ordner.path, 'lib')),
    );
    abgelegt = [];
    // Wie in einer verbundenen Kopie: Jede Datei geht zum Server.
    paths.ablege = (relativ) async => abgelegt.add(relativ);
    await db.insertAsset(
      AssetsCompanion.insert(
        id: 'a',
        originalFileName: 'a.heic',
        relativePath: 'originals/a.heic',
        checksum: 'c',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2026),
        importedAt: DateTime(2026),
      ),
    );
  });

  tearDown(() async {
    await db.close();
    ordner.deleteSync(recursive: true);
  });

  DevelopSettingsCompanion werte(double belichtung) =>
      DevelopSettingsCompanion.insert(
        assetId: 'a',
        exposure: Value(belichtung),
        updatedAt: DateTime.now(),
      );

  Future<String> lege(int inhalt, double belichtung) => legeEntwicklungAb(
    db: db,
    paths: paths,
    assetId: 'a',
    jpeg: Uint8List.fromList([inhalt]),
    einstellungen: werte(belichtung),
  );

  Future<String?> eingetragen() async =>
      (await db.assetById('a'))?.developedRelativePath;

  test('zweimal entwickeln ergibt zwei Namen, die alte Datei geht', () async {
    final erst = await lege(1, 0.5);
    final dann = await lege(2, 1.0);

    expect(erst, startsWith('developed/a-'));
    expect(dann, startsWith('developed/a-'));
    expect(dann, isNot(erst), reason: 'sonst holt kein Gerät die neue');
    expect(abgelegt, [erst, dann], reason: 'jede Fassung zum Server');
    expect(await eingetragen(), dann);
    expect(paths.absolute(dann).readAsBytesSync(), [2]);
    expect(paths.absolute(erst).existsSync(), isFalse);
    expect((await db.developSettingsForAsset('a'))?.exposure, 1.0);
  });

  test('die Datei mit dem festen Namen bis 3.50.0 geht ebenso', () async {
    paths.absolute('developed/a.jpg')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([9]);
    await (db.update(db.assets)..where((t) => t.id.equals('a'))).write(
      const AssetsCompanion(developedRelativePath: Value('developed/a.jpg')),
    );

    final neu = await lege(3, 0.7);

    expect(await eingetragen(), neu);
    expect(paths.absolute('developed/a.jpg').existsSync(), isFalse);
  });

  test('nimmt der Server die Datei nicht, bleibt alles beim Alten', () async {
    final erst = await lege(1, 0.5);
    paths.ablege = (_) async => throw const SocketException('weg');

    await expectLater(lege(2, 1.0), throwsA(isA<EntwicklungNichtAbgelegt>()));

    expect(await eingetragen(), erst);
    expect(paths.absolute(erst).existsSync(), isTrue);
    expect(paths.developedDir.listSync().map((e) => p.basename(e.path)), [
      p.basename(erst),
    ], reason: 'die neue Datei ist wieder weg');
  });

  test('ausserhalb von developed/ wird nie etwas gelöscht', () async {
    final original = paths.absolute('originals/a.heic')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([5]);
    await (db.update(db.assets)..where((t) => t.id.equals('a'))).write(
      const AssetsCompanion(developedRelativePath: Value('originals/a.heic')),
    );

    await lege(4, 0.2);

    expect(original.existsSync(), isTrue);
  });
}
