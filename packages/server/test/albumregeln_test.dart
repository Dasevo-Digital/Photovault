import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:photo_vault_server/src/albumteilungen.dart' show Albumteilungen;
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Alben, die sich selbst füllen (#298), und die eingeschränkte
/// Partnerfreigabe in der Zeitleiste (#299). Erika hat Fotos von Anna,
/// Ben und beiden zusammen; Max ist ihr Partner.
void main() {
  late Directory ordner;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late Konto erika;
  late Konto max;
  late Handler api;
  late String erikaToken;
  late String maxToken;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_albumregeln_');
    sdb = Serverdatenbank.imSpeicher();
    konten = Kontodienst(
      sdb,
      Tresorschluessel(List.filled(32, 5)),
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: false,
    );
    bibliotheken = Bibliotheken(
      wurzel: Directory('${ordner.path}/bibliotheken'),
      eingang: Directory('${ordner.path}/eingang'),
      ruhe: const Duration(hours: 1),
    );
    api = baueApi(konten: konten, bibliotheken: bibliotheken);
    erika = await konten.legeAn('erika', 'ein langes passwort');
    max = await konten.legeAn('max', 'noch ein passwort');
    erikaToken = konten.meldeAn(erika.id, 'Rechner', 'x').token;
    maxToken = konten.meldeAn(max.id, 'Telefon', 'x').token;
  });

  tearDown(() async {
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  Future<Response> frag(
    String methode,
    String pfad, {
    required String token,
    Map<String, String> kopf = const {},
    Object? inhalt,
  }) async => api(
    Request(
      methode,
      Uri.parse('http://server$pfad'),
      headers: {'authorization': 'Bearer $token', ...kopf},
      body: inhalt,
    ),
  );

  Future<Map<String, Object?>> jsonAus(Response r) async =>
      (jsonDecode(await r.readAsString()) as Map).cast<String, Object?>();

  Future<Response> mitJson(
    String methode,
    String pfad,
    String token,
    Object inhalt,
  ) => frag(
    methode,
    pfad,
    token: token,
    kopf: {'content-type': 'application/json'},
    inhalt: jsonEncode(inhalt),
  );

  Uint8List jpeg(int farbe) {
    final bild = img.Image(width: 48, height: 32);
    img.fill(bild, color: img.ColorRgb8(farbe, 120, 255 - farbe));
    return Uint8List.fromList(img.encodeJpg(bild));
  }

  Future<String> ladeHoch(String token, String name, int farbe) async {
    final bytes = jpeg(farbe);
    final tus = {'tus-resumable': '1.0.0'};
    final angelegt = await frag(
      'POST',
      '/api/v1/hochladen',
      token: token,
      kopf: {
        ...tus,
        'upload-length': '${bytes.length}',
        'upload-metadata': 'filename ${base64.encode(utf8.encode(name))}',
      },
    );
    final fertig = await frag(
      'PATCH',
      angelegt.headers['location']!,
      token: token,
      kopf: {
        ...tus,
        'content-type': 'application/offset+octet-stream',
        'upload-offset': '0',
      },
      inhalt: bytes,
    );
    expect(fertig.headers['pv-ausgang'], 'imported', reason: name);
    return fertig.headers['pv-aufnahme']!;
  }

  Future<Response> befehl(String token, String art, Map<String, Object?> w) =>
      mitJson('POST', '/api/v1/befehle', token, {'art': art, 'werte': w});

  Future<AppDatabase> erikasDb() async =>
      (await bibliotheken.fuer(erika.id)).bibliothek.db;

  var gesichter = 0;
  Future<void> gesicht(String aufnahme, String person) async {
    final db = await erikasDb();
    await db
        .into(db.faces)
        .insert(
          FacesCompanion.insert(
            id: 'g${gesichter++}',
            assetId: aufnahme,
            personId: Value(person),
            boxX: 0.1,
            boxY: 0.1,
            boxW: 0.2,
            boxH: 0.2,
          ),
        );
  }

  Future<void> aufgenommen(String aufnahme, DateTime wann) async {
    final db = await erikasDb();
    await (db.update(db.assets)..where((t) => t.id.equals(aufnahme))).write(
      AssetsCompanion(fileCreatedAt: Value(wann)),
    );
  }

  /// Fotos von Anna (2019 und 2024), von Ben (2024), von beiden (2024)
  /// und eines ohne jemanden.
  Future<
    ({String anna19, String anna24, String ben, String beide, String leer})
  >
  fotos() async {
    final db = await erikasDb();
    for (final (id, name) in const [('anna', 'Anna'), ('ben', 'Ben')]) {
      await db
          .into(db.people)
          .insert(PeopleCompanion.insert(id: id, name: name));
    }
    final anna19 = await ladeHoch(erikaToken, 'anna19.jpg', 10);
    final anna24 = await ladeHoch(erikaToken, 'anna24.jpg', 40);
    final ben = await ladeHoch(erikaToken, 'ben.jpg', 80);
    final beide = await ladeHoch(erikaToken, 'beide.jpg', 120);
    final leer = await ladeHoch(erikaToken, 'leer.jpg', 160);
    await gesicht(anna19, 'anna');
    await gesicht(anna24, 'anna');
    await gesicht(ben, 'ben');
    await gesicht(beide, 'anna');
    await gesicht(beide, 'ben');
    await aufgenommen(anna19, DateTime(2019, 6, 1));
    await aufgenommen(anna24, DateTime(2024, 3, 1));
    await aufgenommen(ben, DateTime(2024, 4, 1));
    await aufgenommen(beide, DateTime(2024, 5, 1));
    await aufgenommen(leer, DateTime(2024, 6, 1));
    await befehl(erikaToken, 'albumAnlegen', {
      'albumId': 'kinder',
      'name': 'Kinder',
      'angelegtAm': '2026-11-05T10:00:00Z',
    });
    return (anna19: anna19, anna24: anna24, ben: ben, beide: beide, leer: leer);
  }

  Future<Set<String>> imAlbum() async {
    final a = await jsonAus(
      await frag('GET', '/api/v1/alben/kinder', token: erikaToken),
    );
    return {
      for (final z in a['aufnahmen']! as List) (z as Map)['id'] as String,
    };
  }

  group('Albumregeln (#298)', () {
    test('eine der Personen, ab einem Tag – sofort gefüllt', () async {
      final f = await fotos();
      final r = await mitJson('PUT', '/api/v1/alben/kinder/regel', erikaToken, {
        'personen': ['anna', 'ben'],
        'ab': '2020-01-01',
      });
      expect(r.statusCode, 200);
      final j = await jsonAus(r);
      expect(j['dazu'], 3);
      expect(await imAlbum(), {f.anna24, f.ben, f.beide});
      final regel = j['regel']! as Map;
      expect(regel['ab'], '2020-01-01');
      expect(regel['alle'], false);
      expect(
        [for (final p in regel['personen']! as List) (p as Map)['name']],
        ['Anna', 'Ben'],
      );

      // Die Albenliste zeigt, dass es sich selbst füllt.
      final alben = await jsonAus(
        await frag('GET', '/api/v1/alben', token: erikaToken),
      );
      expect((alben['alben']! as List).cast<Map>().single['automatisch'], true);
    });

    test('alle zusammen auf einem Foto', () async {
      final f = await fotos();
      await mitJson('PUT', '/api/v1/alben/kinder/regel', erikaToken, {
        'personen': ['anna', 'ben'],
        'alle': true,
      });
      expect(await imAlbum(), {f.beide});
    });

    test('was herausgenommen ist, kommt nicht wieder; Neues schon', () async {
      final f = await fotos();
      await mitJson('PUT', '/api/v1/alben/kinder/regel', erikaToken, {
        'personen': ['ben'],
      });
      expect(await imAlbum(), {f.ben, f.beide});
      await befehl(erikaToken, 'ausAlbumNehmen', {
        'albumId': 'kinder',
        'ids': [f.ben],
        'albumLoeschen': false,
      });

      // Ben wird auf einem weiteren Foto erkannt.
      await gesicht(f.leer, 'ben');
      final ablauf = Albumregelablauf(
        konten: konten,
        bibliotheken: bibliotheken,
      );
      await ablauf.pruefe();
      expect(await imAlbum(), {f.beide, f.leer});

      // Papierkorb und Gesperrtes nie.
      final db = await erikasDb();
      await gesicht(f.anna19, 'ben');
      await (db.update(db.assets)..where((t) => t.id.equals(f.anna19))).write(
        const AssetsCompanion(isLocked: Value(true)),
      );
      await ablauf.pruefe();
      expect(await imAlbum(), {f.beide, f.leer});

      // Ohne Regel bleibt, was darin liegt.
      expect(
        (await frag(
          'DELETE',
          '/api/v1/alben/kinder/regel',
          token: erikaToken,
        )).statusCode,
        204,
      );
      expect(
        (await jsonAus(
          await frag('GET', '/api/v1/alben/kinder/regel', token: erikaToken),
        ))['regel'],
        isNull,
      );
      expect(await imAlbum(), {f.beide, f.leer});
    });

    test(
      'fehlt bei „alle zusammen“ eine Person, kommt nichts mehr dazu',
      () async {
        final f = await fotos();
        await mitJson('PUT', '/api/v1/alben/kinder/regel', erikaToken, {
          'personen': ['anna', 'ben'],
          'alle': true,
        });
        expect(await imAlbum(), {f.beide});
        final db = await erikasDb();
        await (db.delete(db.people)..where((t) => t.id.equals('ben'))).go();
        await gesicht(f.leer, 'anna');
        await Albumregelablauf(
          konten: konten,
          bibliotheken: bibliotheken,
        ).pruefe();
        expect(await imAlbum(), {f.beide});
        final regel =
            (await jsonAus(
                  await frag(
                    'GET',
                    '/api/v1/alben/kinder/regel',
                    token: erikaToken,
                  ),
                ))['regel']!
                as Map;
        expect(regel['fehlend'], 1);
      },
    );

    test('falsche Angaben und fremde Alben', () async {
      await fotos();
      Future<int> setze(Object inhalt, {String album = 'kinder'}) async =>
          (await mitJson(
            'PUT',
            '/api/v1/alben/$album/regel',
            erikaToken,
            inhalt,
          )).statusCode;
      expect(await setze({'personen': <String>[]}), 400);
      expect(
        await setze({
          'personen': ['anna'],
          'ab': '2024-02-30',
        }),
        400,
      );
      expect(
        await setze({
          'personen': ['niemand'],
        }),
        404,
      );
      expect(
        await setze({
          'personen': ['anna'],
        }, album: 'gibtsnicht'),
        404,
      );
      // Max hat kein Album „kinder“.
      expect(
        (await mitJson('PUT', '/api/v1/alben/kinder/regel', maxToken, {
          'personen': ['anna'],
        })).statusCode,
        404,
      );
    });
  });

  group('Partnerfreigabe (#299)', () {
    Future<Response> partner(String methode, String pfad, String token) =>
        frag(methode, '/api/v1/partner$pfad', token: token);

    Future<List<String>> partnerIds() async {
      final d = await jsonAus(
        await partner('GET', '/von/${erika.id}/aufnahmen', maxToken),
      );
      return [
        for (final z in d['aufnahmen']! as List) (z as Map)['id'] as String,
      ];
    }

    test('nur ab einem Tag und nur mit Anna – auch jede Datei', () async {
      final f = await fotos();
      expect(
        (await mitJson('PUT', '/api/v1/partner/${max.id}', erikaToken, {
          'ab': '2020-01-01',
          'personen': ['anna'],
        })).statusCode,
        204,
      );
      expect((await partnerIds()).toSet(), {f.anna24, f.beide});

      final mitMir =
          ((await jsonAus(await partner('GET', '', maxToken)))['mitMir']!
                  as List)
              .cast<Map>()
              .single;
      expect(mitMir['anzahl'], 2);
      expect(mitMir['eingeschraenkt'], true);
      expect(mitMir['inZeitleiste'], false);
      final meine =
          ((await jsonAus(await partner('GET', '', erikaToken)))['meine']!
                  as List)
              .cast<Map>()
              .single;
      expect(meine['ab'], '2020-01-01');
      expect(
        [for (final p in meine['personen']! as List) (p as Map)['id']],
        ['anna'],
      );

      Future<int> datei(String id) async => (await partner(
        'GET',
        '/von/${erika.id}/aufnahmen/$id/miniatur',
        maxToken,
      )).statusCode;
      expect(await datei(f.anna24), 200);
      expect(await datei(f.ben), 404, reason: 'ohne Anna');
      expect(await datei(f.anna19), 404, reason: 'vor dem Tag');

      // Ohne Körper bleibt die Einschränkung; mit leerem hebt er sie auf.
      await partner('PUT', '/${max.id}', erikaToken);
      expect((await partnerIds()).toSet(), {f.anna24, f.beide});
      await mitJson('PUT', '/api/v1/partner/${max.id}', erikaToken, {});
      expect((await partnerIds()), hasLength(5));
    });

    test('fehlt die einzige Person, gilt die Einschränkung weiter', () async {
      await fotos();
      await mitJson('PUT', '/api/v1/partner/${max.id}', erikaToken, {
        'personen': ['ben'],
      });
      final db = await erikasDb();
      await (db.delete(db.people)..where((t) => t.id.equals('ben'))).go();
      final meine =
          ((await jsonAus(await partner('GET', '', erikaToken)))['meine']!
                  as List)
              .cast<Map>()
              .single;
      expect(meine['personen'], isEmpty);
      expect(meine['fehlend'], 1, reason: 'sonst sähe es nach „alles“ aus');
    });

    test('in der eigenen Zeitleiste – eingereiht, mit Namen', () async {
      final f = await fotos();
      final eigen = await ladeHoch(maxToken, 'max.jpg', 200);
      final mdb = (await bibliotheken.fuer(max.id)).bibliothek.db;
      await (mdb.update(mdb.assets)..where((t) => t.id.equals(eigen))).write(
        AssetsCompanion(fileCreatedAt: Value(DateTime(2024, 4, 15))),
      );
      await mitJson('PUT', '/api/v1/partner/${max.id}', erikaToken, {
        'ab': '2024-01-01',
      });
      Future<List<Map>> zeitleiste({String extra = ''}) async {
        final alle = <Map>[];
        String? weiter;
        do {
          final d = await jsonAus(
            await frag(
              'GET',
              '/api/v1/aufnahmen?anzahl=2$extra'
                  '${weiter == null ? '' : '&nach=${Uri.encodeQueryComponent(weiter)}'}',
              token: maxToken,
            ),
          );
          alle.addAll((d['aufnahmen']! as List).cast<Map>());
          weiter = d['weiter'] as String?;
        } while (weiter != null);
        return alle;
      }

      expect([for (final z in await zeitleiste()) z['id']], [eigen]);
      expect(
        (await mitJson(
          'PUT',
          '/api/v1/partner/von/${erika.id}/zeitleiste',
          maxToken,
          {'an': true},
        )).statusCode,
        204,
      );
      final z = await zeitleiste();
      expect(
        [for (final x in z) x['id']],
        [f.leer, f.beide, eigen, f.ben, f.anna24],
      );
      final vonErika = z.firstWhere((x) => x['id'] == f.beide);
      expect(vonErika['konto'], erika.id);
      expect(vonErika['von'], 'erika');
      expect(z.firstWhere((x) => x['id'] == eigen).containsKey('konto'), false);

      // Bei „älteste zuerst“ fehlen sie in der Liste, also auch im Regler.
      final ohne = await jsonAus(
        await frag(
          'GET',
          '/api/v1/zeitleiste/monate?sortierung=aufnahmeAlt',
          token: maxToken,
        ),
      );
      expect(
        [for (final m in ohne['monate']! as List) (m as Map)['monat']],
        ['2024-04'],
      );

      // Der Ziehregler zählt mit.
      final monate = await jsonAus(
        await frag('GET', '/api/v1/zeitleiste/monate', token: maxToken),
      );
      expect(
        {
          for (final m in (monate['monate']! as List).cast<Map>())
            m['monat']: m['anzahl'],
        },
        {'2024-06': 1, '2024-05': 1, '2024-04': 2, '2024-03': 1},
      );

      // Favoriten bleiben eigen.
      expect(await zeitleiste(extra: '&favoriten=1'), isEmpty);

      // Wer nicht Partner ist, kann nichts einschalten.
      expect(
        (await mitJson(
          'PUT',
          '/api/v1/partner/von/${max.id}/zeitleiste',
          erikaToken,
          {'an': true},
        )).statusCode,
        404,
      );
    });
  });

  test('Schema 9 → 10: alte Partnerfreigaben bleiben, ganz und ohne '
      'Zeitleiste', () async {
    final datei = File('${ordner.path}/alt.sqlite');
    final roh = sqlite3.open(datei.path);
    roh.execute('''
      CREATE TABLE konten (id TEXT PRIMARY KEY, name TEXT, passwort TEXT,
        totp TEXT, totp_letzter_schritt INTEGER NOT NULL DEFAULT 0,
        verwalter INTEGER NOT NULL DEFAULT 0,
        fehlversuche INTEGER NOT NULL DEFAULT 0, gesperrt_bis INTEGER,
        angelegt INTEGER NOT NULL);
      CREATE TABLE partnerfreigaben (
        besitzer TEXT NOT NULL REFERENCES konten(id) ON DELETE CASCADE,
        partner TEXT NOT NULL REFERENCES konten(id) ON DELETE CASCADE,
        angelegt INTEGER NOT NULL,
        PRIMARY KEY (besitzer, partner));
      INSERT INTO konten (id, name, angelegt) VALUES ('a', 'a', 1), ('b', 'b', 1);
      INSERT INTO partnerfreigaben VALUES ('a', 'b', 1);
      PRAGMA user_version = 9;
    ''');
    roh.close();
    final bank = Serverdatenbank.oeffne(datei);
    try {
      final f = Albumteilungen(bank).partnerfreigabe('a', 'b')!;
      expect(f.eingeschraenkt, false);
      expect(f.inZeitleiste, false);
      expect(
        bank.db.select('PRAGMA user_version').single.columnAt(0),
        Serverdatenbank.schema,
      );
      expect(Albumregeln(bank).alle(), isEmpty);
    } finally {
      bank.schliesse();
    }
  });
}
