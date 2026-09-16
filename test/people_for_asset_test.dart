import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:uuid/uuid.dart';

/// Prüft [AppDatabase.peopleForAsset] – die "Personen"-Sektion der neuen,
/// an Google Fotos angelehnten Info-Ansicht (siehe AssetInfoSheet): liefert
/// nur benannte Personen, deren Gesicht auf GENAU diesem Foto erkannt wurde,
/// ohne Duplikate bei mehreren Gesichtern derselben Person auf einem Foto.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late ImportService import;
  var nextByte = 0;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('photo_vault_people_for_asset_test_');
    db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
    import = ImportService(db, paths);
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<String> importPhoto(String name) async {
    final incoming = Directory(p.join(tempRoot.path, 'incoming'))..createSync(recursive: true);
    final file = File(p.join(incoming.path, name))..writeAsBytesSync([1, 2, 3, nextByte++]);
    final result = await import.importFile(file.path);
    expect(result.outcome, ImportOutcome.imported);
    return result.assetId!;
  }

  Future<String> addFace(String assetId, {String? personId}) async {
    final faceId = const Uuid().v4();
    await db.insertFace(FacesCompanion.insert(
      id: faceId,
      assetId: assetId,
      personId: personId == null ? const Value.absent() : Value(personId),
      boxX: 0,
      boxY: 0,
      boxW: 0.1,
      boxH: 0.1,
    ));
    return faceId;
  }

  test('findet nur Personen mit einem Gesicht auf genau diesem Foto', () async {
    final photoWithAlice = await importPhoto('a.jpg');
    final photoWithoutAlice = await importPhoto('b.jpg');

    final aliceId = const Uuid().v4();
    await db.createPerson(PeopleCompanion.insert(id: aliceId, name: 'Alice'));
    await addFace(photoWithAlice, personId: aliceId);
    await addFace(photoWithoutAlice); // unbenanntes Gesicht, keine Person

    final resultWith = await db.peopleForAsset(photoWithAlice);
    expect(resultWith.map((p) => p.name), ['Alice']);

    final resultWithout = await db.peopleForAsset(photoWithoutAlice);
    expect(resultWithout, isEmpty);
  });

  test('dedupliziert, wenn dieselbe Person mehrfach auf einem Foto markiert ist', () async {
    final photoId = await importPhoto('group.jpg');
    final bobId = const Uuid().v4();
    await db.createPerson(PeopleCompanion.insert(id: bobId, name: 'Bob'));
    await addFace(photoId, personId: bobId);
    await addFace(photoId, personId: bobId);

    final result = await db.peopleForAsset(photoId);
    expect(result.map((p) => p.id), [bobId]);
  });
}
