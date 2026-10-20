import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
  // Overpass für die Wanderobjekte – gezählt, damit der Test sieht, dass
  // ein Ausschnitt nur einmal gefragt wird.
  var overpassFragen = 0;

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
    overpassFragen = 0;
    api = baueApi(
      konten: konten,
      bibliotheken: bibliotheken,
      netz: MockClient((r) async {
        overpassFragen++;
        return http.Response(
          jsonEncode({
            'elements': [
              {
                'id': 7,
                'lat': 51.80,
                'lon': 10.61,
                'tags': {'natural': 'peak', 'name': 'Ilsestein', 'ele': '473'},
              },
              {
                'id': 8,
                'lat': 51.81,
                'lon': 10.62,
                'tags': {'amenity': 'bench'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
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

  test('Videos als H.264: erst 202, dann die abspielbare Fassung', () async {
    // Ein kurzes Video, wie es ein Browser nicht abspielt (HEVC, wo
    // ffmpeg es kann, sonst MPEG-4 Part 2 – auch das spielt kein Browser).
    final quelle = File('${ordner.path}/clip.mov');
    Future<ProcessResult> baue(String codec) => Process.run('ffmpeg', [
      '-nostdin', '-y', '-loglevel', 'error', //
      '-f', 'lavfi', '-i', 'testsrc=size=320x240:rate=10:duration=1',
      '-c:v', codec, '-pix_fmt', 'yuv420p', quelle.path,
    ]);
    if ((await baue('libx265')).exitCode != 0) await baue('mpeg4');
    final bytes = await quelle.readAsBytes();
    final tus = {'tus-resumable': '1.0.0'};
    final angelegt = await frag(
      'POST',
      '/api/v1/hochladen',
      token: erikaToken,
      kopf: {
        ...tus,
        'upload-length': '${bytes.length}',
        'upload-metadata': 'filename ${base64.encode(utf8.encode('clip.mov'))}',
      },
    );
    final fertig = await frag(
      'PATCH',
      angelegt.headers['location']!,
      token: erikaToken,
      kopf: {
        ...tus,
        'content-type': 'application/offset+octet-stream',
        'upload-offset': '0',
      },
      inhalt: bytes,
    );
    expect(fertig.headers['pv-ausgang'], 'imported');
    final id = fertig.headers['pv-aufnahme']!;
    final pfad = '/api/v1/aufnahmen/$id/abspielbar';

    final erst = await frag('GET', pfad, token: erikaToken);
    expect(erst.statusCode, 202);
    expect((await jsonAus(erst))['bereit'], false);
    // Ein anderes Konto sieht die Aufnahme nicht.
    expect((await frag('GET', pfad, token: maxToken)).statusCode, 404);

    Response? da;
    for (var i = 0; i < 300 && da == null; i++) {
      final r = await frag('GET', pfad, token: erikaToken);
      if (r.statusCode == 200) {
        da = r;
      } else {
        expect(r.statusCode, 202);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    expect(da, isNotNull, reason: 'nach 30 s keine Fassung');
    expect(
      await jsonAus(await frag('GET', '$pfad?pruefen=1', token: erikaToken)),
      {'bereit': true},
    );
    expect(da!.headers['content-type'], 'video/mp4');
    final mp4 = await da.read().expand((b) => b).toList();
    final text = latin1.decode(mp4, allowInvalid: true);
    expect(text.substring(4, 8), 'ftyp');
    expect(text, contains('avc1'));
    // Ein Bild hat keine Videofassung.
    final bild = await ladeHoch(erikaToken, 'bild.jpg', 30);
    expect(
      (await frag(
        'GET',
        '/api/v1/aufnahmen/$bild/abspielbar',
        token: erikaToken,
      )).statusCode,
      404,
    );
  }, skip: _hatFfmpeg() ? false : 'ohne ffmpeg');

  test(
    'Gesichter: Gruppen ohne Namen mit Vorschlag, benennen, Angaben',
    () async {
      final a = await ladeHoch(erikaToken, 'feier.jpg', 40);
      final b = await ladeHoch(erikaToken, 'garten.jpg', 140);
      final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
      // Normierte Einbettungen in zwei Richtungen: Wer nah an (0, 1) liegt,
      // ähnelt einander.
      Uint8List vektor(double x) {
        final v = Float32List(128);
        final laenge = math.sqrt(x * x + 1);
        v[0] = x / laenge;
        v[1] = 1 / laenge;
        return Uint8List.view(v.buffer);
      }

      await befehl(erikaToken, 'personAnlegen', {
        'personId': 'anna',
        'name': 'Anna',
      });
      Future<void> gesicht(
        String id,
        String aufnahme,
        String? person,
        double x,
        double links,
      ) => db
          .into(db.faces)
          .insert(
            FacesCompanion.insert(
              id: id,
              assetId: aufnahme,
              personId: Value(person),
              boxX: links,
              boxY: 0.1,
              boxW: 0.2,
              boxH: 0.2,
              cropRelativePath: Value('faces/$id.jpg'),
              embedding: Value(vektor(x)),
            ),
          );
      // Anna kennt man schon; zwei weitere Gesichter sehen ihr ähnlich, ein
      // drittes niemandem.
      await gesicht('f-anna', b, 'anna', 0.05, 0.1);
      await gesicht('f1', a, null, 0.0, 0.6);
      await gesicht('f2', b, null, 0.02, 0.5);
      await gesicht('f3', a, null, -40, 0.2);

      final o = await jsonAus(
        await frag('GET', '/api/v1/gesichter/ohne-namen', token: erikaToken),
      );
      final gruppen = (o['gruppen']! as List).cast<Map>();
      expect(gruppen, hasLength(1));
      expect([
        for (final g in (gruppen.single['gesichter'] as List).cast<Map>())
          g['id'],
      ], unorderedEquals(['f1', 'f2']));
      expect((gruppen.single['vorschlag'] as Map)['name'], 'Anna');
      // Für „Im Foto zeigen“ (#189): das Foto und wo das Gesicht darin sitzt.
      final f1 = (gruppen.single['gesichter'] as List).cast<Map>().firstWhere(
        (g) => g['id'] == 'f1',
      );
      expect(f1['aufnahme'], a);
      expect(f1['kasten'], [0.6, 0.1, 0.2, 0.2]);
      expect(o['einzeln'], 1);
      expect(o['gesamt'], 3);
      expect(o['schwelle'], isA<double>());
      // Ein anderes Konto sieht nichts davon.
      final fremd = await jsonAus(
        await frag('GET', '/api/v1/gesichter/ohne-namen', token: maxToken),
      );
      expect(fremd['gruppen'], isEmpty);

      // Die Angaben zeigen jedes Gesicht, von links nach rechts.
      final vorher = await jsonAus(
        await frag('GET', '/api/v1/aufnahmen/$a/angaben', token: erikaToken),
      );
      final g = (vorher['gesichter']! as List).cast<Map>();
      expect([for (final x in g) x['id']], ['f3', 'f1']);
      expect(g.first['person'], isNull);
      expect(g.first['ausschnitt'], 'faces/f3.jpg');
      expect(g.first['kasten'], [0.2, 0.1, 0.2, 0.2]);

      // Benennen geht über die Befehle – danach ist die Gruppe weg.
      expect(
        (await befehl(erikaToken, 'gesichterZuordnen', {
          'gesichtIds': ['f1', 'f2'],
          'personId': 'anna',
        })).statusCode,
        200,
      );
      final nachher = await jsonAus(
        await frag('GET', '/api/v1/gesichter/ohne-namen', token: erikaToken),
      );
      expect(nachher['gruppen'], isEmpty);
      final angaben = await jsonAus(
        await frag('GET', '/api/v1/aufnahmen/$a/angaben', token: erikaToken),
      );
      expect(
        ((angaben['gesichter']! as List).cast<Map>().last['person']
            as Map)['name'],
        'Anna',
      );
    },
  );

  test(
    'Weitere Fotos einer Person: Vorschläge, Ablehnung hebt die Schwelle',
    () async {
      final a = await ladeHoch(erikaToken, 'feier.jpg', 40);
      final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
      // Ein Gesicht mit genau dieser Ähnlichkeit zu Anna (0, 1, 0, …) –
      // der Rest in einer eigenen Richtung je Gesicht, damit sich die
      // Kandidaten untereinander kaum ähneln.
      var richtung = 2;
      Uint8List vektor(double aehnlichkeit) {
        final v = Float32List(128);
        v[1] = aehnlichkeit;
        v[richtung++] = math.sqrt(1 - aehnlichkeit * aehnlichkeit);
        return Uint8List.view(v.buffer);
      }

      await befehl(erikaToken, 'personAnlegen', {
        'personId': 'anna',
        'name': 'Anna',
      });
      Future<void> gesicht(String id, String? person, double s) => db
          .into(db.faces)
          .insert(
            FacesCompanion.insert(
              id: id,
              assetId: a,
              personId: Value(person),
              boxX: 0.1,
              boxY: 0.1,
              boxW: 0.2,
              boxH: 0.2,
              cropRelativePath: Value('faces/$id.jpg'),
              embedding: Value(vektor(s)),
            ),
          );
      await gesicht('f-anna', 'anna', 1);
      for (final (id, s) in [
        ('g1', 0.9),
        ('g2', 0.8),
        ('g3', 0.6),
        ('g4', 0.45),
        ('g5', 0.2),
      ]) {
        await gesicht(id, null, s);
      }
      Future<Map<String, Object?>> vorschlaege() async => jsonAus(
        await frag(
          'GET',
          '/api/v1/personen/anna/vorschlaege',
          token: erikaToken,
        ),
      );
      final v = await vorschlaege();
      final allgemein = v['allgemein']! as double;
      expect(v['schwelle'], allgemein);
      final liste = (v['vorschlaege']! as List).cast<Map>();
      expect([for (final x in liste) x['id']], ['g1', 'g2', 'g3', 'g4']);
      expect(liste.first['ausschnitt'], 'faces/g1.jpg');
      expect(liste.first['aufnahme'], a);
      expect(liste.first['kasten'], hasLength(4));
      expect(
        (await frag(
          'GET',
          '/api/v1/personen/anna/vorschlaege',
          token: maxToken,
        )).statusCode,
        404,
      );

      // Wie im Browser: drei angenommen, eines abgelehnt.
      for (final (art, werte) in [
        (
          'gesichterZuordnen',
          {
            'gesichtIds': ['g1', 'g2', 'g3'],
            'personId': 'anna',
          },
        ),
        (
          'vorschlaegeVerwerfen',
          {
            'gesichtIds': ['g4'],
          },
        ),
        (
          'gesichtsEntscheidungenMerken',
          {
            'personId': 'anna',
            'entscheidungen': [
              for (final x in liste)
                {
                  'faceId': x['id'],
                  'accepted': x['id'] != 'g4',
                  'similarity': x['aehnlichkeit'],
                },
            ],
            'allgemeineSchwelle': allgemein,
          },
        ),
      ]) {
        expect((await befehl(erikaToken, art, werte)).statusCode, 200);
      }
      // Die Schwelle liegt jetzt zwischen der schwächsten Bestätigung und
      // der stärksten Ablehnung – g4 kommt nicht wieder.
      final nachher = await vorschlaege();
      expect(nachher['schwelle'] as double, greaterThan(0.45));
      expect(nachher['vorschlaege'], isEmpty);
      final anna = await (db.select(
        db.people,
      )..where((t) => t.id.equals('anna'))).getSingle();
      expect(anna.similarityThreshold, nachher['schwelle']);
    },
  );

  test('Orte: Länder mit Städten, Anzahl und Titelbild', () async {
    final a = await ladeHoch(erikaToken, 'rom1.jpg', 10);
    final b = await ladeHoch(erikaToken, 'rom2.jpg', 40);
    final c = await ladeHoch(erikaToken, 'mailand.jpg', 80);
    final d = await ladeHoch(erikaToken, 'wien.jpg', 120);
    await ladeHoch(erikaToken, 'ohne.jpg', 160);
    final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
    Future<void> ort(String id, String land, String stadt) =>
        (db.update(db.assets)..where((t) => t.id.equals(id))).write(
          AssetsCompanion(
            locationCountry: Value(land),
            locationCity: Value(stadt),
          ),
        );
    await ort(a, 'Italy', 'Rome');
    await ort(b, 'Italy', 'Rome');
    await ort(c, 'Italy', 'Milan');
    await ort(d, 'Austria', 'Vienna');
    // Ein Favorit wird Titelbild, auch wenn er nicht der jüngste ist.
    await befehl(erikaToken, 'favoritSetzen', {
      'ids': [a],
      'favorit': true,
    });
    final o = await jsonAus(
      await frag('GET', '/api/v1/laender?sprache=de', token: erikaToken),
    );
    final laender = (o['laender']! as List).cast<Map>();
    expect([for (final l in laender) l['land']], ['Italy', 'Austria']);
    final italien = laender.first;
    expect(italien['name'], 'Italien');
    expect(italien['anzahl'], 3);
    expect(italien['titelbild'], a);
    final staedte = (italien['staedte'] as List).cast<Map>();
    expect([for (final s in staedte) s['stadt']], ['Rome', 'Milan']);
    expect(staedte.first['anzahl'], 2);
    final rom = await jsonAus(
      await frag(
        'GET',
        '/api/v1/laender/aufnahmen?land=Italy&stadt=Rome',
        token: erikaToken,
      ),
    );
    expect(
      {for (final x in (rom['aufnahmen']! as List).cast<Map>()) x['id']},
      {a, b},
    );
    final ganz = await jsonAus(
      await frag(
        'GET',
        '/api/v1/laender/aufnahmen?land=Italy',
        token: erikaToken,
      ),
    );
    expect((ganz['aufnahmen']! as List).length, 3);
    // Ein anderes Konto hat keine Orte.
    final fremd = await jsonAus(
      await frag('GET', '/api/v1/laender', token: maxToken),
    );
    expect(fremd['laender'], isEmpty);
  });

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

  test('Wanderobjekte: einmal von Overpass, danach aus der Bibliothek; '
      'nur ein vernünftiger Ausschnitt', () async {
    const kasten = 'sued=51.7&west=10.5&nord=51.9&ost=10.7';
    for (var i = 0; i < 2; i++) {
      final r = await frag(
        'GET',
        '/api/v1/wanderobjekte?$kasten',
        token: erikaToken,
      );
      expect(r.statusCode, 200);
      expect((await jsonAus(r))['punkte'], [
        {
          'osmId': 7,
          'art': 'gipfel',
          'breite': 51.8,
          'laenge': 10.61,
          'name': 'Ilsestein',
          'hoehe': 473.0,
        },
      ]);
    }
    expect(overpassFragen, 1);
    for (final falsch in [
      'sued=51&west=10&nord=54&ost=11',
      'sued=51.9&west=10.5&nord=51.7&ost=10.7',
      'sued=x&west=10.5&nord=51.9&ost=10.7',
    ]) {
      final r = await frag(
        'GET',
        '/api/v1/wanderobjekte?$falsch',
        token: erikaToken,
      );
      expect(r.statusCode, 400, reason: falsch);
    }
    final ohne = await frag('GET', '/api/v1/wanderobjekte?$kasten');
    expect(ohne.statusCode, 401);
  });

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
      expect(d['spuren'], isEmpty);
      expect(
        (await frag(
          'GET',
          '/api/v1/aktivitaeten/tour',
          token: maxToken,
        )).statusCode,
        404,
      );

      // Eine Spur kommt als Befehl – wie vom Rechner – und ersetzt die
      // Strecke zwischen den Fotos.
      final spur = SpurAnlegen(
        id: 'gpx1',
        name: 'Ilsetal.gpx',
        quelle: '/srv/ablage/wandern/Ilsetal.gpx',
        aktivitaetId: 'tour',
        laengeKm: 3.1,
        aufstieg: 240,
        abstieg: 238,
        angelegtAm: DateTime.utc(2026, 8, 30, 14),
        punkte: [
          (
            breite: 51.83,
            laenge: 10.68,
            hoehe: 250.0,
            zeit: DateTime.utc(2026, 8, 30, 8),
          ),
          (
            breite: 51.82,
            laenge: 10.66,
            hoehe: 410.0,
            zeit: DateTime.utc(2026, 8, 30, 9),
          ),
          (breite: 51.81, laenge: 10.65, hoehe: null, zeit: null),
        ],
      );
      for (var i = 0; i < 2; i++) {
        // Zweimal: Nachgereicht wird auch, was schon da ist.
        expect(
          (await befehl(erikaToken, spur.art, spur.werte)).statusCode,
          200,
        );
      }
      final mit = await jsonAus(
        await frag('GET', '/api/v1/aktivitaeten/tour', token: erikaToken),
      );
      expect((mit['aktivitaet']! as Map)['streckeKm'], 3.1);
      final spuren = (mit['spuren']! as List).cast<Map>();
      expect(spuren, hasLength(1));
      expect(spuren.single['name'], 'Ilsetal.gpx');
      expect(spuren.single['punkte'], [
        [
          51.83,
          10.68,
          250.0,
          DateTime.utc(2026, 8, 30, 8).millisecondsSinceEpoch,
        ],
        [
          51.82,
          10.66,
          410.0,
          DateTime.utc(2026, 8, 30, 9).millisecondsSinceEpoch,
        ],
        [51.81, 10.65, null, null],
      ]);
      final gespeichert = (await db.alleSpuren()).single;
      // Nur der Dateiname, nicht der Pfad des Rechners.
      expect(gespeichert.quelle, 'Ilsetal.gpx');
      expect(gespeichert.punktzahl, 3);
      expect(
        await jsonAus(await frag('GET', '/api/v1/spuren', token: erikaToken)),
        {
          'kennungen': ['gpx1'],
        },
      );
      expect(
        await jsonAus(await frag('GET', '/api/v1/spuren', token: maxToken)),
        {'kennungen': <String>[]},
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

  test('Statistik: Jahre und Monate nach der Ortszeit des Servers', () async {
    // Dieselbe Zone, in der `aufgenommen` ohne Versatz hinausgeht und im
    // Browser die Tage der Zeitleiste bildet. In UTC gezählt, fiel in
    // Mitteleuropa Neujahr 00:30 ins Vorjahr.
    final silvester = await ladeHoch(erikaToken, 'sv.jpg', 10);
    final neujahr = await ladeHoch(erikaToken, 'nj.jpg', 60);
    final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
    for (final (id, wann) in [
      (silvester, DateTime(2025, 12, 31, 23, 30)),
      (neujahr, DateTime(2026, 1, 1, 0, 30)),
    ]) {
      await (db.update(db.assets)..where((t) => t.id.equals(id))).write(
        AssetsCompanion(fileCreatedAt: Value(wann)),
      );
    }
    final s = await jsonAus(
      await frag('GET', '/api/v1/statistik', token: erikaToken),
    );
    expect(s['proJahr'], {'2025': 1, '2026': 1});
    expect(s['proMonat'], {'12': 1, '1': 1});
  });

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

  test(
    'Stammbaum: jedes Kind steht unter seinem Elternhaus, nicht der Reihe nach',
    () async {
      // Zwei Geschwister mit Partnern, darunter ihre Kinder. Das Geflecht
      // führt das Kind der Schwester vor denen des Bruders – der Reihe
      // nach gesetzt stand es unter dem Bruder und sah aus wie sein Sohn.
      for (final id in [
        'oma',
        'bruder',
        'partnerin',
        'schwester',
        'schwager',
        'kind1',
        'kind2',
        'neffe',
      ]) {
        await befehl(erikaToken, 'personAnlegen', {'personId': id, 'name': id});
      }
      Future<void> eltern(String kind, String elternteil) =>
          befehl(erikaToken, 'beziehungHinzufuegen', {
            'personId': kind,
            'andereId': elternteil,
            'verwandtschaft': 'elternteil',
          });
      Future<void> paar(String a, String b) => befehl(
        erikaToken,
        'beziehungHinzufuegen',
        {'personId': a, 'andereId': b, 'verwandtschaft': 'partner'},
      );
      await eltern('bruder', 'oma');
      await eltern('schwester', 'oma');
      await paar('bruder', 'partnerin');
      await paar('schwester', 'schwager');
      await eltern('neffe', 'schwester');
      await eltern('neffe', 'schwager');
      for (final k in ['kind1', 'kind2']) {
        await eltern(k, 'bruder');
        await eltern(k, 'partnerin');
      }
      // Der Neffe ist der Älteste – nach Alter geordnet kommt er zuerst.
      for (final (id, jahr) in [
        ('neffe', 2018),
        ('kind1', 2022),
        ('kind2', 2024),
      ]) {
        await befehl(erikaToken, 'lebensdatenSetzen', {
          'personId': id,
          'geburt': DateTime(jahr, 5, 1).toIso8601String(),
          'tod': null,
        });
      }
      final d = await jsonAus(
        await frag('GET', '/api/v1/stammbaum?fokus=oma', token: erikaToken),
      );
      // So stand es vorher im Geflecht – der Reihe nach gesetzt also
      // links, unter dem Bruder.
      final kinder = [
        for (final h in (d['haushalte']! as List).cast<Map>())
          if (h['band'] == 2) ...(h['personen'] as List),
      ];
      expect(kinder.first, 'neffe');
      final plan = d['plan']! as Map;
      final mitte = {
        for (final s in (plan['schilder']! as List).cast<Map>())
          s['id'] as String: (s['x'] as num) + 59,
      };
      double haus(String a, String b) => (mitte[a]! + mitte[b]!) / 2;
      final bruderHaus = haus('bruder', 'partnerin');
      final schwesterHaus = haus('schwester', 'schwager');
      double naeher(String kind, double zu, double weg) =>
          (mitte[kind]! - weg).abs() - (mitte[kind]! - zu).abs();
      expect(naeher('neffe', schwesterHaus, bruderHaus), greaterThan(0));
      for (final k in ['kind1', 'kind2']) {
        expect(naeher(k, bruderHaus, schwesterHaus), greaterThan(0));
      }
      // Die Äste enden an den Häusern, aus denen die Kinder stammen.
      final aeste = (plan['aeste']! as List).cast<Map>();
      final astNeffe = aeste.singleWhere((a) => a['id'] == 'neffe');
      expect(((astNeffe['x2'] as num) - schwesterHaus).abs(), lessThan(1));
      // Die Kinder des Bruders stehen beieinander, der Neffe nicht dazwischen.
      final reihe = ['kind1', 'kind2', 'neffe']
        ..sort((a, b) => mitte[a]!.compareTo(mitte[b]!));
      expect(reihe.indexOf('neffe'), anyOf(0, 2));
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

  test(
    'Gesicht von Hand: der Server schneidet aus und legt an (#190)',
    () async {
      final a = await ladeHoch(erikaToken, 'gruppe.jpg', 60);
      Future<Response> lege(Object werte, {String? token}) => frag(
        'POST',
        '/api/v1/aufnahmen/$a/gesichter',
        token: token ?? erikaToken,
        kopf: {'content-type': 'application/json'},
        inhalt: jsonEncode(werte),
      );
      final r = await lege({
        'kasten': [0.1, 0.2, 0.5, 0.6],
      });
      expect(r.statusCode, 201);
      final g = (await jsonAus(r))['gesicht']! as Map;
      expect(g['aufnahme'], a);
      expect(g['person'], isNull);
      expect((g['kasten'] as List)[0], closeTo(0.1, 1e-9));
      final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
      final f = (await db.facesForAsset(a)).single;
      expect(f.id, g['id']);
      expect(f.cropRelativePath, isNotNull);
      // Die Angaben zeigen es mit Rahmen.
      final angaben = await jsonAus(
        await frag('GET', '/api/v1/aufnahmen/$a/angaben', token: erikaToken),
      );
      expect(((angaben['gesichter']! as List).single as Map)['id'], f.id);

      // Gleich zugeordnet: Die Person bekommt den Ausschnitt als Bild.
      await befehl(erikaToken, 'personAnlegen', {
        'personId': 'p1',
        'name': 'Ida',
      });
      final mit = await lege({
        'kasten': [0.5, 0.1, 0.3, 0.3],
        'personId': 'p1',
      });
      expect(mit.statusCode, 201);
      expect(((await jsonAus(mit))['gesicht']! as Map)['person'], {
        'id': 'p1',
        'name': 'Ida',
      });
      final ida = await (db.select(
        db.people,
      )..where((t) => t.id.equals('p1'))).getSingle();
      expect(ida.coverFaceCropPath, isNotNull);

      expect(
        (await lege({
          'kasten': [0.1, 0.1, 0.005, 0.2],
        })).statusCode,
        400,
        reason: 'zu klein',
      );
      expect(
        (await lege({
          'kasten': [0.1, 0.1, 0.2, 0.2],
          'personId': 'gibtsnicht',
        })).statusCode,
        400,
      );
      expect(
        (await lege({
          'kasten': [0.1, 0.1, 0.2, 0.2],
        }, token: maxToken)).statusCode,
        404,
        reason: 'fremde Aufnahme',
      );

      // Löschen (#191): über den Befehl; den Ausschnitt räumt der Server
      // weg.
      final pfade = (await bibliotheken.fuer(erika.id)).bibliothek.pfade;
      final ausschnitt = pfade.absolute(f.cropRelativePath!);
      expect(ausschnitt.existsSync(), isTrue);
      expect(
        (await befehl(erikaToken, 'gesichtLoeschen', {
          'gesichtId': f.id,
        })).statusCode,
        200,
      );
      expect(
        (await db.facesForAsset(a)).map((x) => x.id),
        isNot(contains(f.id)),
      );
      for (var i = 0; i < 20 && ausschnitt.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(ausschnitt.existsSync(), isFalse);

      // Von der Gesichtssuche ausnehmen – die Angaben sagen es.
      expect(
        (await befehl(erikaToken, 'gesichtssucheAusnehmen', {
          'id': a,
          'ausgenommen': true,
        })).statusCode,
        200,
      );
      expect(
        (await jsonAus(
          await frag('GET', '/api/v1/aufnahmen/$a/angaben', token: erikaToken),
        ))['gesichtssucheAus'],
        isTrue,
      );

      // Das Gesicht hinter Idas Profilbild löschen: Das Bild zeigte sonst
      // ins Leere – sie hat kein anderes, also keins.
      final idas = (await db.facesForAsset(
        a,
      )).where((x) => x.personId == 'p1').single;
      await befehl(erikaToken, 'gesichtLoeschen', {'gesichtId': idas.id});
      final idaDanach = await (db.select(
        db.people,
      )..where((t) => t.id.equals('p1'))).getSingle();
      expect(idaDanach.coverFaceCropPath, isNull);
    },
  );

  test(
    'Alle unbenannten ignorieren oder löschen, „Ignoriert“ (#192)',
    () async {
      final a = await ladeHoch(erikaToken, 'a.jpg', 30);
      final b = (await bibliotheken.fuer(erika.id)).bibliothek;
      final db = b.db;
      await db
          .into(db.people)
          .insert(PeopleCompanion.insert(id: 'p1', name: 'Ida'));
      for (final (id, person, beiseite) in [
        ('u1', null, false),
        ('u2', null, false),
        ('i1', null, true),
        ('n1', 'p1', false),
      ]) {
        await db
            .into(db.faces)
            .insert(
              FacesCompanion.insert(
                id: id,
                assetId: a,
                personId: Value(person),
                isIgnored: Value(beiseite),
                boxX: 0.1,
                boxY: 0.1,
                boxW: 0.2,
                boxH: 0.2,
                cropRelativePath: Value(b.pfade.faceRelativePath(id)),
              ),
            );
        final datei = b.pfade.absolute(b.pfade.faceRelativePath(id));
        await datei.parent.create(recursive: true);
        await datei.writeAsBytes([1, 2, 3]);
      }
      Future<Map<String, Object?>> hol(String pfad) async =>
          jsonAus(await frag('GET', pfad, token: erikaToken));
      Future<Response> alle(Object werte) => frag(
        'POST',
        '/api/v1/gesichter/unbenannte',
        token: erikaToken,
        kopf: {'content-type': 'application/json'},
        inhalt: jsonEncode(werte),
      );

      expect((await hol('/api/v1/gesichter/ohne-namen'))['ignoriert'], 1);
      final ignoriert = await hol('/api/v1/gesichter/ignoriert');
      expect(ignoriert['gesamt'], 1);
      expect(((ignoriert['gesichter']! as List).single as Map)['id'], 'i1');

      // Ignorieren trifft nur die offenen, nicht die benannten.
      final r = await alle({'aktion': 'ignorieren'});
      expect(r.statusCode, 200);
      expect((await jsonAus(r))['anzahl'], 2);
      expect((await hol('/api/v1/gesichter/ignoriert'))['gesamt'], 3);

      // Löschen trifft alle unbenannten, auch die ignorierten – samt
      // Ausschnitten. Die benannte Ida bleibt.
      expect((await jsonAus(await alle({'aktion': 'loeschen'})))['anzahl'], 3);
      expect((await db.facesForAsset(a)).map((f) => f.id), ['n1']);
      for (var i = 0; i < 20; i++) {
        if (!b.pfade.absolute(b.pfade.faceRelativePath('u1')).existsSync()) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      for (final id in ['u1', 'u2', 'i1']) {
        expect(
          b.pfade.absolute(b.pfade.faceRelativePath(id)).existsSync(),
          isFalse,
          reason: id,
        );
      }
      expect(
        b.pfade.absolute(b.pfade.faceRelativePath('n1')).existsSync(),
        isTrue,
      );

      expect((await alle({'aktion': 'weg'})).statusCode, 400);
    },
  );

  test('Rückblick und Kalender wie am Rechner (#185)', () async {
    final a = await ladeHoch(erikaToken, 'a.jpg', 30);
    final b = await ladeHoch(erikaToken, 'b.jpg', 60);
    final c = await ladeHoch(erikaToken, 'c.jpg', 90);
    final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
    Future<void> datum(String id, DateTime d) =>
        (db.update(db.assets)..where((t) => t.id.equals(id))).write(
          AssetsCompanion(
            fileCreatedAt: Value(d),
            datumGeschaetzt: const Value(false),
          ),
        );
    await datum(a, DateTime(2024, 10, 20, 12, 34)); // heute vor zwei Jahren
    await datum(b, DateTime(2024, 3, 5, 12, 34));
    await datum(c, DateTime(2025, 7, 1, 12, 34));
    await db
        .into(db.people)
        .insert(
          PeopleCompanion.insert(
            id: 'oma',
            name: 'Oma',
            geburtsdatum: Value(DateTime(1950, 10, 22)),
          ),
        );
    await db
        .into(db.faces)
        .insert(
          FacesCompanion.insert(
            id: 'fo',
            assetId: c,
            personId: const Value('oma'),
            boxX: 0.1,
            boxY: 0.1,
            boxW: 0.2,
            boxH: 0.2,
          ),
        );

    final r = await jsonAus(
      await frag(
        'GET',
        '/api/v1/rueckblick?heute=2026-10-20',
        token: erikaToken,
      ),
    );
    expect(r['jahr'], 2026);
    final tag = (r['familientage']! as List).cast<Map>().single;
    expect(tag['art'], 'geburtstag');
    expect(tag['jahre'], 76);
    expect(tag['inTagen'], 2);
    expect(tag['namen'], ['Oma']);
    expect(
      [for (final x in (tag['aufnahmen'] as List).cast<Map>()) x['id']],
      [c],
    );
    final letzte = (r['letzte']! as List).cast<Map>();
    expect(letzte.first['kennung'], '2024-10-20');
    expect(letzte.first['jahreHer'], 2);
    expect((letzte.first['aufnahmen'] as List).cast<Map>().single['id'], a);

    final k = await jsonAus(
      await frag('GET', '/api/v1/kalender', token: erikaToken),
    );
    expect(
      [for (final j in (k['jahre']! as List).cast<Map>()) j['nummer']],
      [2025, 2024],
    );
    final m = await jsonAus(
      await frag('GET', '/api/v1/kalender/2024', token: erikaToken),
    );
    expect(
      [
        for (final x in (m['monate']! as List).cast<Map>())
          [x['nummer'], x['anzahl']],
      ],
      [
        [3, 1],
        [10, 1],
      ],
    );
    expect(((m['monate']! as List).first as Map)['titelbild'], isA<Map>());
    final okt = await jsonAus(
      await frag('GET', '/api/v1/kalender/2024/10', token: erikaToken),
    );
    expect((okt['aufnahmen']! as List).cast<Map>().single['id'], a);
    expect(
      (await frag(
        'GET',
        '/api/v1/kalender/2024/13',
        token: erikaToken,
      )).statusCode,
      400,
    );

    final j = await jsonAus(
      await frag('GET', '/api/v1/jahresrueckblick/2024', token: erikaToken),
    );
    expect(j['fotos'], 2);
    expect((j['jeMonat']! as List)[2], 1);
    expect((j['jeMonat']! as List)[9], 1);

    // Ein anderes Konto sieht nichts davon.
    expect(
      (await jsonAus(
        await frag('GET', '/api/v1/kalender', token: maxToken),
      ))['jahre'],
      isEmpty,
    );
  });

  test('Intelligente Alben: gemerkte Suchen als Album (#187)', () async {
    final strand = await ladeHoch(erikaToken, 'strand.jpg', 30);
    final berg = await ladeHoch(erikaToken, 'berg.jpg', 90);
    expect(
      (await befehl(erikaToken, 'favoritSetzen', {
        'ids': [berg],
        'favorit': true,
      })).statusCode,
      200,
    );
    // So schicken Browser und Handy eine Suche: nur, was gesetzt ist.
    for (final (id, name, filter) in [
      ('s1', 'Strand', {'query': 'stra', 'textMode': 'ueberall'}),
      ('s2', 'Lieblinge', {'favoritesOnly': true}),
      ('s3', 'Meer', {'query': 'meer', 'textMode': 'context'}),
    ]) {
      expect(
        (await befehl(erikaToken, 'sucheMerken', {
          'sucheId': id,
          'name': name,
          'filter': filter,
        })).statusCode,
        200,
        reason: name,
      );
    }
    final liste = await jsonAus(
      await frag('GET', '/api/v1/intelligente-alben', token: erikaToken),
    );
    final alben = (liste['alben']! as List).cast<Map>();
    expect(
      {for (final a in alben) a['id']: a['inhalt']},
      {'s1': false, 's2': false, 's3': true},
    );
    Future<List<Object?>> inhalt(String id) async => [
      for (final a
          in ((await jsonAus(
                    await frag(
                      'GET',
                      '/api/v1/intelligente-alben/$id',
                      token: erikaToken,
                    ),
                  ))['aufnahmen']!
                  as List)
              .cast<Map>())
        a['id'],
    ];
    expect(await inhalt('s1'), [strand]);
    expect(await inhalt('s2'), [berg]);
    // Bildinhalt braucht das Textmodell – das hat dieser Server nicht.
    expect(
      (await frag(
        'GET',
        '/api/v1/intelligente-alben/s3',
        token: erikaToken,
      )).statusCode,
      404,
    );
    expect(
      (await jsonAus(
        await frag('GET', '/api/v1/intelligente-alben', token: maxToken),
      ))['alben'],
      isEmpty,
    );
    expect(
      (await befehl(erikaToken, 'sucheVergessen', {
        'sucheId': 's2',
      })).statusCode,
      200,
    );
    expect(
      (await frag(
        'GET',
        '/api/v1/intelligente-alben/s2',
        token: erikaToken,
      )).statusCode,
      404,
    );
  });

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
    // Die Kachel trägt Herz und Format wie am Rechner.
    for (final x in (alle['aufnahmen']! as List).cast<Map>()) {
      expect(x['favorit'], isTrue);
      expect(x['format'], 'JPG');
    }
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

  test('Suche mit Filtern: ohne Text, mit Text, Auswahllisten', () async {
    final a = await ladeHoch(erikaToken, 'Strand_Rom.jpg', 10);
    final b = await ladeHoch(erikaToken, 'Strand_Kiel.jpg', 60);
    final c = await ladeHoch(erikaToken, 'Berg.jpg', 110);
    final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
    Future<void> setze(String id, String land, String stadt, DateTime wann) =>
        (db.update(db.assets)..where((t) => t.id.equals(id))).write(
          AssetsCompanion(
            locationCountry: Value(land),
            locationCity: Value(stadt),
            fileCreatedAt: Value(wann),
            cameraModel: const Value('iPhone 17 Pro'),
          ),
        );
    await setze(a, 'Italy', 'Rome', DateTime(2024, 5, 3, 12));
    await setze(b, 'Germany', 'Kiel', DateTime(2025, 7, 1, 12));
    await setze(c, 'Italy', 'Bolzano', DateTime(2025, 8, 9, 12));
    await befehl(erikaToken, 'personAnlegen', {
      'personId': 'anna',
      'name': 'Anna',
    });
    await db
        .into(db.faces)
        .insert(
          FacesCompanion.insert(
            id: 'fa',
            assetId: c,
            personId: const Value('anna'),
            boxX: 0.1,
            boxY: 0.1,
            boxW: 0.2,
            boxH: 0.2,
          ),
        );
    await befehl(erikaToken, 'favoritSetzen', {
      'ids': [b],
      'favorit': true,
    });
    Future<List<Object?>> ids(String q) async => [
      for (final z
          in ((await jsonAus(
                    await frag('GET', '/api/v1/suche?$q', token: erikaToken),
                  ))['aufnahmen']!
                  as List)
              .cast<Map>())
        z['id'],
    ];

    // Nur Filter, nach Datum geordnet (jüngste zuerst).
    expect(await ids('land=Italy'), [c, a]);
    // Seitenweise (#186): alle Kennungen, Zeilen nur für die erste Seite.
    final seite = await jsonAus(
      await frag('GET', '/api/v1/suche?land=Italy&anzahl=1', token: erikaToken),
    );
    expect(seite['kennungen'], [c, a]);
    expect(
      [for (final z in (seite['aufnahmen']! as List).cast<Map>()) z['id']],
      [c],
    );
    expect(await ids('land=Italy&stadt=Rome'), [a]);
    expect(await ids('von=2025-01-01&bis=2025-07-01'), [b]);
    expect(await ids('person=anna'), [c]);
    expect(await ids('favoriten=1'), [b]);
    expect(await ids('kamera=iPhone%2017%20Pro&art=video'), isEmpty);
    // Text und Filter zusammen.
    expect(await ids('art=text&text=strand&land=Germany'), [b]);
    // Ganz ohne beides: 400.
    expect(
      (await frag('GET', '/api/v1/suche', token: erikaToken)).statusCode,
      400,
    );

    final w = await jsonAus(
      await frag('GET', '/api/v1/suche/auswahl?sprache=de', token: erikaToken),
    );
    expect((w['personen']! as List).cast<Map>().map((p) => p['name']), [
      'Anna',
    ]);
    final orte = (w['orte']! as List).cast<Map>();
    expect(orte.map((o) => o['land']), ['Germany', 'Italy']);
    expect(orte.last['name'], 'Italien');
    expect(orte.last['staedte'], ['Bolzano', 'Rome']);
    expect(w['kameras'], ['iPhone 17 Pro']);
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

bool _hatFfmpeg() {
  try {
    return Process.runSync('ffmpeg', ['-version']).exitCode == 0;
  } catch (_) {
    return false;
  }
}
