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
    'Aktivitäten: in der Reiseliste, in ihrer Reise, Route und Strecke',
    () async {
      final a = await ladeHoch(erikaToken, 'w1.jpg', 10);
      final b = await ladeHoch(erikaToken, 'w2.jpg', 60);
      final c = await ladeHoch(erikaToken, 'w3.jpg', 120);
      final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
      // Zwei Aufnahmen mit Ort, rund 11 km auseinander, eine ohne.
      for (final (id, breite, laenge, stunde) in [
        (a, 47.0, 11.0, 9),
        (b, 47.1, 11.0, 12),
      ]) {
        await (db.update(db.assets)..where((t) => t.id.equals(id))).write(
          AssetsCompanion(
            latitude: Value(breite),
            longitude: Value(laenge),
            locationCity: const Value('Innsbruck'),
            locationState: const Value('Tirol'),
            locationCountry: const Value('Austria'),
            fileCreatedAt: Value(DateTime(2026, 7, 3, stunde)),
          ),
        );
      }
      await db.reiseAnlegen(
        ReisenCompanion.insert(
          id: 'alpen',
          name: 'Alpen',
          von: DateTime(2026, 7, 1),
          bis: DateTime(2026, 7, 9),
          angelegtAm: DateTime(2026, 7, 10),
        ),
        [a, b, c],
      );
      await db.aktivitaetAnlegen(
        AktivitaetenCompanion.insert(
          id: 'tour',
          name: 'Zur Hütte',
          art: 'wanderung',
          von: DateTime(2026, 7, 3, 9),
          bis: DateTime(2026, 7, 3, 12),
          reiseId: const Value('alpen'),
          angelegtAm: DateTime(2026, 7, 10),
        ),
        [a, b],
      );
      await db.aktivitaetAnlegen(
        AktivitaetenCompanion.insert(
          id: 'runde',
          name: 'Abendrunde',
          art: 'Gassi',
          von: DateTime(2026, 8, 1, 18),
          bis: DateTime(2026, 8, 1, 19),
          angelegtAm: DateTime(2026, 8, 2),
        ),
        [c],
      );
      final liste = await jsonAus(
        await frag('GET', '/api/v1/reisen?sprache=de', token: erikaToken),
      );
      final reise = (liste['reisen']! as List).cast<Map>().single;
      expect(reise['ort'], {
        'text': 'Innsbruck, Tirol, Österreich',
        'weitere': 0,
      });
      final aktivitaeten = (liste['aktivitaeten']! as List).cast<Map>();
      expect(aktivitaeten.map((x) => x['id']), ['runde', 'tour']);
      final tour = aktivitaeten.last;
      expect(tour['reisename'], 'Alpen');
      expect(tour['anzahl'], 2);
      expect(tour['art'], 'wanderung');
      expect(tour['titelbild'], a);
      expect(aktivitaeten.first['art'], 'Gassi');
      expect(aktivitaeten.first['ort'], isNull);
      final englisch = await jsonAus(
        await frag('GET', '/api/v1/reisen?sprache=en', token: erikaToken),
      );
      expect(((englisch['reisen']! as List).single as Map)['ort'], {
        'text': 'Innsbruck, Tirol, Austria',
        'weitere': 0,
      });

      final inReise = await jsonAus(
        await frag('GET', '/api/v1/reisen/alpen', token: erikaToken),
      );
      expect(
        (inReise['aktivitaeten']! as List).cast<Map>().map((x) => x['id']),
        ['tour'],
      );
      expect((inReise['reise']! as Map)['anzahl'], 3);

      final d = await jsonAus(
        await frag('GET', '/api/v1/aktivitaeten/tour', token: erikaToken),
      );
      final k = d['aktivitaet']! as Map;
      expect(k['reise'], {'id': 'alpen', 'name': 'Alpen'});
      expect(k['anzahl'], 2);
      expect(k['streckeKm'] as double, closeTo(11.1, 0.2));
      expect((d['route']! as List).cast<Map>().map((x) => x['id']), [a, b]);
      expect((d['aufnahmen']! as List).cast<Map>().map((x) => x['id']), [a, b]);
      expect(
        (await frag(
          'GET',
          '/api/v1/aktivitaeten/tour',
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

  test('Angaben: Datei, Kamera, Ort, Schlagwort, Album; Serie', () async {
    final a = await ladeHoch(erikaToken, 'a1.jpg', 10);
    final b = await ladeHoch(erikaToken, 'a2.jpg', 60);
    final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
    await (db.update(db.assets)..where((t) => t.id.equals(a))).write(
      const AssetsCompanion(
        cameraMake: Value('Canon'),
        cameraModel: Value('EOS R5'),
        fNumber: Value(2.8),
        iso: Value(400),
        exposureTimeSeconds: Value(0.004),
        latitude: Value(54.32),
        longitude: Value(10.13),
        locationCity: Value('Kiel'),
        locationCountry: Value('DE'),
        description: Value('Am Hafen'),
      ),
    );
    await befehl(erikaToken, 'schlagwortAnheften', {
      'ids': [a],
      'name': 'Hafen',
      'quelle': 'hand',
    });
    await befehl(erikaToken, 'albumAnlegen', {
      'albumId': 'alb1',
      'name': 'Küste',
      'angelegtAm': DateTime(2026, 7, 1).toIso8601String(),
    });
    await befehl(erikaToken, 'albumFuellen', {
      'albumId': 'alb1',
      'ids': [a],
    });
    await befehl(erikaToken, 'serieBilden', {
      'serieId': 'st1',
      'ids': [a, b],
      'titelId': a,
    });
    final d = await jsonAus(
      await frag('GET', '/api/v1/aufnahmen/$a/angaben', token: erikaToken),
    );
    expect(d['name'], 'a1.jpg');
    expect(d['bytes'], greaterThan(0));
    expect((d['kamera']! as Map)['modell'], 'EOS R5');
    expect((d['kamera']! as Map)['iso'], 400);
    expect((d['ort']! as Map)['stadt'], 'Kiel');
    expect((d['ort']! as Map)['land'], 'DE');
    expect(d['beschreibung'], 'Am Hafen');
    expect((d['schlagwoerter']! as List).cast<Map>().map((x) => x['name']), [
      'Hafen',
    ]);
    expect((d['alben']! as List).cast<Map>().map((x) => x['name']), ['Küste']);
    expect(d['personen'], isEmpty);
    expect((d['serie']! as Map)['groesse'], 2);
    final serie = await jsonAus(
      await frag('GET', '/api/v1/serien/st1', token: erikaToken),
    );
    expect((serie['aufnahmen']! as List).cast<Map>().map((x) => x['id']), [
      a,
      b,
    ], reason: 'Titelbild zuerst');
    for (final pfad in ['/api/v1/aufnahmen/$a/angaben', '/api/v1/serien/st1']) {
      expect((await frag('GET', pfad, token: maxToken)).statusCode, 404);
    }
  });

  test(
    'Stammbaum: Haushalte je Band und Elternhäuser, Fokus wählbar',
    () async {
      for (final (id, name) in [
        ('oma', 'Oma'),
        ('opa', 'Opa'),
        ('kind', 'Kind'),
      ]) {
        await befehl(erikaToken, 'personAnlegen', {
          'personId': id,
          'name': name,
        });
      }
      await befehl(erikaToken, 'beziehungHinzufuegen', {
        'personId': 'kind',
        'andereId': 'oma',
        'verwandtschaft': 'elternteil',
      });
      await befehl(erikaToken, 'beziehungHinzufuegen', {
        'personId': 'kind',
        'andereId': 'opa',
        'verwandtschaft': 'elternteil',
      });
      await befehl(erikaToken, 'beziehungHinzufuegen', {
        'personId': 'oma',
        'andereId': 'opa',
        'verwandtschaft': 'partner',
      });
      await befehl(erikaToken, 'lebensdatenSetzen', {
        'personId': 'oma',
        'geburt': DateTime(1950, 3, 1).toIso8601String(),
        'tod': null,
      });
      final d = await jsonAus(
        await frag('GET', '/api/v1/stammbaum?fokus=kind', token: erikaToken),
      );
      expect(d['fokus'], 'kind');
      final haushalte = (d['haushalte']! as List).cast<Map>();
      final eltern = haushalte.singleWhere((h) => h['band'] == -1);
      expect((eltern['personen'] as List), unorderedEquals(['oma', 'opa']));
      final kind = haushalte.singleWhere((h) => h['band'] == 0);
      expect(kind['personen'], ['kind']);
      expect((d['elternhaeuser']! as Map)['kind'], [eltern['id']]);
      final oma = (d['personen']! as List).cast<Map>().singleWhere(
        (p) => p['id'] == 'oma',
      );
      expect(oma['geburt'], startsWith('1950-03-01'));
      expect(oma['verwandt'], true);
      // Ohne fokus: die erste Person mit Verwandtschaft.
      final ohne = await jsonAus(
        await frag('GET', '/api/v1/stammbaum', token: erikaToken),
      );
      expect(ohne['fokus'], isNotNull);
      final fremd = await jsonAus(
        await frag('GET', '/api/v1/stammbaum', token: maxToken),
      );
      expect(fremd['fokus'], isNull);
    },
  );

  test('Einstellungen: Vorgaben lesen, über Befehle ändern', () async {
    Future<Map<String, Object?>> lies() async =>
        jsonAus(await frag('GET', '/api/v1/einstellungen', token: erikaToken));
    final vorher = await lies();
    expect(vorher['papierkorbLeeren'], false);
    expect(vorher['vorschlaegeAb'], isNull);
    for (final (art, werte) in [
      ('papierkorbFristSetzen', {'an': true, 'tage': 14}),
      ('vorschlaegeAutomatischSetzen', {'ab': 0.93}),
      ('auswertenNachImportSetzen', {'an': false}),
      ('sucheUebersetzenSetzen', {'an': true}),
      ('angabenSchuetzenSetzen', {'an': false}),
      ('gesichtsschwelleSetzen', {'schwelle': 0.5}),
    ]) {
      expect(
        (await befehl(erikaToken, art, werte)).statusCode,
        200,
        reason: art,
      );
    }
    final nachher = await lies();
    expect(nachher['papierkorbLeeren'], true);
    expect(nachher['papierkorbTage'], 14);
    expect(nachher['vorschlaegeAb'], closeTo(0.93, 1e-9));
    expect(nachher['auswertenNachImport'], false);
    expect(nachher['sucheUebersetzen'], true);
    expect(nachher['angabenSchuetzen'], false);
    expect(nachher['gesichtsschwelle'], closeTo(0.5, 1e-9));
    final fremd = await jsonAus(
      await frag('GET', '/api/v1/einstellungen', token: maxToken),
    );
    expect(fremd['papierkorbLeeren'], false);
  });

  test(
    'Entwickeln: Regler lesen, Kurve als Textur, Speichern über den Befehl',
    () async {
      final a = await ladeHoch(erikaToken, 'e1.jpg', 10);
      var d = await jsonAus(
        await frag('GET', '/api/v1/entwickeln/$a', token: erikaToken),
      );
      expect(d['quelle'], 'original');
      expect(d['einstellungen'], isNull);
      expect(d.containsKey('kurve'), isFalse);

      // Eine Kurve vom Rechner kommt als fertige 256×1-Textur an.
      final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
      await db
          .into(db.developSettings)
          .insert(
            DevelopSettingsCompanion.insert(
              assetId: a,
              exposure: const Value(0.5),
              toneCurveJson: const Value(
                '{"zusammen":[{"x":0,"y":0},{"x":0.5,"y":0.7},{"x":1,"y":1}]}',
              ),
              updatedAt: DateTime(2026, 10, 17),
            ),
          );
      d = await jsonAus(
        await frag('GET', '/api/v1/entwickeln/$a', token: erikaToken),
      );
      expect((d['einstellungen']! as Map)['exposure'], 0.5);
      expect(base64Decode(d['kurve']! as String).length, 256 * 4);
      expect(d.containsKey('wuerfel'), isFalse);

      // So speichert der Browser: erst die Datei, dann der Befehl.
      final jpeg = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 8, height: 8)),
      );
      final pfad = 'developed/$a-1.jpg';
      expect(
        (await frag(
          'PUT',
          '/api/v1/dateien/$pfad',
          token: erikaToken,
          kopf: {'content-length': '${jpeg.length}'},
          inhalt: Stream.value(jpeg),
        )).statusCode,
        204,
      );
      expect(
        (await befehl(erikaToken, 'entwicklungSpeichern', {
          'id': a,
          'pfad': pfad,
          'einstellungen': {
            'asset_id': a,
            'exposure': 1.25,
            'temperature': null,
            'tint': null,
            'contrast': 0.2,
            'shadows': 0.0,
            'highlights': 0.0,
            'sharpness': 0.0,
            'noise_reduction': 0.0,
            'clarity': 0.0,
            'vignette': 0.0,
            'lut_path': null,
            'lut_strength': 1.0,
            'lens_correction_enabled': true,
            'tone_curve_json': null,
            'color_mixer_json': null,
            'updated_at': DateTime(2026, 10, 17, 12).toIso8601String(),
          },
        })).statusCode,
        200,
      );
      final nachher = (await db.assetById(a))!;
      expect(nachher.developedRelativePath, pfad);
      expect((await db.developSettingsForAsset(a))!.exposure, 1.25);
      // Der Betrachter zeigt die entwickelte Fassung, das Entwickeln
      // rechnet weiter aus dem Original.
      Future<int> laenge(String art) async => (await (await frag(
        'GET',
        '/api/v1/aufnahmen/$a/$art',
        token: erikaToken,
      )).read().expand((x) => x).toList()).length;
      expect(await laenge('ansicht'), jpeg.length);
      expect(await laenge('original'), isNot(jpeg.length));
      expect(
        (await frag(
          'GET',
          '/api/v1/entwickeln/$a',
          token: maxToken,
        )).statusCode,
        404,
      );
    },
  );

  test(
    'Lebensbaum: Anordnung aus dem Kern, Grad je Person, Optionen',
    () async {
      for (final (id, name) in [
        ('oma', 'Gerda Kiel'),
        ('opa', 'Heinz Kiel'),
        ('kind', 'Anna Kiel'),
      ]) {
        await befehl(erikaToken, 'personAnlegen', {
          'personId': id,
          'name': name,
        });
      }
      for (final (a, b, v) in [
        ('kind', 'oma', 'elternteil'),
        ('kind', 'opa', 'elternteil'),
        ('oma', 'opa', 'partner'),
      ]) {
        await befehl(erikaToken, 'beziehungHinzufuegen', {
          'personId': a,
          'andereId': b,
          'verwandtschaft': v,
        });
      }
      final d = await jsonAus(
        await frag(
          'GET',
          '/api/v1/lebensbaum?fokus=kind&richtung=vorfahren&stil=gold',
          token: erikaToken,
        ),
      );
      expect(d['fokus'], 'kind');
      expect((d['optionen']! as Map)['stil'], 'gold');
      expect(d['nachname'], 'Kiel');
      expect(d['hintergrund'], endsWith('.jpg'));
      final plaetze = (d['plaetze']! as List).cast<Map>();
      final imBild = {for (final p in plaetze) ...(p['personen'] as List)};
      expect(imBild, containsAll(['kind', 'oma', 'opa']));
      expect(plaetze.where((p) => p['amStamm'] == true), hasLength(1));
      final personen = (d['personen']! as Map).cast<String, Map>();
      expect((personen['oma']!['grad'] as Map)['art'], 'vorfahre');
      expect((personen['oma']!['grad'] as Map)['aufwaerts'], 1);
      // Die Person am Stamm trägt keine Bezeichnung: Um sie geht es.
      expect(personen['kind']!.containsKey('grad'), isFalse);
      expect(((d['vorlage']! as Map)['groesse'] as List), hasLength(2));

      final familie = await jsonAus(
        await frag(
          'GET',
          '/api/v1/lebensbaum?fokus=kind&richtung=familie',
          token: erikaToken,
        ),
      );
      expect((familie['optionen']! as Map)['richtung'], 'familie');
      expect(familie['plaetze'], isNotEmpty);
      final fremd = await jsonAus(
        await frag('GET', '/api/v1/lebensbaum', token: maxToken),
      );
      expect(fremd['fokus'], isNull);
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

  test('Favoriten: nur, was so markiert ist, seitenweise', () async {
    final a = await ladeHoch(erikaToken, 'lieblings.jpg', 20);
    await ladeHoch(erikaToken, 'sonst.jpg', 70);
    final b = await ladeHoch(erikaToken, 'auch.jpg', 120);
    expect(
      (await befehl(erikaToken, 'favoritSetzen', {
        'ids': [a, b],
        'favorit': true,
      })).statusCode,
      200,
    );
    final alle = await jsonAus(
      await frag('GET', '/api/v1/aufnahmen?favoriten=1', token: erikaToken),
    );
    expect(
      (alle['aufnahmen']! as List).cast<Map>().map((x) => x['id']).toSet(),
      {a, b},
    );
    expect(alle['weiter'], isNull);
    final erste = await jsonAus(
      await frag(
        'GET',
        '/api/v1/aufnahmen?favoriten=1&anzahl=1',
        token: erikaToken,
      ),
    );
    expect((erste['aufnahmen']! as List).length, 1);
    final zweite = await jsonAus(
      await frag(
        'GET',
        '/api/v1/aufnahmen?favoriten=1&anzahl=1&nach=${erste['weiter']}',
        token: erikaToken,
      ),
    );
    final ids = [
      for (final d in [erste, zweite])
        ...(d['aufnahmen']! as List).cast<Map>().map((x) => x['id']),
    ];
    expect(ids.toSet(), {a, b});
    final ohne = await jsonAus(
      await frag('GET', '/api/v1/aufnahmen', token: erikaToken),
    );
    expect((ohne['aufnahmen']! as List).length, 3);
  });

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
