import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Alben zwischen Konten teilen (#105): Erika teilt ihr Album „Urlaub“
/// mit Max – erst zum Ansehen, dann zum Beitragen. Moritz bekommt nichts
/// zu sehen.
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
    ordner = await Directory.systemTemp.createTemp('pv_albumteilung_');
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

  test('wählen, mit wem: alle anderen Konten, nicht das eigene', () async {
    final k = await jsonAus(
      await frag('GET', '/api/v1/konten/andere', token: maxToken),
    );
    expect(
      [for (final x in (k['konten']! as List).cast<Map>()) x['name']],
      ['erika', 'moritz'],
    );
  });

  test('zum Ansehen geteilt: Max sieht das Album, sonst nichts', () async {
    final (strand, berg, privat) = await urlaub();
    expect((await teile(max.id)).statusCode, 200);

    final liste = await mitMir(maxToken);
    expect(liste, hasLength(1));
    expect(liste.single['name'], 'Urlaub');
    expect(liste.single['besitzer'], 'erika');
    expect(liste.single['beitragen'], false);
    expect(liste.single['anzahl'], 2);
    final id = liste.single['id']! as String;

    final inhalt = await jsonAus(
      await frag('GET', '/api/v1/geteilt/$id', token: maxToken),
    );
    final zeilen = (inhalt['aufnahmen']! as List).cast<Map>();
    expect({for (final z in zeilen) z['id']}, {strand, berg});
    expect(
      zeilen.any((z) => z.containsKey('favorit')),
      isFalse,
      reason: 'Erikas Marken bleiben bei ihr',
    );

    final bild = await frag(
      'GET',
      '/api/v1/geteilt/$id/aufnahmen/$strand/ansicht',
      token: maxToken,
    );
    expect(bild.statusCode, 200);
    expect(
      (await frag(
        'GET',
        '/api/v1/geteilt/$id/aufnahmen/$privat/ansicht',
        token: maxToken,
      )).statusCode,
      404,
      reason: 'nicht im Album',
    );
    expect(
      (await frag(
        'GET',
        '/api/v1/aufnahmen/$strand/ansicht',
        token: maxToken,
      )).statusCode,
      404,
      reason: 'über den eigenen Weg sieht Max nichts von Erika',
    );

    // Moritz kennt die Teilung nicht.
    expect(await mitMir(moritzToken), isEmpty);
    expect(
      (await frag('GET', '/api/v1/geteilt/$id', token: moritzToken)).statusCode,
      404,
    );
    expect(
      (await frag(
        'GET',
        '/api/v1/geteilt/$id/aufnahmen/$strand/ansicht',
        token: moritzToken,
      )).statusCode,
      404,
    );

    // Erika sieht in ihrer Albenliste, dass es geteilt ist.
    final alben = await jsonAus(
      await frag('GET', '/api/v1/alben', token: erikaToken),
    );
    expect((alben['alben']! as List).cast<Map>().single['geteilt'], 1);
  });

  test('gesperrt oder im Papierkorb: nicht mehr zu sehen', () async {
    final (strand, berg, _) = await urlaub();
    await teile(max.id);
    final id = (await mitMir(maxToken)).single['id']! as String;
    final b = (await bibliotheken.fuer(erika.id)).bibliothek;
    await (b.db.update(b.db.assets)..where((t) => t.id.equals(strand))).write(
      const AssetsCompanion(isLocked: Value(true)),
    );
    await befehl(erikaToken, 'inDenPapierkorb', {
      'ids': [berg],
    });

    final inhalt = await jsonAus(
      await frag('GET', '/api/v1/geteilt/$id', token: maxToken),
    );
    expect(inhalt['aufnahmen'], isEmpty);
    for (final a in [strand, berg]) {
      expect(
        (await frag(
          'GET',
          '/api/v1/geteilt/$id/aufnahmen/$a/miniatur',
          token: maxToken,
        )).statusCode,
        404,
      );
    }
  });

  test('beitragen: nur mit Recht, dann direkt in Erikas Album', () async {
    await urlaub();
    await teile(max.id);
    final id = (await mitMir(maxToken)).single['id']! as String;
    Future<Response> schicke(Uint8List bytes, String name) => frag(
      'POST',
      '/api/v1/geteilt/$id/beitrag?name=$name&geaendert=1760000000000',
      token: maxToken,
      kopf: {'content-length': '${bytes.length}'},
      inhalt: bytes,
    );

    expect((await schicke(jpeg(40), 'see.jpg')).statusCode, 403);

    expect((await teile(max.id, beitragen: true)).statusCode, 200);
    final r = await schicke(jpeg(40), 'see.jpg');
    expect(r.statusCode, 201);
    final j = await jsonAus(r);
    expect(j['ausgang'], 'imported');
    final neu = j['aufnahme']! as String;

    final b = (await bibliotheken.fuer(erika.id)).bibliothek;
    expect((await b.db.assetById(neu))?.originalFileName, 'see.jpg');
    expect([
      for (final a in await b.db.albumAufnahmen('urlaub')) a.id,
    ], contains(neu));
    final zeile =
        (await jsonAus(
              await frag('GET', '/api/v1/geteilt/$id', token: maxToken),
            ))['aufnahmen']!
            as List;
    final beitrag = zeile.cast<Map>().singleWhere((z) => z['id'] == neu);
    expect(beitrag['von'], 'max');
    expect(beitrag['eigene'], true);
    // Erika sieht im eigenen Album, von wem es kam.
    final eigen =
        (await jsonAus(
              await frag('GET', '/api/v1/alben/urlaub', token: erikaToken),
            ))['aufnahmen']!
            as List;
    expect(eigen.cast<Map>().singleWhere((z) => z['id'] == neu)['von'], 'max');
    // In Max' eigener Bibliothek landet nichts.
    final maxB = (await bibliotheken.fuer(max.id)).bibliothek;
    expect(await maxB.db.assetById(neu), isNull);

    // Dasselbe noch einmal: liegt schon da, bleibt im Album.
    final noch = await jsonAus(await schicke(jpeg(40), 'see.jpg'));
    expect(noch['ausgang'], 'duplicateSkipped');
    expect(noch['aufnahme'], neu);
  });

  test('eigene Beiträge wieder entfernen, fremde nicht (#290)', () async {
    final (strand, _, _) = await urlaub();
    await teile(max.id, beitragen: true);
    final id = (await mitMir(maxToken)).single['id']! as String;
    Future<String> schicke(int farbe, String name) async {
      final bytes = jpeg(farbe);
      final r = await frag(
        'POST',
        '/api/v1/geteilt/$id/beitrag?name=$name',
        token: maxToken,
        kopf: {'content-length': '${bytes.length}'},
        inhalt: bytes,
      );
      return (await jsonAus(r))['aufnahme']! as String;
    }

    final see = await schicke(40, 'see.jpg');
    final wald = await schicke(160, 'wald.jpg');
    Future<Response> entferne(String a, [String? token]) => frag(
      'DELETE',
      '/api/v1/geteilt/$id/aufnahmen/$a',
      token: token ?? maxToken,
    );

    expect((await entferne(strand)).statusCode, 403, reason: 'Erikas Foto');
    expect(
      (await entferne(see, moritzToken)).statusCode,
      404,
      reason: 'Moritz kennt die Teilung nicht',
    );

    final b = (await bibliotheken.fuer(erika.id)).bibliothek;
    // Erika hat „wald“ auch in ein eigenes Album gelegt.
    await befehl(erikaToken, 'albumAnlegen', {
      'albumId': 'natur',
      'name': 'Natur',
      'angelegtAm': '2026-10-18T10:00:00Z',
    });
    await befehl(erikaToken, 'albumFuellen', {
      'albumId': 'natur',
      'ids': [wald],
    });

    final r1 = await entferne(see);
    expect(r1.statusCode, 200);
    expect((await jsonAus(r1))['papierkorb'], true);
    expect((await b.db.assetById(see))!.isTrashed, isTrue);

    final r2 = await entferne(wald);
    expect((await jsonAus(r2))['papierkorb'], false, reason: 'noch in „Natur“');
    expect((await b.db.assetById(wald))!.isTrashed, isFalse);

    final im = [for (final a in await b.db.albumAufnahmen('urlaub')) a.id];
    expect(im, isNot(contains(see)));
    expect(im, isNot(contains(wald)));
    expect(im, contains(strand));
  });

  test(
    'Erika erfährt von neuen Beiträgen, bis sie das Album öffnet (#295)',
    () async {
      await urlaub();
      await teile(max.id, beitragen: true);
      final id = (await mitMir(maxToken)).single['id']! as String;
      Future<Map<String, Object?>> neu() async => jsonAus(
        await frag('GET', '/api/v1/kontobeitraege', token: erikaToken),
      );
      expect((await neu())['alben'], isEmpty);

      for (final (farbe, name) in [(40, 'see.jpg'), (160, 'wald.jpg')]) {
        final bytes = jpeg(farbe);
        await frag(
          'POST',
          '/api/v1/geteilt/$id/beitrag?name=$name',
          token: maxToken,
          kopf: {'content-length': '${bytes.length}'},
          inhalt: bytes,
        );
      }
      final alben = ((await neu())['alben']! as List).cast<Map>();
      expect(alben.single['id'], 'urlaub');
      expect(alben.single['name'], 'Urlaub');
      expect(alben.single['anzahl'], 2);
      expect(alben.single['von'], ['max']);
      expect(alben.single['titelbild'], isNotNull);
      // Max sieht nichts davon – es geht um Erikas Alben.
      expect(
        (await jsonAus(
          await frag('GET', '/api/v1/kontobeitraege', token: maxToken),
        ))['alben'],
        isEmpty,
      );

      expect(
        (await frag(
          'POST',
          '/api/v1/alben/urlaub/kontobeitraege/gesehen',
          token: erikaToken,
        )).statusCode,
        204,
      );
      expect((await neu())['alben'], isEmpty);
    },
  );

  test('Serverdatenbank 6: Beiträge von vorher gelten als gesehen', () async {
    final ordner = await Directory.systemTemp.createTemp('pv_teilung_mig7_');
    final datei = File('${ordner.path}/server.sqlite');
    var bank = Serverdatenbank.oeffne(datei);
    try {
      bank.db.execute(
        "INSERT INTO konten (id, name, angelegt) VALUES ('k', 'erika', 1)",
      );
      bank.db.execute('DROP INDEX kontobeitraege_neu');
      bank.db.execute('ALTER TABLE kontobeitraege DROP COLUMN gesehen');
      bank.db.execute('ALTER TABLE kontobeitraege DROP COLUMN album');
      bank.db.execute(
        'INSERT INTO kontobeitraege (besitzer, aufnahme, von, name, angelegt) '
        "VALUES ('k', 'a1', NULL, 'max', 1)",
      );
      bank.db.execute('PRAGMA user_version = 6');
      bank.schliesse();
      bank = Serverdatenbank.oeffne(datei);
      expect(
        bank.db.select('SELECT gesehen FROM kontobeitraege').single['gesehen'],
        1,
      );
      expect(bank.db.select('PRAGMA user_version').single.columnAt(0), 7);
    } finally {
      bank.schliesse();
      await ordner.delete(recursive: true);
    }
  });

  test('Erika hört auf zu teilen, Max verlässt ein Album', () async {
    await urlaub();
    await teile(max.id);
    await teile((konten.kontoNamens('moritz'))!.id, beitragen: true);
    final wer =
        (await jsonAus(
              await frag(
                'GET',
                '/api/v1/alben/urlaub/teilungen',
                token: erikaToken,
              ),
            ))['teilungen']!
            as List;
    expect([for (final t in wer.cast<Map>()) t['name']], ['max', 'moritz']);

    final id = (await mitMir(maxToken)).single['id']! as String;
    expect(
      (await frag('DELETE', '/api/v1/geteilt/$id', token: maxToken)).statusCode,
      204,
    );
    expect(await mitMir(maxToken), isEmpty);

    expect(
      (await frag(
        'DELETE',
        '/api/v1/alben/urlaub/teilungen/${konten.kontoNamens('moritz')!.id}',
        token: erikaToken,
      )).statusCode,
      204,
    );
    expect(await mitMir(moritzToken), isEmpty);
  });

  test('nur eigene Alben, nicht mit sich selbst', () async {
    await urlaub();
    expect(
      (await frag(
        'PUT',
        '/api/v1/alben/urlaub/teilungen/${erika.id}',
        token: maxToken,
        inhalt: '{}',
      )).statusCode,
      404,
      reason: 'Max hat kein Album „urlaub“',
    );
    expect((await teile(erika.id)).statusCode, 404);
  });

  test('ein gelöschtes Album verschwindet auch beim Empfänger', () async {
    await urlaub();
    await teile(max.id);
    final b = (await bibliotheken.fuer(erika.id)).bibliothek;
    await (b.db.delete(b.db.albums)..where((t) => t.id.equals('urlaub'))).go();

    expect(await mitMir(maxToken), isEmpty);
    expect(konten.albumteilungen.vonBesitzer(erika.id), isEmpty);
  });

  test('ein gelöschtes Konto nimmt seine Teilungen mit', () async {
    await urlaub();
    await teile(max.id);
    konten.entferne(max.id);
    expect(konten.albumteilungen.vonBesitzer(erika.id), isEmpty);
  });

  test('Serverdatenbank 5 bekommt die Teilungen, die Konten bleiben', () async {
    final ordner = await Directory.systemTemp.createTemp('pv_teilung_mig_');
    final datei = File('${ordner.path}/server.sqlite');
    var bank = Serverdatenbank.oeffne(datei);
    try {
      bank.db.execute(
        "INSERT INTO konten (id, name, angelegt) VALUES ('k', 'pruefkonto', 1)",
      );
      bank.db.execute('DROP TABLE albumteilungen');
      bank.db.execute('DROP TABLE kontobeitraege');
      bank.db.execute('PRAGMA user_version = 5');
      bank.schliesse();
      bank = Serverdatenbank.oeffne(datei);
      expect(
        bank.db.select('SELECT name FROM konten').single['name'],
        'pruefkonto',
      );
      expect(
        bank.db.select('SELECT count(*) AS n FROM albumteilungen').single['n'],
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
