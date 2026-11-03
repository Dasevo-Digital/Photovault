import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/bearbeitung_zuruecknehmen.dart';
import 'package:photo_vault/services/entwicklung_ablegen.dart';

/// Restaurierung und KI-Entrauschen gehen wie eine Entwicklung zum Server,
/// jedes Ergebnis unter einem neuen Namen (#284).
///
/// Bis 3.52 schrieb der Rechner jedes Ergebnis nach `restored/<id>.jpg`
/// und trug es nur bei sich ein. In einer verbundenen Bibliothek sahen
/// Handy und Browser eine Restaurierung deshalb nie, und ein Gerät, das
/// die Datei schon hatte, holte die neue nicht.
void main() {
  late Directory ordner;
  late AppDatabase db;
  late StoragePaths paths;
  late List<String> abgelegt;
  late List<String> befehle;

  setUp(() async {
    ordner = Directory.systemTemp.createTempSync('pv_rest_ablegen_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(
      Directory(p.join(ordner.path, 'lib')),
    );
    abgelegt = [];
    befehle = [];
    // Wie in einer verbundenen Kopie: Jede Datei geht zum Server, und
    // jeder Befehl auch.
    paths.ablege = (relativ) async => abgelegt.add(relativ);
    db.befehlsbeobachter.add((b) => befehle.add(b.art));
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

  Future<String> lege(int inhalt) => legeRestaurierungAb(
    db: db,
    paths: paths,
    assetId: 'a',
    jpeg: Uint8List.fromList([inhalt]),
  );

  Future<String?> eingetragen() async =>
      (await db.assetById('a'))?.restoredRelativePath;

  test('zweimal restaurieren ergibt zwei Namen, die alte Datei geht', () async {
    final erst = await lege(1);
    final dann = await lege(2);

    expect(erst, startsWith('restored/a-'));
    expect(dann, isNot(erst), reason: 'sonst holt kein Gerät die neue');
    expect(abgelegt, [erst, dann], reason: 'jede Fassung zum Server');
    expect(befehle, ['restaurierungSpeichern', 'restaurierungSpeichern']);
    expect(await eingetragen(), dann);
    expect(paths.absolute(dann).readAsBytesSync(), [2]);
    expect(paths.absolute(erst).existsSync(), isFalse);
  });

  test('die Datei mit dem festen Namen bis 3.52 geht ebenso', () async {
    paths.absolute('restored/a.jpg')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([9]);
    await db.fuehreAus(const RestaurierungSpeichern('a', 'restored/a.jpg'));

    final neu = await lege(3);

    expect(await eingetragen(), neu);
    expect(paths.absolute('restored/a.jpg').existsSync(), isFalse);
  });

  test('nimmt der Server die Datei nicht, bleibt alles beim Alten', () async {
    final erst = await lege(1);
    paths.ablege = (_) async => throw const SocketException('weg');

    await expectLater(lege(2), throwsA(isA<EntwicklungNichtAbgelegt>()));

    expect(await eingetragen(), erst);
    expect(paths.restoredDir.listSync().map((e) => p.basename(e.path)), [
      p.basename(erst),
    ], reason: 'die neue Datei ist wieder weg');
  });

  test('ausserhalb von restored/ wird nie etwas gelöscht', () async {
    final entwickelt = paths.absolute('developed/a-1.jpg')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([5]);
    await (db.update(db.assets)..where((t) => t.id.equals('a'))).write(
      const AssetsCompanion(restoredRelativePath: Value('developed/a-1.jpg')),
    );

    await lege(4);

    expect(entwickelt.existsSync(), isTrue);
  });

  test('zurücknehmen geht ebenfalls als Befehl', () async {
    final pfad = await lege(1);
    befehle.clear();

    await originalWiederherstellen(
      db: db,
      paths: paths,
      asset: (await db.assetById('a'))!,
    );

    expect(befehle, ['restaurierungZuruecksetzen']);
    expect(await eingetragen(), isNull);
    expect(paths.absolute(pfad).existsSync(), isFalse);
  });
}
