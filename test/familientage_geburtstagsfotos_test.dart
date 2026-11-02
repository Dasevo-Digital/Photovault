import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/rueckblickseite.dart';

/// Ein Geburtstag im Rückblick zeigt Fotos früherer Geburtstage (#272),
/// nicht die neuesten Fotos der Person.
void main() {
  late AppDatabase db;
  var n = 0;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> person(String id, DateTime? geburt) async {
    await db.createPerson(
      PeopleCompanion.insert(id: id, name: id, geburtsdatum: Value(geburt)),
    );
  }

  Future<String> foto(String person, DateTime wann) async {
    final id = 'a${n++}';
    await db.insertAsset(
      AssetsCompanion.insert(
        id: id,
        originalFileName: '$id.jpg',
        relativePath: 'originals/$id.jpg',
        checksum: 'c$id',
        type: 'IMAGE',
        fileCreatedAt: wann,
        importedAt: DateTime(2026),
      ),
    );
    await db
        .into(db.faces)
        .insert(
          FacesCompanion.insert(
            id: 'f$id',
            assetId: id,
            personId: Value(person),
            boxX: 0.1,
            boxY: 0.1,
            boxW: 0.2,
            boxH: 0.2,
          ),
        );
    return id;
  }

  Future<List<String>> fotosAm(DateTime heute) async {
    final tage = await familientageMitFotos(db, heute: heute);
    return [for (final a in tage.single.fotos) a.id];
  }

  test(
    'zuerst die Fotos früherer Geburtstage, höchstens drei je Jahr',
    () async {
      await person('Anna', DateTime(2018, 6, 14));
      final neu = await foto('Anna', DateTime(2026, 6, 10, 9));
      final f24 = [
        for (var h = 10; h < 15; h++)
          await foto('Anna', DateTime(2024, 6, 14, h)),
      ];
      final f22 = await foto('Anna', DateTime(2022, 6, 14, 16));
      final geburt = await foto('Anna', DateTime(2018, 6, 14, 8));

      final ids = await fotosAm(DateTime(2026, 6, 14));

      expect(ids, isNot(contains(neu)), reason: 'kein Geburtstag');
      expect(ids.where(f24.contains), hasLength(3), reason: 'drei je Jahr');
      expect(ids.indexOf(f22), greaterThan(ids.indexOf(f24.last)));
      expect(ids.last, geburt, reason: 'der Tag der Geburt zählt mit');
    },
  );

  test('ohne Geburtstagsfotos bleiben es die neuesten', () async {
    await person('Ben', DateTime(2015, 3, 2));
    final a = await foto('Ben', DateTime(2025, 8, 1));
    final b = await foto('Ben', DateTime(2026, 1, 5));

    expect(await fotosAm(DateTime(2026, 3, 2)), [b, a]);
  });

  test('am 29. Februar Geborene feiern sonst am 28.', () async {
    await person('Cleo', DateTime(2020, 2, 29));
    final x = await foto('Cleo', DateTime(2023, 2, 28, 15));
    await foto('Cleo', DateTime(2024, 2, 28, 15)); // Schaltjahr: kein Fest
    final y = await foto('Cleo', DateTime(2024, 2, 29, 15));

    expect(await fotosAm(DateTime(2026, 2, 28)), [y, x]);
  });
}
