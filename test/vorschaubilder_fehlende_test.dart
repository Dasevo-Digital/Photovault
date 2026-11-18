import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/state/library_state.dart';

/// „Vorschaubilder erzeugen → Fehlende“ fand eine im Bibliotheksordner
/// gelöschte Miniatur nicht: Gefragt wurde nur, ob ihr Pfad in der
/// Datenbank leer ist (IMP-135).
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_vorschau_fehlt_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'l')),
      );
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> aufnahme(String id, {String? miniatur}) => db
      .into(db.assets)
      .insert(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'c$id',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2024),
          importedAt: DateTime(2024),
          thumbnailRelativePath: Value(miniatur),
        ),
      );

  void lege(String relativ) => library.paths.absolute(relativ)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync([1, 2, 3]);

  test('fehlt die Datei einer eingetragenen Miniatur, zählt sie', () async {
    await aufnahme('ohne');
    await aufnahme('da', miniatur: 'thumbnails/da.jpg');
    lege('thumbnails/da.jpg');
    await aufnahme('geloescht', miniatur: 'thumbnails/geloescht.jpg');

    final fehlend = await library.aufnahmenOhneVorschaubild();
    expect(fehlend.map((a) => a.id), unorderedEquals(['ohne', 'geloescht']));
  });

  test('verbunden ist eine fehlende Datei nur noch nicht geholt', () async {
    library.paths.beschaffe = (_) async {};
    await aufnahme('geloescht', miniatur: 'thumbnails/geloescht.jpg');
    expect(await library.aufnahmenOhneVorschaubild(), isEmpty);
  });
}
