import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Die Schnittstelle der Weboberfläche, Stufe 2 (Issue #134): Alben,
/// Personen und Suche für einen Browser ohne eigene Kopie der Bibliothek –
/// und dass dabei kein Konto in die Bibliothek eines anderen sieht.
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
    ordner = await Directory.systemTemp.createTemp('pv_web_api_');
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
    maxToken = konten.meldeAn(max.id, 'Rechner', 'x').token;
  });

  tearDown(() async {
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  Future<Response> frag(
    String methode,
    String pfad, {
    String? token,
    Map<String, String> kopf = const {},
    Object? inhalt,
  }) async => api(
    Request(
      methode,
      Uri.parse('http://server$pfad'),
      headers: {if (token != null) 'authorization': 'Bearer $token', ...kopf},
      body: inhalt,
    ),
  );

  Future<Map<String, Object?>> jsonAus(Response r) async =>
      (jsonDecode(await r.readAsString()) as Map).cast<String, Object?>();

  Future<String> ladeHoch(String token, String name, int farbe) async {
    final bild = img.Image(width: 48, height: 32);
    img.fill(bild, color: img.ColorRgb8(farbe, 120, 255 - farbe));
    final bytes = Uint8List.fromList(img.encodeJpg(bild));
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
      frag(
        'POST',
        '/api/v1/befehle',
        token: token,
        kopf: {'content-type': 'application/json'},
        inhalt: jsonEncode({'art': art, 'werte': w}),
      );

  test(
    'Alben: Liste mit Anzahl und Titelbild, Inhalt, fremde unsichtbar',
    () async {
      final a = await ladeHoch(erikaToken, 'strand.jpg', 10);
      final b = await ladeHoch(erikaToken, 'berg.jpg', 90);
      await ladeHoch(erikaToken, 'see.jpg', 200);
      expect(
        (await befehl(erikaToken, 'albumAnlegen', {
          'albumId': 'urlaub',
          'name': 'Urlaub',
          'angelegtAm': '2026-10-17T10:00:00Z',
        })).statusCode,
        200,
      );
      expect(
        (await befehl(erikaToken, 'albumFuellen', {
          'albumId': 'urlaub',
          'ids': [a, b],
        })).statusCode,
        200,
      );

      final liste = await jsonAus(
        await frag('GET', '/api/v1/alben', token: erikaToken),
      );
      final album = (liste['alben']! as List).cast<Map>().single;
      expect(album['name'], 'Urlaub');
      expect(album['anzahl'], 2);
      expect(album['titelbild'], isIn([a, b]));

      final inhalt = await jsonAus(
        await frag('GET', '/api/v1/alben/urlaub', token: erikaToken),
      );
      expect((inhalt['album']! as Map)['name'], 'Urlaub');
      expect(
        (inhalt['aufnahmen']! as List).cast<Map>().map((z) => z['id']),
        unorderedEquals([a, b]),
      );

      // Max hat seine eigene Bibliothek: kein Album, und Erikas gibt es für
      // ihn nicht – auch nicht mit geratener Kennung.
      expect(
        (await jsonAus(
          await frag('GET', '/api/v1/alben', token: maxToken),
        ))['alben'],
        isEmpty,
      );
      expect(
        (await frag('GET', '/api/v1/alben/urlaub', token: maxToken)).statusCode,
        404,
      );
      expect((await frag('GET', '/api/v1/alben/urlaub')).statusCode, 401);
    },
  );

  test('Personen: Liste nach Anzahl, Inhalt, Unbekanntes 404', () async {
    final a = await ladeHoch(erikaToken, 'a.jpg', 10);
    final b = await ladeHoch(erikaToken, 'b.jpg', 60);
    final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
    for (final (id, name) in [('p1', 'Anna'), ('p2', 'Ben')]) {
      await db.createPerson(PeopleCompanion.insert(id: id, name: name));
    }
    var n = 0;
    for (final (asset, person) in [(a, 'p1'), (b, 'p1'), (a, 'p2')]) {
      await db.insertFace(
        FacesCompanion.insert(
          id: 'g${n++}',
          assetId: asset,
          personId: Value(person),
          boxX: 0.1,
          boxY: 0.1,
          boxW: 0.2,
          boxH: 0.2,
        ),
      );
    }
    final liste = await jsonAus(
      await frag('GET', '/api/v1/personen', token: erikaToken),
    );
    final personen = (liste['personen']! as List).cast<Map>();
    expect(personen.map((p) => p['name']), ['Anna', 'Ben']);
    expect(personen.first['anzahl'], 2);
    expect(personen.last['anzahl'], 1);

    final anna = await jsonAus(
      await frag('GET', '/api/v1/personen/p1', token: erikaToken),
    );
    expect(
      (anna['aufnahmen']! as List).cast<Map>().map((z) => z['id']),
      unorderedEquals([a, b]),
    );
    expect(
      (await frag('GET', '/api/v1/personen/p1', token: maxToken)).statusCode,
      404,
    );
    expect(
      (await frag(
        'GET',
        '/api/v1/personen/niemand',
        token: erikaToken,
      )).statusCode,
      404,
    );
  });

  test(
    'Reisen: Liste mit Zeitraum und Anzahl, Inhalt, fremde unsichtbar',
    () async {
      final a = await ladeHoch(erikaToken, 'r1.jpg', 10);
      final b = await ladeHoch(erikaToken, 'r2.jpg', 60);
      final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
      await db.reiseAnlegen(
        ReisenCompanion.insert(
          id: 'sommer',
          name: 'Sommer in Kiel',
          von: DateTime(2026, 7, 1),
          bis: DateTime(2026, 7, 10),
          angelegtAm: DateTime(2026, 7, 11),
        ),
        [a, b],
      );
      final liste = await jsonAus(
        await frag('GET', '/api/v1/reisen', token: erikaToken),
      );
      final reise = (liste['reisen']! as List).cast<Map>().single;
      expect(reise['name'], 'Sommer in Kiel');
      expect(reise['anzahl'], 2);
      expect(reise['titelbild'], isIn([a, b]));
      final inhalt = await jsonAus(
        await frag('GET', '/api/v1/reisen/sommer', token: erikaToken),
      );
      expect(
        (inhalt['aufnahmen']! as List).cast<Map>().map((x) => x['id']),
        unorderedEquals([a, b]),
      );
      expect(
        (await frag(
          'GET',
          '/api/v1/reisen/sommer',
          token: maxToken,
        )).statusCode,
        404,
      );
    },
  );

  test(
    'Statistik: Kennzahlen wie auf dem Rechner, je Konto getrennt',
    () async {
      final a = await ladeHoch(erikaToken, 's1.jpg', 10);
      await ladeHoch(erikaToken, 's2.jpg', 60);
      final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
      await (db.update(db.assets)..where((t) => t.id.equals(a))).write(
        const AssetsCompanion(isTrashed: Value(true)),
      );
      final s = await jsonAus(
        await frag('GET', '/api/v1/statistik', token: erikaToken),
      );
      expect(s['insgesamt'], 1);
      expect(s['fotos'], 1);
      expect(s['videos'], 0);
      expect(s['papierkorb'], 1);
      expect(s['bytes'], greaterThan(0));
      final proJahr = (s['proJahr']! as Map).cast<String, int>();
      expect(proJahr.values.fold(0, (x, y) => x + y), 1);
      expect(
        (s['proMonat']! as Map).cast<String, int>().values.fold(
          0,
          (x, y) => x + y,
        ),
        1,
      );
      expect(s['kameras'], isA<List>());
      final fremd = await jsonAus(
        await frag('GET', '/api/v1/statistik', token: maxToken),
      );
      expect(fremd['insgesamt'], 0);
    },
  );

  test(
    'Duplikate: Gruppen aus den Einbettungen, bestes Foto markiert',
    () async {
      final a = await ladeHoch(erikaToken, 'd1.jpg', 10);
      final b = await ladeHoch(erikaToken, 'd2.jpg', 60);
      final c = await ladeHoch(erikaToken, 'd3.jpg', 120);
      final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
      Float32List vektor(int achse) => Float32List(64)..[achse] = 1;
      await db.saveEmbedding(a, vektor(0));
      await db.saveEmbedding(b, vektor(0));
      await db.saveEmbedding(c, vektor(1));
      await (db.update(db.assets)..where((t) => t.id.equals(b))).write(
        const AssetsCompanion(isFavorite: Value(true)),
      );
      final d = await jsonAus(
        await frag('GET', '/api/v1/duplikate?schwelle=0.95', token: erikaToken),
      );
      expect(d['einbettungen'], 3);
      final gruppe = (d['gruppen']! as List).cast<Map>().single;
      expect(
        (gruppe['aufnahmen']! as List).cast<Map>().map((x) => x['id']),
        unorderedEquals([a, b]),
      );
      expect(gruppe['behalten'], b, reason: 'der Favorit bleibt');
      expect(gruppe['loeschbar'], [a]);
      expect(
        (await frag(
          'GET',
          '/api/v1/duplikate?schwelle=2',
          token: erikaToken,
        )).statusCode,
        400,
      );
      final fremd = await jsonAus(
        await frag('GET', '/api/v1/duplikate', token: maxToken),
      );
      expect(fremd['gruppen'], isEmpty);
    },
  );

  test('Orte: Punkte je Zoom, und die Zeilen zu einer Gruppe', () async {
    final a = await ladeHoch(erikaToken, 'tor.jpg', 10);
    final b = await ladeHoch(erikaToken, 'dom.jpg', 60);
    final c = await ladeHoch(erikaToken, 'hafen.jpg', 120);
    final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
    for (final (id, breite, laenge) in [
      (a, 52.5163, 13.3777),
      (b, 52.5191, 13.4010),
      (c, 53.5413, 9.9841),
    ]) {
      await (db.update(db.assets)..where((t) => t.id.equals(id))).write(
        AssetsCompanion(latitude: Value(breite), longitude: Value(laenge)),
      );
    }
    final grob = await jsonAus(
      await frag('GET', '/api/v1/orte?zoom=4', token: erikaToken),
    );
    final gruppen = (grob['gruppen']! as List).cast<Map>();
    expect(gruppen.map((g) => g['anzahl']), unorderedEquals([2, 1]));
    final fein = await jsonAus(
      await frag('GET', '/api/v1/orte?zoom=16', token: erikaToken),
    );
    expect((fein['gruppen']! as List).length, 3);

    final berlin = gruppen.firstWhere((g) => g['anzahl'] == 2);
    final zeilen = await jsonAus(
      await frag(
        'POST',
        '/api/v1/aufnahmen/liste',
        token: erikaToken,
        kopf: {'content-type': 'application/json'},
        inhalt: jsonEncode({'ids': berlin['ids']}),
      ),
    );
    expect(
      (zeilen['aufnahmen']! as List).cast<Map>().map((x) => x['id']),
      unorderedEquals([a, b]),
    );
    expect(
      (await frag('GET', '/api/v1/orte', token: maxToken)).statusCode,
      200,
    );
  });

  test(
    'Zustand nennt die Fassung; Papierkorb listet, was drin liegt',
    () async {
      final z = await jsonAus(await frag('GET', '/api/v1/zustand'));
      expect(z['fassung'], 'Entwicklung');
      final a = await ladeHoch(erikaToken, 'weg.jpg', 30);
      await ladeHoch(erikaToken, 'bleibt.jpg', 80);
      expect(
        (await befehl(erikaToken, 'inDenPapierkorb', {
          'ids': [a],
        })).statusCode,
        200,
      );
      final korb = await jsonAus(
        await frag('GET', '/api/v1/papierkorb', token: erikaToken),
      );
      expect((korb['aufnahmen']! as List).cast<Map>().map((x) => x['id']), [a]);
      final sichtbar = await jsonAus(
        await frag('GET', '/api/v1/aufnahmen', token: erikaToken),
      );
      expect((sichtbar['aufnahmen']! as List).length, 1);
      expect(
        (await befehl(erikaToken, 'ausDemPapierkorb', {
          'ids': [a],
        })).statusCode,
        200,
      );
      expect(
        (await jsonAus(
          await frag('GET', '/api/v1/papierkorb', token: erikaToken),
        ))['aufnahmen'],
        isEmpty,
      );
      expect(
        (await frag('GET', '/api/v1/papierkorb', token: maxToken)).statusCode,
        200,
      );
      final e = await jsonAus(
        await frag('GET', '/api/v1/erinnerungen', token: erikaToken),
      );
      expect(e['art'], isIn(['tag', 'monat', 'keiner']));
      expect(e['gruppen'], isA<List>());
    },
  );

  test(
    'Suche: nach Text findet den Namen; nach Inhalt ohne Modell 404',
    () async {
      final a = await ladeHoch(erikaToken, 'Sonnenuntergang_Lanzarote.jpg', 10);
      await ladeHoch(erikaToken, 'IMG_0002.jpg', 60);
      final text = await jsonAus(
        await frag(
          'GET',
          '/api/v1/suche?art=text&text=lanzarote',
          token: erikaToken,
        ),
      );
      expect((text['aufnahmen']! as List).cast<Map>().map((z) => z['id']), [a]);
      expect(
        ((await jsonAus(
              await frag(
                'GET',
                '/api/v1/suche?art=text&text=nirgends',
                token: erikaToken,
              ),
            ))['aufnahmen']!
            as List),
        isEmpty,
      );
      expect(
        (await frag(
          'GET',
          '/api/v1/suche?text=strand',
          token: erikaToken,
        )).statusCode,
        404,
      );
      expect(
        (await frag(
          'GET',
          '/api/v1/suche?art=text&text=',
          token: erikaToken,
        )).statusCode,
        400,
      );
      expect(
        (await frag(
          'GET',
          '/api/v1/suche?art=text&text=x',
          token: maxToken,
        )).statusCode,
        200,
      );
    },
  );
}
