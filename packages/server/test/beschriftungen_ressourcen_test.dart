import 'dart:convert';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/beschriftungsvorschlaege.dart';
import 'package:photo_vault_server/src/beschriftung_api.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class _Zaehler extends QueryInterceptor {
  int lesen = 0;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    lesen++;
    return executor.runSelect(statement, args);
  }
}

void main() {
  late AppDatabase db;
  late _Zaehler zaehler;
  setUp(() async {
    zaehler = _Zaehler();
    db = AppDatabase(NativeDatabase.memory().interceptWith(zaehler));
    await db.fuehreAus(AlbumAnlegen('album', 'Probealbum', DateTime(2026)));
  });
  tearDown(() => db.close());

  Future<(Map, int)> frag([String query = '']) async {
    final r = await beschriftungsAnfrage(
      Request(
        'GET',
        Uri.parse('http://server/api/v1/alben/album/beschriftungen$query'),
      ),
      db,
      'album',
      konto: 'test',
      name: 'Testkonto',
      besitzer: true,
    );
    expect(r.statusCode, 200);
    final text = await r.readAsString();
    return (jsonDecode(text) as Map, utf8.encode(text).length);
  }

  Future<void> fotos(int anzahl, {bool person = false}) async {
    await db.batch((b) {
      for (var i = 0; i < anzahl; i++) {
        b.insert(
          db.assets,
          AssetsCompanion.insert(
            id: 'a$i',
            originalFileName: '$i.jpg',
            relativePath: '$i.jpg',
            checksum: 'a$i',
            type: 'IMAGE',
            fileCreatedAt: DateTime.utc(2020),
            importedAt: DateTime.utc(2026),
          ),
        );
        b.insert(
          db.albumAssets,
          AlbumAssetsCompanion.insert(albumId: 'album', assetId: 'a$i'),
        );
        b.insert(
          db.beschriftungsvorschlaege,
          BeschriftungsvorschlaegeCompanion.insert(
            id: 'v$i',
            assetId: 'a$i',
            albumId: 'album',
            von: 'test',
            vonName: 'Testgast',
            art: person ? 'person' : 'ort',
            wert: person ? 'Gleicher Name' : 'Testort',
            angelegt: DateTime.utc(2026),
            gesichtId: Value(person ? 'f$i' : null),
          ),
        );
        if (person) {
          b.insert(
            db.faces,
            FacesCompanion.insert(
              id: 'f$i',
              assetId: 'a$i',
              boxX: 0,
              boxY: 0,
              boxW: .2,
              boxH: .2,
            ),
          );
        }
      }
    });
  }

  test(
    '5000 unbeteiligte Personen vergrößern eine leere Seite nicht',
    () async {
      final vorher = await frag();
      await db.batch((b) {
        for (var i = 0; i < 5000; i++) {
          b.insert(
            db.people,
            PeopleCompanion.insert(id: 'p$i', name: 'Probe $i'),
          );
        }
      });
      final nachher = await frag();
      expect(nachher.$1, vorher.$1);
      expect(nachher.$2, vorher.$2);
      expect(nachher.$1['personen'], isEmpty);
      expect(nachher.$2, lessThan(512));
    },
  );

  test(
    '100 verschiedene Fotos werden in einer begrenzten Abfragezahl gelesen',
    () async {
      await fotos(100);
      zaehler.lesen = 0;
      final antwort = await frag();
      expect((antwort.$1['vorschlaege'] as List).length, 100);
      expect(zaehler.lesen, lessThanOrEqualTo(6));
      final v = (antwort.$1['vorschlaege'] as List).first as Map;
      expect(
        v['stand'],
        await Beschriftungsdienst(db).stand(v['aufnahme'] as String),
      );
    },
  );

  test(
    'Gleichnamige Kandidaten sind getrennt begrenzt und vollständig blätterbar',
    () async {
      await fotos(1, person: true);
      await db.batch((b) {
        for (var i = 0; i < 205; i++) {
          b.insert(
            db.people,
            PeopleCompanion.insert(
              id: 'p${i.toString().padLeft(3, '0')}',
              name: 'Gleicher Name',
            ),
          );
        }
      });
      final ids = <String>{};
      for (var seite = 0; seite < 3; seite++) {
        final (j, _) = await frag(
          '?personenname=Gleicher%20Name&personenseite=$seite',
        );
        final personen = (j['personen'] as List).cast<Map>();
        expect(personen.length, seite == 2 ? 5 : 100);
        expect(j['personenMehr'], seite < 2);
        ids.addAll(personen.map((p) => p['id'] as String));
      }
      expect(ids.length, 205);
      final (erste, _) = await frag();
      expect((erste['personen'] as List).length, 100);
      expect(erste['personenMehr'], isTrue);
      final dienst = Beschriftungsdienst(db);
      await expectLater(
        dienst.entscheiden(
          'v0',
          annehmen: true,
          erwartet: await dienst.stand('a0'),
        ),
        throwsFormatException,
      );
      await dienst.entscheiden(
        'v0',
        annehmen: true,
        erwartet: await dienst.stand('a0'),
        personId: 'p204',
      );
      expect((await db.facesForAsset('a0')).single.personId, 'p204');
    },
  );
}
