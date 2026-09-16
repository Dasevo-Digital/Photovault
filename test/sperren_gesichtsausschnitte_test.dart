import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

/// Was mit dem Profilbild einer Person geschieht, wenn das Foto, aus dem
/// es geschnitten ist, gesperrt wird.
///
/// Die Ausschnittdatei selbst wird beim Sperren mitverschlüsselt – das ist
/// abgedeckt in locked_folder_test.dart und war nie das Problem. Der Pfad
/// im Profilbild zeigt danach aber auf Chiffrat, und die Person verlor
/// ihren Avatar in Erkunden, Personen und Stammbaum. Gefunden in der
/// siebten Prüfrunde.
void main() {
  late Directory tempRoot;
  late AppDatabase db;

  Future<void> gesicht(String faceId, String assetId, {String? person}) async {
    await db.insertFace(FacesCompanion.insert(
      id: faceId,
      assetId: assetId,
      boxX: .1, boxY: .1, boxW: .2, boxH: .2,
      cropRelativePath: Value('faces/$faceId.jpg'),
    ));
    if (person != null) await db.assignFacesToPerson([faceId], person);
  }

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_sperren_');
    db = AppDatabase(NativeDatabase.memory());
    for (final id in ['geheim', 'offen']) {
      await db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'c_$id',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026),
            importedAt: DateTime(2026),
          ));
    }
    await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anna'));
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<PersonData> anna() =>
      (db.select(db.people)..where((t) => t.id.equals('p1'))).getSingle();

  test('das Profilbild weicht auf ein nicht gesperrtes Foto aus', () async {
    await gesicht('f1', 'geheim', person: 'p1');
    await gesicht('f2', 'offen', person: 'p1');
    await db.setPersonCover('p1', 'faces/f1.jpg');

    await db.setAssetsLocked(['geheim'], true);
    expect(await db.verlegeProfilbilderVon(['geheim']), 1);

    expect((await anna()).coverFaceCropPath, 'faces/f2.jpg');
  });

  test('gibt es keinen Ersatz, bleibt die Person ohne Profilbild', () async {
    await gesicht('f1', 'geheim', person: 'p1');
    await db.setPersonCover('p1', 'faces/f1.jpg');

    await db.setAssetsLocked(['geheim'], true);
    await db.verlegeProfilbilderVon(['geheim']);

    // Lieber gar kein Bild als ein Kästchen, das nichts anzeigen kann.
    expect((await anna()).coverFaceCropPath, isNull);
  });

  test('ein Profilbild aus einem anderen Foto bleibt unangetastet', () async {
    await gesicht('f1', 'geheim', person: 'p1');
    await gesicht('f2', 'offen', person: 'p1');
    await db.setPersonCover('p1', 'faces/f2.jpg');

    await db.setAssetsLocked(['geheim'], true);
    expect(await db.verlegeProfilbilderVon(['geheim']), 0);
    expect((await anna()).coverFaceCropPath, 'faces/f2.jpg');
  });

  test('die Gesichtszeile selbst bleibt vollständig', () async {
    // Sie trägt die Zuordnung zur Person und den Pfad, den das Entsperren
    // wieder braucht – hier darf nichts gelöscht werden.
    await gesicht('f1', 'geheim', person: 'p1');
    await db.setPersonCover('p1', 'faces/f1.jpg');

    await db.setAssetsLocked(['geheim'], true);
    await db.verlegeProfilbilderVon(['geheim']);

    final face = (await db.facesForAsset('geheim')).single;
    expect(face.cropRelativePath, 'faces/f1.jpg');
    expect(face.personId, 'p1');
  });

  test('ohne Gesichter passiert nichts', () async {
    expect(await db.verlegeProfilbilderVon(['offen']), 0);
  });
}
