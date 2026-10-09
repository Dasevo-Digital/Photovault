import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/screens/erinnerungen_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Die Erinnerungsseite: zwei Wochen zurück, Gemerktes, schönste Reisen.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> foto(
    String id,
    DateTime wann, {
    bool favorit = false,
    int sterne = 0,
    bool geraten = false,
    bool papierkorb = false,
  }) => db
      .into(db.assets)
      .insert(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'pruef-$id',
          type: 'IMAGE',
          fileCreatedAt: wann,
          importedAt: DateTime(2026),
          isFavorite: Value(favorit),
          rating: Value(sterne),
          datumGeschaetzt: Value(geraten),
          isTrashed: Value(papierkorb),
        ),
      );

  test('je Tag die früheren Jahre, in einem Durchgang', () async {
    final heute = DateTime(2026, 10, 9);
    final gestern = DateTime(2026, 10, 8);
    await foto('heute2019', DateTime(2019, 10, 9, 14, 3));
    await foto('heute2023', DateTime(2023, 10, 9, 9, 41));
    await foto('gestern2020', DateTime(2020, 10, 8, 18, 12));
    await foto('diesesJahr', DateTime(2026, 10, 8, 11, 5));
    await foto('geraten', DateTime(2018, 10, 9, 10, 7), geraten: true);
    await foto('geloescht', DateTime(2018, 10, 9, 10, 8), papierkorb: true);
    await foto('andererTag', DateTime(2019, 10, 1, 12, 1));

    final jeTag = await db.assetsAnTagen([heute, gestern]);
    expect([for (final a in jeTag[heute]!) a.id], ['heute2023', 'heute2019']);
    expect([for (final a in jeTag[gestern]!) a.id], ['gestern2020']);

    final liste = erinnerungenDerLetztenTage(jeTag);
    expect(
      [for (final e in liste) (e.tag, e.jahreHer)],
      [(heute, 3), (heute, 7), (gestern, 6)],
    );
    expect(erinnerungsKennung(heute, 7), '2019-10-09');
  });

  test('merken hält die Auswahl fest, auch wenn ein Foto wegfällt', () async {
    await foto('a', DateTime(2019, 10, 9, 14, 3));
    await foto('b', DateTime(2019, 10, 9, 15, 3));
    await db.merkeErinnerung(
      id: '2019-10-09',
      titel: '9. Oktober 2019',
      tag: DateTime(2019, 10, 9),
      assetIds: ['b', 'a'],
    );
    final e = (await db.alleGemerktenErinnerungen()).single;
    expect(
      [for (final a in await db.aufnahmenDerErinnerung(e)) a.id],
      ['b', 'a'],
    );
    await db.moveToTrash(['b']);
    expect([for (final a in await db.aufnahmenDerErinnerung(e)) a.id], ['a']);
    await db.vergissErinnerung('2019-10-09');
    expect(await db.alleGemerktenErinnerungen(), isEmpty);
  });

  test('schönste Reisen nach Lieblingsfotos, ohne Lieblinge keine', () async {
    for (final (id, name) in [
      ('r1', 'Venedig'),
      ('r2', 'Harz'),
      ('r3', 'Leer'),
    ]) {
      await db
          .into(db.reisen)
          .insert(
            ReisenCompanion.insert(
              id: id,
              name: name,
              von: DateTime(2024),
              bis: DateTime(2024, 1, 5),
              angelegtAm: DateTime(2026),
            ),
          );
    }
    await foto('v1', DateTime(2024, 1, 1, 10, 1), favorit: true);
    await foto('v2', DateTime(2024, 1, 1, 10, 2), sterne: 5);
    await foto('v3', DateTime(2024, 1, 1, 10, 3));
    await foto('h1', DateTime(2024, 1, 2, 10, 1), sterne: 4);
    await foto('l1', DateTime(2024, 1, 3, 10, 1), sterne: 3);
    for (final (r, a) in [
      ('r1', 'v1'),
      ('r1', 'v2'),
      ('r1', 'v3'),
      ('r2', 'h1'),
      ('r3', 'l1'),
    ]) {
      await db
          .into(db.reiseAufnahmen)
          .insert(ReiseAufnahmenCompanion.insert(reiseId: r, assetId: a));
    }
    final liste = await db.schoensteReisen();
    expect(
      [for (final r in liste) (r.reise.name, r.lieblinge)],
      [('Venedig', 2), ('Harz', 1)],
    );
  });

  test('Migration 88 auf 89 legt die Tabelle an', () async {
    final dir = await Directory.systemTemp.createTemp('photo_vault_v88_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/library.sqlite');
    final initial = AppDatabase(NativeDatabase(file));
    await initial.verwirfDokumentvorschlaege(['x']);
    await initial.close();

    final alt = sqlite.sqlite3.open(file.path);
    alt.execute('DROP TABLE gemerkte_erinnerungen');
    alt.execute('PRAGMA user_version = 88');
    alt.close();

    final neu = AppDatabase(NativeDatabase(file));
    addTearDown(neu.close);
    expect(await neu.alleGemerktenErinnerungen(), isEmpty);
    await neu.merkeErinnerung(
      id: 'x',
      titel: 'x',
      tag: DateTime(2020),
      assetIds: const [],
    );
    expect(await neu.alleGemerktenErinnerungen(), hasLength(1));
  });
}
