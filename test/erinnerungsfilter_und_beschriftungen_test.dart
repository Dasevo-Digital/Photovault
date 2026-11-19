import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/beschriftungsvorschlaege.dart';
import 'package:kern/services/erinnerungsfilter.dart';
import 'package:kern/services/rueckblickseite.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  late AppDatabase db;
  late Beschriftungsdienst dienst;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dienst = Beschriftungsdienst(db);
  });
  tearDown(() => db.close());

  Future<void> foto(String id, DateTime datum) async {
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: '$id.jpg',
            checksum: id,
            type: 'IMAGE',
            fileCreatedAt: datum,
            importedAt: DateTime(2026),
            isFavorite: const Value(true),
            datumGeschaetzt: const Value(false),
          ),
        );
  }

  Future<void> album() async {
    await foto('a', DateTime(2020, 11, 19, 12, 3));
    await db.fuehreAus(AlbumAnlegen('familie', 'Familie', DateTime(2026)));
    await db.fuehreAus(const AlbumFuellen('familie', ['a']));
  }

  Future<String> vorschlag(String art, String wert, {String? gesicht}) =>
      dienst.vorschlagen(
        id: 'a',
        album: 'familie',
        von: 'gast',
        name: 'Gast',
        art: art,
        wert: wert,
        gesicht: gesicht,
      );

  test(
    'Person, Album und beide Datumsgrenzen gelten auch für gemerkte Rückblicke',
    () async {
      for (final (id, datum) in [
        ('person', DateTime(2020, 11, 19, 10)),
        ('album', DateTime(2020, 11, 19, 11)),
        ('anfang', DateTime(2020, 11, 19)),
        ('ende', DateTime(2020, 11, 20, 23, 59, 59)),
        ('davor', DateTime(2020, 11, 18, 23, 59)),
        ('danach', DateTime(2020, 11, 21)),
        ('frei', DateTime(2019, 11, 19, 12, 3)),
      ]) {
        await foto(id, datum);
      }
      await db.fuehreAus(const PersonAnlegen('p', 'Person'));
      await db.insertFace(
        FacesCompanion.insert(
          id: 'f',
          assetId: 'person',
          boxX: 0,
          boxY: 0,
          boxW: .2,
          boxH: .2,
          personId: const Value('p'),
        ),
      );
      await db.fuehreAus(AlbumAnlegen('privat', 'Privat', DateTime(2026)));
      await db.fuehreAus(const AlbumFuellen('privat', ['album']));
      final filter = Erinnerungsfilter(
        personen: ['p'],
        alben: ['privat'],
        zeitraeume: [(von: '2020-11-19', bis: '2020-11-20')],
      );
      final b = ErinnerungsfilterSetzen(filter);
      await db.fuehreAus(Befehl.ausJson(b.alsJson()));
      expect((await db.erinnerungsfilter()).alsJson(), filter.alsJson());
      expect(
        (await db.assetsOnThisDay(DateTime(2026, 11, 19))).map((a) => a.id),
        ['frei'],
      );
      expect((await jahresinhalt(db, 2020)).auswahl.map((a) => a.id).toSet(), {
        'davor',
        'danach',
      });
      await db.merkeErinnerung(
        id: 'm',
        titel: 'Gemerkte Auswahl',
        tag: DateTime(2020),
        assetIds: ['ende', 'frei', 'person', 'davor'],
      );
      final m = (await db.alleGemerktenErinnerungen()).single;
      expect((await db.aufnahmenDerErinnerung(m)).map((a) => a.id), [
        'frei',
        'davor',
      ]);
      expect(await db.select(db.assets).get(), hasLength(7));
      await db.setzeErinnerungsfilter(Erinnerungsfilter());
      expect((await db.aufnahmenDerErinnerung(m)).map((a) => a.id), [
        'ende',
        'frei',
        'person',
        'davor',
      ]);
    },
  );

  test(
    'Personen- und Albumausschluss wirken unabhängig von Zeiträumen',
    () async {
      await album();
      await foto('b', DateTime(2020, 11, 19, 13, 3));
      await db.fuehreAus(const PersonAnlegen('p', 'Person'));
      await db.insertFace(
        FacesCompanion.insert(
          id: 'f',
          assetId: 'b',
          boxX: 0,
          boxY: 0,
          boxW: .2,
          boxH: .2,
          personId: const Value('p'),
        ),
      );
      await db.setzeErinnerungsfilter(Erinnerungsfilter(alben: ['familie']));
      expect(
        (await db.assetsOnThisDay(DateTime(2026, 11, 19))).map((a) => a.id),
        ['b'],
      );
      await db.setzeErinnerungsfilter(Erinnerungsfilter(personen: ['p']));
      expect(
        (await db.assetsOnThisDay(DateTime(2026, 11, 19))).map((a) => a.id),
        ['a'],
      );
      expect((await jahresinhalt(db, 2020)).personen, isEmpty);
    },
  );

  test(
    'Ungültige und unbekannte Filter öffnen keine gesperrten Rückblicke',
    () async {
      expect(
        () => Erinnerungsfilter(
          zeitraeume: [(von: '2020-02-30', bis: '2020-03-01')],
        ),
        throwsFormatException,
      );
      expect(
        () => Erinnerungsfilter(
          zeitraeume: [(von: '2021-01-01', bis: '2020-01-01')],
        ),
        throwsFormatException,
      );
      await foto('a', DateTime(2020, 11, 19));
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            const AppSettingsCompanion(
              id: Value(0),
              erinnerungsfilter: Value('{"fassung":2}'),
            ),
          );
      await expectLater(
        db.assetsOnThisDay(DateTime(2026, 11, 19)),
        throwsFormatException,
      );
    },
  );

  test(
    'Vorschlag ändert erst nach Annahme; Wiederholung überschreibt keine spätere Bearbeitung',
    () async {
      await album();
      final id = await vorschlag('ort', '  Testort  ');
      expect((await db.assetById('a'))!.locationCity, isNull);
      await dienst.entscheiden(
        id,
        annehmen: true,
        erwartet: await dienst.stand('a'),
      );
      expect((await db.assetById('a'))!.locationCity, 'Testort');
      await db.fuehreAus(const OrtSetzen(['a'], null, null, stadt: 'Später'));
      await dienst.entscheiden(id, annehmen: true, erwartet: 'alter Stand');
      expect((await db.assetById('a'))!.locationCity, 'Später');
      final row = (await db.select(db.beschriftungsvorschlaege).get()).single;
      expect(
        (row.von, row.vonName, row.wert, row.zustand),
        ('gast', 'Gast', 'Testort', 'angenommen'),
      );
      expect(row.entschieden, isNotNull);
      await expectLater(
        dienst.entscheiden(
          id,
          annehmen: false,
          erwartet: await dienst.stand('a'),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'Veraltete Entscheidung und entferntes Foto werden atomar abgewiesen',
    () async {
      await album();
      final id = await vorschlag('jahr', '1980');
      final stand = await dienst.stand('a');
      await db.fuehreAus(const OrtSetzen(['a'], 12, 13, stadt: 'Neue Angabe'));
      await expectLater(
        dienst.entscheiden(id, annehmen: true, erwartet: stand),
        throwsFormatException,
      );
      expect((await db.assetById('a'))!.fileCreatedAt.year, 2020);
      expect(
        (await db.select(db.beschriftungsvorschlaege).get()).single.zustand,
        'offen',
      );
      await db.fuehreAus(const AusAlbumNehmen('familie', ['a']));
      await expectLater(vorschlag('ort', 'Fremd'), throwsFormatException);
      await expectLater(
        dienst.entscheiden(
          id,
          annehmen: true,
          erwartet: await dienst.stand('a'),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'Gleichnamige Personen brauchen eine Auswahl; fremde Gesichter bleiben unberührt',
    () async {
      await album();
      await foto('b', DateTime(2021));
      for (final (id, asset) in [('f', 'a'), ('fremd', 'b')]) {
        await db.insertFace(
          FacesCompanion.insert(
            id: id,
            assetId: asset,
            boxX: 0,
            boxY: 0,
            boxW: .2,
            boxH: .2,
          ),
        );
      }
      await expectLater(
        vorschlag('person', 'Person', gesicht: 'fremd'),
        throwsFormatException,
      );
      for (final id in ['p1', 'p2']) {
        await db.fuehreAus(PersonAnlegen(id, 'Person'));
      }
      final id = await vorschlag('person', 'Person', gesicht: 'f');
      final stand = await dienst.stand('a');
      await expectLater(
        dienst.entscheiden(id, annehmen: true, erwartet: stand),
        throwsFormatException,
      );
      expect((await db.facesForAsset('a')).single.personId, isNull);
      await dienst.entscheiden(
        id,
        annehmen: true,
        erwartet: stand,
        personId: 'p2',
      );
      expect((await db.facesForAsset('a')).single.personId, 'p2');
      expect((await db.facesForAsset('b')).single.personId, isNull);
    },
  );

  test('Ungefähres Jahr und Ablehnung behalten die Herkunft', () async {
    await album();
    final id = await vorschlag('jahr', '1980');
    await dienst.entscheiden(
      id,
      annehmen: true,
      erwartet: await dienst.stand('a'),
    );
    final a = (await db.assetById('a'))!;
    expect(a.fileCreatedAt.year, 1980);
    expect(a.datumGeschaetzt, isTrue);
    final nein = await vorschlag('ort', 'Falscher Ort');
    await dienst.entscheiden(
      nein,
      annehmen: false,
      erwartet: await dienst.stand('a'),
    );
    expect((await db.assetById('a'))!.locationCity, isNull);
    expect(
      (await db.select(db.beschriftungsvorschlaege).get())
          .map((r) => r.zustand)
          .toSet(),
      {'angenommen', 'abgelehnt'},
    );
    await db.moveToTrash(['a']);
    await expectLater(vorschlag('ort', 'Verboten'), throwsFormatException);
  });

  test(
    'Migration 98 auf 99 erhält Aufnahmen und legt Filter und Vorschläge an',
    () async {
      final temp = await Directory.systemTemp.createTemp('pv_migration99_');
      addTearDown(() => temp.delete(recursive: true));
      final file = File('${temp.path}/library.sqlite');
      final initial = AppDatabase(NativeDatabase(file));
      await initial
          .into(initial.appSettings)
          .insert(const AppSettingsCompanion(id: Value(0)));
      await initial.close();
      final alt = sqlite.sqlite3.open(file.path);
      alt.execute('DROP TABLE beschriftungsvorschlaege');
      alt.execute('ALTER TABLE app_settings DROP COLUMN erinnerungsfilter');
      alt.execute('PRAGMA user_version = 98');
      alt.close();
      final neu = AppDatabase(NativeDatabase(file));
      addTearDown(neu.close);
      expect((await neu.erinnerungsfilter()).leer, isTrue);
      expect(await neu.select(neu.beschriftungsvorschlaege).get(), isEmpty);
      expect(neu.schemaVersion, 99);
    },
  );
}
