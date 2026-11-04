import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Kommentare und „Gefällt mir“ in geteilten Alben (#297): Erika teilt
/// „Urlaub“ mit Max zum Ansehen. Beide sagen etwas dazu; Moritz, mit dem
/// nichts geteilt ist, weder sieht noch schreibt etwas.
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
    ordner = await Directory.systemTemp.createTemp('pv_albumkommentare_');
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
      frag(
        'POST',
        '/api/v1/befehle',
        token: token,
        kopf: {'content-type': 'application/json'},
        inhalt: jsonEncode({'art': art, 'werte': w}),
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

  Future<Map<String, Object?>> aktivitaet(String pfad, String token) async =>
      jsonAus(await frag('GET', '$pfad/aktivitaet', token: token));

  Future<Response> kommentiere(
    String pfad,
    String token,
    String text, {
    String? aufnahme,
  }) => frag(
    'POST',
    '$pfad/kommentare',
    token: token,
    kopf: {'content-type': 'application/json'},
    inhalt: jsonEncode({'text': text, 'aufnahme': ?aufnahme}),
  );

  Future<String> geteiltFuerMax() async {
    expect((await teile(max.id)).statusCode, 200);
    return (await mitMir(maxToken)).single['id']! as String;
  }

  test(
    'beide Seiten kommentieren und finden gut, was im Album liegt',
    () async {
      final (strand, berg, privat) = await urlaub();
      final id = await geteiltFuerMax();
      const eigen = '/api/v1/alben/urlaub';
      final fremd = '/api/v1/geteilt/$id';

      // Max darf nur ansehen – reden darf er trotzdem.
      final k1 = await kommentiere(
        fremd,
        maxToken,
        '  Schöner Strand!  ',
        aufnahme: strand,
      );
      expect(k1.statusCode, 201);
      expect((await jsonAus(k1))['text'], 'Schöner Strand!');
      expect(
        (await kommentiere(
          eigen,
          erikaToken,
          'Danke für eure Fotos',
        )).statusCode,
        201,
      );
      expect(
        (await frag(
          'PUT',
          '$fremd/gefaellt/$strand',
          token: maxToken,
        )).statusCode,
        204,
      );
      expect(
        (await frag(
          'PUT',
          '$eigen/gefaellt/$strand',
          token: erikaToken,
        )).statusCode,
        204,
      );
      // Zweimal ist wie einmal.
      expect(
        (await frag(
          'PUT',
          '$fremd/gefaellt/$strand',
          token: maxToken,
        )).statusCode,
        204,
      );

      // Was nicht im Album liegt, nimmt es nicht an.
      expect(
        (await kommentiere(
          fremd,
          maxToken,
          'privat?',
          aufnahme: privat,
        )).statusCode,
        404,
      );
      expect(
        (await frag(
          'PUT',
          '$fremd/gefaellt/$privat',
          token: maxToken,
        )).statusCode,
        404,
      );
      expect((await kommentiere(fremd, maxToken, '   ')).statusCode, 400);
      expect((await kommentiere(fremd, maxToken, 'x' * 2001)).statusCode, 400);

      final ausSicht = await aktivitaet(fremd, maxToken);
      final kommentare = (ausSicht['kommentare']! as List).cast<Map>();
      expect(
        [for (final k in kommentare) k['text']],
        ['Schöner Strand!', 'Danke für eure Fotos'],
      );
      expect(kommentare.first['aufnahme'], strand);
      expect(kommentare.first['name'], 'max');
      expect(kommentare.first['eigener'], true);
      expect(kommentare.last.containsKey('aufnahme'), isFalse);
      expect(kommentare.last['loeschbar'], false, reason: 'Erikas Kommentar');
      final gefaellt = (ausSicht['gefaellt']! as Map)[strand]! as Map;
      expect(gefaellt['anzahl'], 2);
      expect(gefaellt['ich'], true);
      expect(gefaellt['namen'], ['max', 'erika']);
      expect((ausSicht['gefaellt']! as Map).containsKey(berg), isFalse);

      // Erika sieht dasselbe – und darf jeden Kommentar entfernen.
      final besitzerSicht = await aktivitaet(eigen, erikaToken);
      final vonMax = ((besitzerSicht['kommentare']! as List).cast<Map>()).first;
      expect(vonMax['loeschbar'], true);
      expect(vonMax['eigener'], false);

      // Max nimmt sein „Gefällt mir“ zurück.
      expect(
        (await frag(
          'DELETE',
          '$fremd/gefaellt/$strand',
          token: maxToken,
        )).statusCode,
        204,
      );
      final danach =
          ((await aktivitaet(eigen, erikaToken))['gefaellt']! as Map)[strand]!
              as Map;
      expect(danach['anzahl'], 1);
      expect(danach['ich'], true);
    },
  );

  test(
    'wer darf entfernen: der Schreiber seinen, der Besitzer jeden',
    () async {
      final (strand, _, _) = await urlaub();
      final id = await geteiltFuerMax();
      const eigen = '/api/v1/alben/urlaub';
      final fremd = '/api/v1/geteilt/$id';
      final vonMax = (await jsonAus(
        await kommentiere(fremd, maxToken, 'eins'),
      ))['id'];
      final vonMax2 = (await jsonAus(
        await kommentiere(fremd, maxToken, 'zwei', aufnahme: strand),
      ))['id'];
      final vonErika = (await jsonAus(
        await kommentiere(eigen, erikaToken, 'drei'),
      ))['id'];

      expect(
        (await frag(
          'DELETE',
          '$fremd/kommentare/$vonErika',
          token: maxToken,
        )).statusCode,
        404,
      );
      expect(
        (await frag(
          'DELETE',
          '$fremd/kommentare/$vonMax',
          token: maxToken,
        )).statusCode,
        204,
      );
      expect(
        (await frag(
          'DELETE',
          '$eigen/kommentare/$vonMax2',
          token: erikaToken,
        )).statusCode,
        204,
      );
      final uebrig =
          ((await aktivitaet(eigen, erikaToken))['kommentare']! as List)
              .cast<Map>();
      expect([for (final k in uebrig) k['text']], ['drei']);
    },
  );

  test('ohne Teilung nichts – weder lesen noch schreiben', () async {
    final (strand, _, _) = await urlaub();
    final id = await geteiltFuerMax();
    final fremd = '/api/v1/geteilt/$id';
    expect(
      (await frag('GET', '$fremd/aktivitaet', token: moritzToken)).statusCode,
      404,
    );
    expect((await kommentiere(fremd, moritzToken, 'hallo')).statusCode, 404);
    expect(
      (await frag(
        'PUT',
        '$fremd/gefaellt/$strand',
        token: moritzToken,
      )).statusCode,
      404,
    );
    expect(
      (await frag(
        'GET',
        '/api/v1/alben/urlaub/aktivitaet',
        token: maxToken,
      )).statusCode,
      404,
    );

    // Hebt Erika die Teilung auf, kommt Max nicht mehr heran.
    expect(
      (await frag(
        'DELETE',
        '/api/v1/alben/urlaub/teilungen/${max.id}',
        token: erikaToken,
      )).statusCode,
      lessThan(300),
    );
    expect(
      (await frag('GET', '$fremd/aktivitaet', token: maxToken)).statusCode,
      404,
    );
  });

  test('endgültig gelöscht: Kommentare und „Gefällt mir“ gehen mit', () async {
    final (strand, _, _) = await urlaub();
    final id = await geteiltFuerMax();
    final fremd = '/api/v1/geteilt/$id';
    await kommentiere(fremd, maxToken, 'weg damit', aufnahme: strand);
    await frag('PUT', '$fremd/gefaellt/$strand', token: maxToken);
    konten.albumteilungen.vergissBeitraege(erika.id, [strand]);
    expect(konten.albumteilungen.kommentare(erika.id, 'urlaub'), isEmpty);
    expect(konten.albumteilungen.gefaelltIn(erika.id, 'urlaub'), isEmpty);
  });

  test('der Server sagt, dass er es kann', () async {
    final z = await jsonAus(
      await frag('GET', '/api/v1/zustand', token: maxToken),
    );
    expect((z['funktionen']! as Map)['kommentare'], 1);
  });

  test('Serverdatenbank 8 bekommt Kommentare, Teilungen bleiben', () async {
    final ordner = await Directory.systemTemp.createTemp('pv_kommentar_mig_');
    final datei = File('${ordner.path}/server.sqlite');
    var bank = Serverdatenbank.oeffne(datei);
    try {
      bank.db.execute(
        "INSERT INTO konten (id, name, angelegt) VALUES ('k', 'a', 1), "
        "('m', 'b', 1)",
      );
      bank.db.execute(
        'INSERT INTO albumteilungen (id, besitzer, album, empfaenger, '
        "angelegt) VALUES ('t', 'k', 'urlaub', 'm', 1)",
      );
      bank.db.execute('DROP TABLE albumkommentare');
      bank.db.execute('DROP TABLE albumgefaellt');
      bank.db.execute('PRAGMA user_version = 8');
      bank.schliesse();
      bank = Serverdatenbank.oeffne(datei);
      expect(
        bank.db.select('SELECT count(*) AS n FROM albumteilungen').single['n'],
        1,
      );
      expect(
        bank.db.select('SELECT count(*) AS n FROM albumkommentare').single['n'],
        0,
      );
      expect(
        bank.db.select('PRAGMA user_version').single.columnAt(0),
        Serverdatenbank.schema,
      );
    } finally {
      bank.schliesse();
      await ordner.delete(recursive: true);
    }
  });
}
