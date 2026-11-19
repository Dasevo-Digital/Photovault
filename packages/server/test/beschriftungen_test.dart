import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Echte API-Anfragen mit getrennten synthetischen Konten: Vorschläge
/// brauchen eine aktuelle Freigabe, Entscheidungen die Besitzerrolle.
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
  late String moritzToken;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_beschriftungen_');
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
    final moritz = await konten.legeAn('moritz', 'ein drittes passwort');
    erikaToken = konten.meldeAn(erika.id, 'Rechner', 'x').token;
    maxToken = konten.meldeAn(max.id, 'Telefon', 'x').token;
    moritzToken = konten.meldeAn(moritz.id, 'Telefon', 'x').token;
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

  Uint8List jpeg(int farbe) {
    final bild = img.Image(width: 48, height: 32);
    img.fill(bild, color: img.ColorRgb8(farbe, 120, 255 - farbe));
    return Uint8List.fromList(img.encodeJpg(bild));
  }

  Future<String> ladeHoch(
    String token,
    String name,
    int farbe, {
    Map<String, Object?>? beilage,
  }) async {
    final bytes = jpeg(farbe);
    final tus = {'tus-resumable': '1.0.0'};
    final angelegt = await frag(
      'POST',
      '/api/v1/hochladen',
      token: token,
      kopf: {
        ...tus,
        'upload-length': '${bytes.length}',
        'upload-metadata':
            'filename ${base64.encode(utf8.encode(name))}'
            '${beilage == null ? '' : ',xmp ${base64.encode(utf8.encode(jsonEncode(beilage)))}'}',
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
      frag(
        'POST',
        '/api/v1/befehle',
        token: token,
        kopf: {'content-type': 'application/json'},
        inhalt: jsonEncode({'art': art, 'werte': w}),
      );

  test(
    'Albumgrenze wird vor dem Upload geprüft und zulässige Zuordnungen bleiben vollständig',
    () async {
      final alben = List.generate(100, (i) => 'Album $i');
      final foto = await ladeHoch(
        erikaToken,
        'alben.jpg',
        10,
        beilage: {'alben': alben},
      );
      final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
      expect((await db.select(db.albums).get()).length, 100);
      final zuordnungen = await (db.select(
        db.albumAssets,
      )..where((t) => t.assetId.equals(foto))).get();
      expect(zuordnungen.length, 100);
      final antwort = await frag(
        'POST',
        '/api/v1/hochladen',
        token: erikaToken,
        kopf: {
          'tus-resumable': '1.0.0',
          'upload-length': '3',
          'upload-metadata':
              'filename ${base64.encode(utf8.encode('zu-viele.jpg'))},xmp ${base64.encode(utf8.encode(jsonEncode({
                'alben': [...alben, 'Album 100'],
              })))}',
        },
      );
      expect(antwort.statusCode, 400);
      expect(await antwort.readAsString(), 'pv_umzug_angaben_zu_gross');
      expect((await db.select(db.assets).get()).length, 1);
      expect((await db.select(db.albums).get()).length, 100);
    },
  );

  Future<Response> teile(String konto, {bool beitragen = false}) => frag(
    'PUT',
    '/api/v1/alben/urlaub/teilungen/$konto',
    token: erikaToken,
    kopf: {'content-type': 'application/json'},
    inhalt: jsonEncode({'beitragen': beitragen}),
  );

  Future<List<Map>> mitMir(String token) async =>
      ((await jsonAus(
                await frag('GET', '/api/v1/geteilt', token: token),
              ))['alben']!
              as List)
          .cast<Map>();

  /// Erikas Album „Urlaub“ mit zwei Fotos; ein drittes liegt daneben.
  Future<(String, String, String)> urlaub() async {
    final strand = await ladeHoch(erikaToken, 'strand.jpg', 10);
    final berg = await ladeHoch(erikaToken, 'berg.jpg', 90);
    final privat = await ladeHoch(erikaToken, 'privat.jpg', 200);
    await befehl(erikaToken, 'albumAnlegen', {
      'albumId': 'urlaub',
      'name': 'Urlaub',
      'angelegtAm': '2026-10-17T10:00:00Z',
    });
    await befehl(erikaToken, 'albumFuellen', {
      'albumId': 'urlaub',
      'ids': [strand, berg],
    });
    await befehl(erikaToken, 'favoritSetzen', {
      'ids': [strand],
      'favorit': true,
    });
    return (strand, berg, privat);
  }

  Future<String> geteiltFuerMax() async {
    expect((await teile(max.id)).statusCode, 200);
    return (await mitMir(maxToken)).single['id']! as String;
  }

  Future<Response> vorschlag(
    String pfad,
    String token,
    String id, {
    String art = 'ort',
    String wert = 'Testort',
  }) => frag(
    'POST',
    '$pfad/beschriftungen',
    token: token,
    inhalt: jsonEncode({
      'aufnahme': id,
      'art': art,
      'wert': wert,
      'von': 'gefaelscht',
    }),
  );
  Future<Map<String, Object?>> liste(String pfad, String token) async =>
      jsonAus(await frag('GET', '$pfad/beschriftungen', token: token));

  test(
    'Umzugsangaben gelangen über den echten Upload bis zu Datum und Album',
    () async {
      final id = await ladeHoch(
        erikaToken,
        'umzug.jpg',
        43,
        beilage: {
          'sterne': 4,
          'beschreibung': 'Übernommener Text',
          'aufgenommenAm': '2000-01-01T10:03:00Z',
          'favorit': true,
          'alben': ['Übernommenes Album'],
        },
      );
      final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
      final a = (await db.assetById(id))!;
      expect(
        (a.rating, a.description, a.isFavorite, a.datumGeschaetzt),
        (4, 'Übernommener Text', true, false),
      );
      expect(a.fileCreatedAt.toUtc(), DateTime.utc(2000, 1, 1, 10, 3));
      final album = (await db.select(db.albums).get()).single;
      expect(album.name, 'Übernommenes Album');
      expect((await db.albumAufnahmen(album.id)).single.id, id);
    },
  );

  test(
    'Große Vorschlagsverläufe bleiben begrenzt und vollständig seitenweise lesbar',
    () async {
      final (foto, _, _) = await urlaub();
      final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
      await db.batch((b) {
        for (var i = 0; i < 1000; i++) {
          b.insert(
            db.beschriftungsvorschlaege,
            BeschriftungsvorschlaegeCompanion.insert(
              id: 'v${i.toString().padLeft(4, '0')}',
              assetId: foto,
              albumId: 'urlaub',
              von: max.id,
              vonName: 'Testgast',
              art: 'ort',
              wert: 'Testort',
              angelegt: DateTime.utc(2026, 1, 1, 0, 0, i),
            ),
          );
        }
      });
      const route = '/api/v1/alben/urlaub/beschriftungen';
      final seite1 = await jsonAus(await frag('GET', route, token: erikaToken));
      final seite2 = await jsonAus(
        await frag('GET', '$route?seite=1', token: erikaToken),
      );
      expect(seite1['mehr'], true);
      expect(seite1['vorschlaege'], hasLength(100));
      expect(seite2['vorschlaege'], hasLength(100));
      final ids = (seite1['vorschlaege'] as List)
          .map((v) => (v as Map)['id'])
          .toSet();
      expect(
        (seite2['vorschlaege'] as List).any(
          (v) => ids.contains((v as Map)['id']),
        ),
        false,
      );
      expect(
        (await frag('GET', '$route?seite=-1', token: erikaToken)).statusCode,
        400,
      );
      expect(
        (await vorschlag('/api/v1/alben/urlaub', erikaToken, foto)).statusCode,
        400,
      );
    },
  );

  test(
    'Empfänger schlagen vor, nur der Besitzer entscheidet mit unverfälschter Herkunft',
    () async {
      final (foto, _, privat) = await urlaub();
      final share = await geteiltFuerMax();
      const eigen = '/api/v1/alben/urlaub';
      final fremd = '/api/v1/geteilt/$share';
      final r = await vorschlag(fremd, maxToken, foto);
      expect(r.statusCode, 201);
      expect((await vorschlag(fremd, maxToken, privat)).statusCode, 404);
      expect(
        (await frag(
          'GET',
          '$fremd/beschriftungen',
          token: moritzToken,
        )).statusCode,
        404,
      );
      final d = await liste(eigen, erikaToken);
      final v = (d['vorschlaege'] as List).single as Map;
      expect(v['von'], 'max');
      expect(v['zustand'], 'offen');
      expect(v['aktuell'], '');
      final id = v['id'];
      final entscheidung = jsonEncode({'annehmen': true, 'stand': v['stand']});
      expect(
        (await frag(
          'POST',
          '$eigen/beschriftungen/$id',
          token: maxToken,
          inhalt: entscheidung,
        )).statusCode,
        404,
      );
      expect(
        (await frag(
          'POST',
          '$fremd/beschriftungen/$id',
          token: maxToken,
          inhalt: entscheidung,
        )).statusCode,
        404,
      );
      expect(
        (await frag(
          'POST',
          '$eigen/beschriftungen/$id',
          token: erikaToken,
          inhalt: entscheidung,
        )).statusCode,
        200,
      );
      final danach =
          ((await liste(eigen, erikaToken))['vorschlaege'] as List).single
              as Map;
      expect(danach['zustand'], 'angenommen');
      expect(danach['aktuell'], 'Testort');
      expect(danach['entschieden'], isA<String>());
      expect(
        (await frag(
          'POST',
          '$eigen/beschriftungen/$id',
          token: erikaToken,
          inhalt: entscheidung,
        )).statusCode,
        200,
      );
      await vorschlag(eigen, erikaToken, foto, wert: 'Nur Besitzer');
      expect((await liste(fremd, maxToken))['vorschlaege'], hasLength(1));
      expect((await liste(eigen, erikaToken))['vorschlaege'], hasLength(2));
    },
  );

  test(
    'Entzogene Freigaben und entfernte, gesperrte oder gelöschte Fotos sind unzugänglich',
    () async {
      final (foto, berg, _) = await urlaub();
      final share = await geteiltFuerMax();
      const eigen = '/api/v1/alben/urlaub';
      final fremd = '/api/v1/geteilt/$share';
      await vorschlag(fremd, maxToken, foto);
      expect(
        (await befehl(erikaToken, 'ausAlbumNehmen', {
          'albumId': 'urlaub',
          'ids': [foto],
          'albumLoeschen': false,
        })).statusCode,
        200,
      );
      expect((await liste(fremd, maxToken))['vorschlaege'], isEmpty);
      expect((await vorschlag(fremd, maxToken, foto)).statusCode, 404);
      await vorschlag(fremd, maxToken, berg);
      final bereich = await bibliotheken.fuer(erika.id);
      await bereich.bibliothek.db.setAssetsLocked([berg], true);
      expect((await liste(fremd, maxToken))['vorschlaege'], isEmpty);
      expect((await vorschlag(fremd, maxToken, berg)).statusCode, 404);
      await bereich.bibliothek.db.setAssetsLocked([berg], false);
      await befehl(erikaToken, 'inDenPapierkorb', {
        'ids': [berg],
      });
      expect((await liste(fremd, maxToken))['vorschlaege'], isEmpty);
      expect(
        (await frag(
          'DELETE',
          '$eigen/teilungen/${max.id}',
          token: erikaToken,
        )).statusCode,
        204,
      );
      expect(
        (await frag(
          'GET',
          '$fremd/beschriftungen',
          token: maxToken,
        )).statusCode,
        404,
      );
      expect((await vorschlag(fremd, maxToken, berg)).statusCode, 404);
    },
  );

  test(
    'Veraltete Entscheidungen, falsche Formate und übergroße Anfragen ändern keine Metadaten',
    () async {
      final (foto, _, _) = await urlaub();
      const eigen = '/api/v1/alben/urlaub';
      await vorschlag(eigen, erikaToken, foto, art: 'jahr', wert: '1985');
      final v =
          ((await liste(eigen, erikaToken))['vorschlaege'] as List).single
              as Map;
      await befehl(erikaToken, 'ortSetzen', {
        'ids': [foto],
        'breite': null,
        'laenge': null,
        'stadt': 'Danach',
      });
      expect(
        (await frag(
          'POST',
          "$eigen/beschriftungen/${v['id']}",
          token: erikaToken,
          inhalt: jsonEncode({'annehmen': true, 'stand': v['stand']}),
        )).statusCode,
        409,
      );
      expect((await liste(eigen, erikaToken))['vorschlaege'], hasLength(1));
      expect(
        (await vorschlag(
          eigen,
          erikaToken,
          foto,
          art: 'jahr',
          wert: '10000',
        )).statusCode,
        400,
      );
      expect(
        (await frag(
          'POST',
          '$eigen/beschriftungen',
          token: erikaToken,
          inhalt: '[]',
        )).statusCode,
        400,
      );
      expect(
        (await frag(
          'POST',
          '$eigen/beschriftungen',
          token: erikaToken,
          inhalt: ' ' * 8193,
        )).statusCode,
        413,
      );
      final e = await jsonAus(
        await frag('GET', '/api/v1/einstellungen', token: erikaToken),
      );
      expect((e['erinnerungsfilter'] as Map)['fassung'], 2);
      expect(
        (await befehl(erikaToken, 'erinnerungsfilterSetzen', {
          'filter': {
            'fassung': 1,
            'personen': [],
            'alben': ['urlaub'],
            'zeitraeume': [],
          },
        })).statusCode,
        200,
      );
      final neu = await jsonAus(
        await frag('GET', '/api/v1/einstellungen', token: erikaToken),
      );
      expect((neu['erinnerungsfilter'] as Map)['alben'], ['urlaub']);
    },
  );
}
