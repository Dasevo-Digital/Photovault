import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';

/// **Zuordnen und Zusammenführen auf eine Person, die es nicht mehr gibt.**
///
/// Wurde eine Person auf einem anderen Gerät gelöscht oder zusammengeführt,
/// bekamen Gesichter beim Zuordnen ihre alte Kennung und waren danach in
/// keiner Ansicht mehr zu finden. Jetzt wird das abgelehnt.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.insertAsset(
      AssetsCompanion.insert(
        id: 'a',
        originalFileName: 'a.jpg',
        relativePath: 'originals/a.jpg',
        checksum: 'c',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2026),
        importedAt: DateTime(2026),
      ),
    );
    await db
        .into(db.people)
        .insert(PeopleCompanion.insert(id: 'p', name: 'Anna'));
    for (final (id, person) in [('f1', null), ('f2', 'p')]) {
      await db
          .into(db.faces)
          .insert(
            FacesCompanion.insert(
              id: id,
              assetId: 'a',
              boxX: 0.1,
              boxY: 0.1,
              boxW: 0.2,
              boxH: 0.2,
              personId: Value(person),
            ),
          );
    }
  });

  tearDown(() => db.close());

  Future<String?> personVon(String face) async => (await (db.select(
    db.faces,
  )..where((t) => t.id.equals(face))).getSingle()).personId;

  test('Zuordnen zu einer gelöschten Person wird abgelehnt', () async {
    await expectLater(
      db.assignFacesToPerson(['f1'], 'weg'),
      throwsA(isA<StateError>()),
    );
    expect(await personVon('f1'), isNull, reason: 'Gesicht bleibt, wie es war');
    await db.assignFacesToPerson(['f1'], 'p');
    expect(await personVon('f1'), 'p');
  });

  test('Zusammenführen in eine gelöschte Person wird abgelehnt', () async {
    await expectLater(
      db.mergePeople(keepPersonId: 'weg', removePersonId: 'p'),
      throwsA(isA<StateError>()),
    );
    expect(await personVon('f2'), 'p');
  });

  test('Sichere Vorschläge für eine gelöschte Person bleiben offen', () async {
    await db.setVorschlaegeAutomatischAb(0.7);
    await (db.update(db.faces)..where((t) => t.id.equals('f1'))).write(
      const FacesCompanion(
        vorschlagPersonId: Value('weg'),
        vorschlagWert: Value(0.9),
      ),
    );
    expect(await db.uebernimmSichereVorschlaege(['f1']), 0);
    expect(await personVon('f1'), isNull);
  });
}
