import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:photo_vault_server/src/albumteilungen.dart' show Albumteilungen;
import 'package:photo_vault_server/src/videofassung.dart';
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

  Future<String> ladeHoch(
    String token,
    String name,
    int farbe, {
    Uint8List? inhalt,
  }) async {
    final bytes = inhalt ?? jpeg(farbe);
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
    // Ebenso in ihrer Zeitleiste; was sie selbst hat, trägt kein „von“.
    final zeitleiste =
        ((await jsonAus(
                  await frag('GET', '/api/v1/aufnahmen', token: erikaToken),
                ))['aufnahmen']!
                as List)
            .cast<Map>();
    expect(zeitleiste.singleWhere((z) => z['id'] == neu)['von'], 'max');
    expect(
      zeitleiste.where((z) => z['id'] != neu).any((z) => z.containsKey('von')),
      isFalse,
    );
    // In Max' eigener Bibliothek landet nichts.
    final maxB = (await bibliotheken.fuer(max.id)).bibliothek;
    expect(await maxB.db.assetById(neu), isNull);

    // Dasselbe noch einmal: liegt schon da, bleibt im Album.
    final noch = await jsonAus(await schicke(jpeg(40), 'see.jpg'));
    expect(noch['ausgang'], 'duplicateSkipped');
    expect(noch['aufnahme'], neu);
  });

  // #426: Eine Dublette eines gesperrten Fotos oder eines im Papierkorb
  // kam ins geteilte Album, und die Antwort nannte seine Kennung.
  test('Beitrag gleich einem gesperrten oder weggeworfenen Foto: nicht ins '
      'Album, keine Kennung', () async {
    final (_, _, privat) = await urlaub();
    final weg = await ladeHoch(erikaToken, 'weg.jpg', 150);
    final b = (await bibliotheken.fuer(erika.id)).bibliothek;
    await (b.db.update(b.db.assets)..where((t) => t.id.equals(privat))).write(
      const AssetsCompanion(isLocked: Value(true)),
    );
    await befehl(erikaToken, 'inDenPapierkorb', {
      'ids': [weg],
    });
    await teile(max.id, beitragen: true);
    final id = (await mitMir(maxToken)).single['id']! as String;
    for (final (farbe, kennung) in [(200, privat), (150, weg)]) {
      final bytes = jpeg(farbe);
      final r = await frag(
        'POST',
        '/api/v1/geteilt/$id/beitrag?name=gleich.jpg',
        token: maxToken,
        kopf: {'content-length': '${bytes.length}'},
        inhalt: bytes,
      );
      final text = await r.readAsString();
      expect(r.statusCode, 409, reason: text);
      expect(text, isNot(contains(kennung)));
      expect([
        for (final a in await b.db.albumAufnahmen('urlaub')) a.id,
      ], isNot(contains(kennung)));
      expect(
        await (b.db.select(
          b.db.albumAssets,
        )..where((t) => t.assetId.equals(kennung))).get(),
        isEmpty,
      );
    }
  });

  // #426: Geprüft wurde nur, ob die letzte Messung „voll“ sagte – nicht,
  // ob die Datei selbst noch Platz hat.
  test('beitragen: die Datei selbst muss noch Platz haben', () async {
    await urlaub();
    var frei = 1 << 40;
    final speicher = Speicherwaechter(
      ordner,
      mindestFrei: 1000000,
      messung: (_) async => Speicherstand(gesamt: 1 << 41, frei: frei),
    );
    api = baueApi(
      konten: konten,
      bibliotheken: bibliotheken,
      speicher: speicher,
    );
    await teile(max.id, beitragen: true);
    final id = (await mitMir(maxToken)).single['id']! as String;
    final bytes = jpeg(40);
    Future<int> schicke() async => (await frag(
      'POST',
      '/api/v1/geteilt/$id/beitrag?name=see.jpg',
      token: maxToken,
      kopf: {'content-length': '${bytes.length}'},
      inhalt: bytes,
    )).statusCode;
    frei = 1000000 + bytes.length - 1;
    await speicher.pruefe();
    expect(speicher.voll, isFalse);
    expect(await schicke(), 507);
    expect(speicher.reserviert, 0);
    frei = 1000000 + bytes.length;
    await speicher.pruefe();
    expect(await schicke(), 201);
  });

  // #436: Eine Zeit ausserhalb dessen, was DateTime fasst, endete mit 500.
  test('beitragen mit unmöglicher Zeit: angenommen, Zeit übergangen', () async {
    await urlaub();
    await teile(max.id, beitragen: true);
    final id = (await mitMir(maxToken)).single['id']! as String;
    final bytes = jpeg(66);
    final r = await frag(
      'POST',
      '/api/v1/geteilt/$id/beitrag?name=see.jpg&geaendert=9999999999999999',
      token: maxToken,
      kopf: {'content-length': '${bytes.length}'},
      inhalt: bytes,
    );
    expect(r.statusCode, 201, reason: await r.readAsString());
  });

  // #436: Ein Lesezeichen mit einer Zeit, die DateTime nicht fasst, warf
  // in der Zeitleiste und in der eines Partners.
  test(
    'Zeitleisten: ein Lesezeichen jenseits von DateTime fängt vorn an',
    () async {
      await urlaub();
      const nach = 'nach=99999999999999999~x';
      final eigen = await frag(
        'GET',
        '/api/v1/aufnahmen?$nach',
        token: erikaToken,
      );
      expect(eigen.statusCode, 200);
      expect((await jsonAus(eigen))['aufnahmen'], hasLength(3));
      final gesetzt = await frag(
        'PUT',
        '/api/v1/partner/${max.id}',
        token: erikaToken,
        kopf: {'content-type': 'application/json'},
        inhalt: '{}',
      );
      expect(
        gesetzt.statusCode,
        lessThan(300),
        reason: await gesetzt.readAsString(),
      );
      final partner = await frag(
        'GET',
        '/api/v1/partner/von/${erika.id}/aufnahmen?$nach',
        token: maxToken,
      );
      expect(partner.statusCode, 200);
      expect((await jsonAus(partner))['aufnahmen'], hasLength(3));
    },
  );

  // #436: „Geteilt mit mir“ fragt je Besitzer einmal nach Alben,
  // Anzahlen und Titelbildern – mit denselben Angaben wie vorher.
  test('geteilt mit mir: mehrere Alben eines Besitzers, gewähltes '
      'Titelbild', () async {
    final (strand, berg, privat) = await urlaub();
    await befehl(erikaToken, 'albumAnlegen', {
      'albumId': 'zweites',
      'name': 'Zweites',
      'angelegtAm': '2026-10-18T10:00:00Z',
    });
    await befehl(erikaToken, 'albumFuellen', {
      'albumId': 'zweites',
      'ids': [berg, privat],
    });
    await befehl(erikaToken, 'albumTitelbildSetzen', {
      'albumId': 'zweites',
      'id': privat,
    });
    await teile(max.id);
    await frag(
      'PUT',
      '/api/v1/alben/zweites/teilungen/${max.id}',
      token: erikaToken,
      kopf: {'content-type': 'application/json'},
      inhalt: jsonEncode({'beitragen': true}),
    );
    final liste = await mitMir(maxToken);
    expect(liste.map((a) => a['name']), unorderedEquals(['Urlaub', 'Zweites']));
    final urlaubKarte = liste.singleWhere((a) => a['name'] == 'Urlaub');
    final zweites = liste.singleWhere((a) => a['name'] == 'Zweites');
    expect(urlaubKarte['anzahl'], 2);
    expect([strand, berg], contains(urlaubKarte['titelbild']));
    expect(urlaubKarte['beitragen'], false);
    expect(zweites['anzahl'], 2);
    expect(zweites['titelbild'], privat);
    expect(zweites['titelstand'], isNotNull);
    expect(zweites['beitragen'], true);
    // Ein gelöschtes Album verschwindet samt Teilung.
    final b = (await bibliotheken.fuer(erika.id)).bibliothek;
    await (b.db.delete(b.db.albums)..where((t) => t.id.equals('zweites'))).go();
    expect((await mitMir(maxToken)).map((a) => a['name']), ['Urlaub']);
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
      expect(
        bank.db.select('PRAGMA user_version').single.columnAt(0),
        Serverdatenbank.schema,
      );
    } finally {
      bank.schliesse();
      await ordner.delete(recursive: true);
    }
  });

  test(
    'Partnerfreigabe: Max sieht Erikas ganze Bibliothek, blätternd (#293)',
    () async {
      final (strand, berg, privat) = await urlaub();
      Future<Response> partner(String methode, String pfad, String token) =>
          frag(methode, '/api/v1/partner$pfad', token: token);

      expect(
        ((await jsonAus(await partner('GET', '', maxToken)))['mitMir']!
            as List),
        isEmpty,
      );
      expect((await partner('PUT', '/${max.id}', erikaToken)).statusCode, 204);
      expect(
        (await partner('PUT', '/${erika.id}', erikaToken)).statusCode,
        404,
      );

      final p = await jsonAus(await partner('GET', '', maxToken));
      final mitMir = (p['mitMir']! as List).cast<Map>().single;
      expect(mitMir['name'], 'erika');
      expect(mitMir['anzahl'], 3);
      final meine =
          (await jsonAus(await partner('GET', '', erikaToken)))['meine']!
              as List;
      expect([for (final x in meine.cast<Map>()) x['name']], ['max']);

      // Seitenweise, ohne Erikas Marken.
      final eins = await jsonAus(
        await partner('GET', '/von/${erika.id}/aufnahmen?anzahl=2', maxToken),
      );
      final zwei = await jsonAus(
        await partner(
          'GET',
          '/von/${erika.id}/aufnahmen?anzahl=2&nach=${Uri.encodeQueryComponent('${eins['weiter']}')}',
          maxToken,
        ),
      );
      final ids = [
        for (final z in [
          ...eins['aufnahmen']! as List,
          ...zwei['aufnahmen']! as List,
        ])
          (z as Map)['id'],
      ];
      expect(ids.toSet(), {strand, berg, privat});
      expect(ids, hasLength(3), reason: 'nichts doppelt');
      expect(zwei['weiter'], isNull);
      expect(
        [
          ...eins['aufnahmen']! as List,
        ].any((z) => (z as Map).containsKey('favorit')),
        isFalse,
      );
      expect(
        (await partner(
          'GET',
          '/von/${erika.id}/aufnahmen/$privat/miniatur',
          maxToken,
        )).statusCode,
        200,
      );

      // Moritz sieht nichts.
      expect(
        (await partner(
          'GET',
          '/von/${erika.id}/aufnahmen',
          moritzToken,
        )).statusCode,
        404,
      );
      expect(
        (await partner(
          'GET',
          '/von/${erika.id}/aufnahmen/$privat/miniatur',
          moritzToken,
        )).statusCode,
        404,
      );

      // Gesperrtes nie.
      final b = (await bibliotheken.fuer(erika.id)).bibliothek;
      await (b.db.update(b.db.assets)..where((t) => t.id.equals(privat))).write(
        const AssetsCompanion(isLocked: Value(true)),
      );
      final danach = await jsonAus(
        await partner('GET', '/von/${erika.id}/aufnahmen', maxToken),
      );
      expect([
        for (final z in danach['aufnahmen']! as List) (z as Map)['id'],
      ], isNot(contains(privat)));
      expect(
        (await partner(
          'GET',
          '/von/${erika.id}/aufnahmen/$privat/miniatur',
          maxToken,
        )).statusCode,
        404,
      );

      // Archiviertes fehlt in der Zeitleiste (#304) – und in der Zahl und
      // im Titelbild der Karte: Sie zählte es mit.
      for (final id in [strand, berg]) {
        await (b.db.update(b.db.assets)..where((t) => t.id.equals(id))).write(
          const AssetsCompanion(isArchived: Value(true)),
        );
      }
      final ohneArchiv = await jsonAus(
        await partner('GET', '/von/${erika.id}/aufnahmen', maxToken),
      );
      expect(ohneArchiv['aufnahmen'], isEmpty);
      final karte =
          ((await jsonAus(await partner('GET', '', maxToken)))['mitMir']!
                  as List)
              .cast<Map>()
              .single;
      expect(karte['anzahl'], 0);
      expect(karte.containsKey('titelbild'), isFalse);

      // Max verlässt die Freigabe – oder Erika hebt sie auf.
      expect(
        (await partner('DELETE', '/von/${erika.id}', maxToken)).statusCode,
        204,
      );
      expect(
        (await partner(
          'GET',
          '/von/${erika.id}/aufnahmen',
          maxToken,
        )).statusCode,
        404,
      );
      await partner('PUT', '/${max.id}', erikaToken);
      expect(
        (await partner('DELETE', '/${max.id}', erikaToken)).statusCode,
        204,
      );
      expect(
        ((await jsonAus(await partner('GET', '', maxToken)))['mitMir']!
            as List),
        isEmpty,
      );
    },
  );

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

  // --- Der Ort für andere Konten (#463, WEB-087, WEB-167) ------------------

  /// Ein JPEG mit Ort, Kamera und Drehung – wie vom Telefon.
  Uint8List jpegMitOrt() {
    final bild = img.Image(width: 48, height: 32);
    img.fill(bild, color: img.ColorRgb8(40, 160, 90));
    bild.exif.imageIfd.make = 'Kamera-Hersteller';
    bild.exif.imageIfd.model = 'Kamera-Modell';
    bild.exif.exifIfd['DateTimeOriginal'] = img.IfdValueAscii(
      '2025:09:11 12:00:00',
    );
    final gps = bild.exif.gpsIfd;
    gps[1] = img.IfdValueAscii('N');
    gps[2] = img.IfdValueRational(54, 1)
      ..value.addAll(img.IfdValueRational(19, 1).value)
      ..value.addAll(img.IfdValueRational(1234, 100).value);
    gps[3] = img.IfdValueAscii('E');
    gps[4] = img.IfdValueRational(10, 1)
      ..value.addAll(img.IfdValueRational(7, 1).value)
      ..value.addAll(img.IfdValueRational(4321, 100).value);
    return Uint8List.fromList(img.encodeJpg(bild, quality: 90));
  }

  Future<Uint8List> bytesAus(Response r) async =>
      Uint8List.fromList(await r.read().expand((x) => x).toList());

  /// Ob [bytes] ein Bild mit Ort im EXIF ist.
  bool mitGps(Uint8List bytes) =>
      !(img.decodeJpgExif(bytes)?.gpsIfd.isEmpty ?? true);

  /// Erikas Album „Urlaub“ mit einem Foto samt Ort.
  Future<(String, Uint8List)> urlaubMitOrt() async {
    final roh = jpegMitOrt();
    final ort = await ladeHoch(erikaToken, 'hafen.jpg', 0, inhalt: roh);
    await befehl(erikaToken, 'albumAnlegen', {
      'albumId': 'urlaub',
      'name': 'Urlaub',
      'angelegtAm': '2026-10-17T10:00:00Z',
    });
    await befehl(erikaToken, 'albumFuellen', {
      'albumId': 'urlaub',
      'ids': [ort],
    });
    return (ort, roh);
  }

  test('WEB-087 geteiltes Album: ohne Erlaubnis kein Ort, weder in den '
      'Zeilen noch in einer Datei; mit Erlaubnis das Original', () async {
    final (ort, roh) = await urlaubMitOrt();
    expect(mitGps(roh), isTrue);
    // Erika selbst sieht den Ort.
    final eigen = await jsonAus(
      await frag('GET', '/api/v1/alben/urlaub', token: erikaToken),
    );
    expect(((eigen['aufnahmen']! as List).single as Map)['ort'], isNotNull);

    expect((await teile(max.id)).statusCode, 200);
    final teilung =
        (await jsonAus(
              await frag(
                'GET',
                '/api/v1/alben/urlaub/teilungen',
                token: erikaToken,
              ),
            ))['teilungen']!
            as List;
    expect((teilung.single as Map)['mitOrt'], isFalse, reason: 'Vorgabe');
    final liste = await mitMir(maxToken);
    expect(liste.single['mitOrt'], isFalse);
    final id = liste.single['id']! as String;
    final album = await jsonAus(
      await frag('GET', '/api/v1/geteilt/$id', token: maxToken),
    );
    expect((album['album']! as Map)['mitOrt'], isFalse);
    final zeile = (album['aufnahmen']! as List).single as Map;
    expect(zeile.containsKey('ort'), isFalse);
    expect(zeile['ohneOrt'], isTrue);

    Future<Response> datei(String art) =>
        frag('GET', '/api/v1/geteilt/$id/aufnahmen/$ort/$art', token: maxToken);
    // Das Original: ein JPEG mit Aufnahmezeit und Kamera, ohne Ort.
    final original = await datei('original');
    expect(original.statusCode, 200);
    expect(original.headers['content-type'], 'image/jpeg');
    expect(original.headers['content-disposition'], contains('hafen.jpg'));
    final bytes = await bytesAus(original);
    expect(bytes, isNot(roh));
    expect(mitGps(bytes), isFalse);
    expect(img.decodeJpgExif(bytes)!.imageIfd.model, 'Kamera-Modell');
    // Ansicht, Vorschau, volle Grösse und Miniatur ebenso.
    for (final art in ['ansicht', 'vorschau', 'voll', 'miniatur']) {
      final r = await datei(art);
      expect(r.statusCode, 200, reason: art);
      final b = await bytesAus(r);
      expect(img.decodeJpg(b), isNotNull, reason: art);
      expect(mitGps(b), isFalse, reason: art);
    }
    // Ein zweiter Abruf mit dem Merkmal: 304, ohne Inhalt.
    final ansicht = await datei('ansicht');
    final etag = ansicht.headers['etag']!;
    await ansicht.read().drain<void>();
    expect(
      (await frag(
        'GET',
        '/api/v1/geteilt/$id/aufnahmen/$ort/ansicht',
        token: maxToken,
        kopf: {'if-none-match': etag},
      )).statusCode,
      304,
    );

    // Erika erlaubt den Ort: das unveränderte Original, der Ort in der Zeile.
    final erlaubt = await frag(
      'PUT',
      '/api/v1/alben/urlaub/teilungen/${max.id}',
      token: erikaToken,
      kopf: {'content-type': 'application/json'},
      inhalt: jsonEncode({'beitragen': false, 'mitOrt': true}),
    );
    expect((await jsonAus(erlaubt))['mitOrt'], isTrue);
    expect(await bytesAus(await datei('original')), roh);
    final mit = await jsonAus(
      await frag('GET', '/api/v1/geteilt/$id', token: maxToken),
    );
    expect(((mit['aufnahmen']! as List).single as Map)['ort'], isNotNull);
    expect(mitGps(await bytesAus(await datei('ansicht'))), isTrue);

    // Nur das Recht zum Beitragen geändert (wie ältere Apps): der Ort bleibt.
    await teile(max.id, beitragen: true);
    expect((await mitMir(maxToken)).single['mitOrt'], isTrue);
    // Wieder ohne.
    await frag(
      'PUT',
      '/api/v1/alben/urlaub/teilungen/${max.id}',
      token: erikaToken,
      kopf: {'content-type': 'application/json'},
      inhalt: jsonEncode({'beitragen': true, 'mitOrt': false}),
    );
    expect(mitGps(await bytesAus(await datei('original'))), isFalse);
  });

  test('WEB-167 ganze Bibliothek: ohne Erlaubnis kein Ort – auch in der '
      'eigenen Zeitleiste des Partners; die Einschränkung bleibt', () async {
    final (ort, roh) = await urlaubMitOrt();
    Future<Response> partner(
      String methode,
      String pfad,
      String token, {
      Object? inhalt,
    }) => frag(
      methode,
      '/api/v1/partner$pfad',
      token: token,
      kopf: {'content-type': 'application/json'},
      inhalt: inhalt == null ? null : jsonEncode(inhalt),
    );
    expect((await partner('PUT', '/${max.id}', erikaToken)).statusCode, 204);
    final meine =
        ((await jsonAus(await partner('GET', '', erikaToken)))['meine']!
                as List)
            .cast<Map>()
            .single;
    expect(meine['mitOrt'], isFalse, reason: 'Vorgabe');
    final mitMirP =
        ((await jsonAus(await partner('GET', '', maxToken)))['mitMir']! as List)
            .cast<Map>()
            .single;
    expect(mitMirP['mitOrt'], isFalse);

    final zeilen = await jsonAus(
      await partner('GET', '/von/${erika.id}/aufnahmen', maxToken),
    );
    final zeile = (zeilen['aufnahmen']! as List).single as Map;
    expect(zeile.containsKey('ort'), isFalse);
    expect(zeile['ohneOrt'], isTrue);
    final original = await partner(
      'GET',
      '/von/${erika.id}/aufnahmen/$ort/original',
      maxToken,
    );
    final bytes = await bytesAus(original);
    expect(mitGps(bytes), isFalse);
    expect(bytes, isNot(roh));
    expect(
      mitGps(
        await bytesAus(
          await partner(
            'GET',
            '/von/${erika.id}/aufnahmen/$ort/ansicht',
            maxToken,
          ),
        ),
      ),
      isFalse,
    );

    // In Max' eigener Zeitleiste, auch mit den Angaben der Liste.
    await partner(
      'PUT',
      '/von/${erika.id}/zeitleiste',
      maxToken,
      inhalt: {'an': true},
    );
    final zeitleiste = await jsonAus(
      await frag('GET', '/api/v1/aufnahmen?voll=1', token: maxToken),
    );
    final fremd = (zeitleiste['aufnahmen']! as List).cast<Map>().singleWhere(
      (z) => z['id'] == ort,
    );
    expect(fremd.containsKey('ort'), isFalse);
    expect(fremd.containsKey('stadt'), isFalse);
    expect(fremd['ohneOrt'], isTrue);

    // Erika schränkt ein und erlaubt dann den Ort: Die Einschränkung bleibt.
    expect(
      (await partner(
        'PUT',
        '/${max.id}',
        erikaToken,
        inhalt: {'ab': '2000-01-01'},
      )).statusCode,
      204,
    );
    expect(
      (await partner(
        'PUT',
        '/${max.id}',
        erikaToken,
        inhalt: {'mitOrt': true},
      )).statusCode,
      204,
    );
    final danach =
        ((await jsonAus(await partner('GET', '', erikaToken)))['meine']!
                as List)
            .cast<Map>()
            .single;
    expect(danach['mitOrt'], isTrue);
    expect(danach['ab'], '2000-01-01');
    expect(
      await bytesAus(
        await partner(
          'GET',
          '/von/${erika.id}/aufnahmen/$ort/original',
          maxToken,
        ),
      ),
      roh,
    );
    expect(
      (await partner(
        'PUT',
        '/${max.id}',
        erikaToken,
        inhalt: {'mitOrt': 'ja'},
      )).statusCode,
      400,
    );
  });

  test('ein Video ohne Erlaubnis: nur die Fassung ohne Metadaten', () async {
    await urlaubMitOrt();
    final b = (await bibliotheken.fuer(erika.id)).bibliothek;
    const relativ = 'originals/film.mov';
    final film = b.pfade.absolute(relativ);
    await film.parent.create(recursive: true);
    await film.writeAsBytes(List.filled(64, 7));
    await b.db
        .into(b.db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'film',
            originalFileName: 'Film am Hafen.mov',
            relativePath: relativ,
            checksum: 'c_film',
            type: 'VIDEO',
            fileCreatedAt: DateTime(2025, 9, 11),
            importedAt: DateTime(2025, 9, 11),
          ),
        );
    await befehl(erikaToken, 'albumFuellen', {
      'albumId': 'urlaub',
      'ids': ['film'],
    });
    await teile(max.id);
    final id = (await mitMir(maxToken)).single['id']! as String;
    Future<Response> datei(String art) =>
        frag('GET', '/api/v1/geteilt/$id/aufnahmen/film/$art', token: maxToken);

    // Die Fassung fehlt noch: Abspielen sagt 404 (der Spieler holt dann
    // `abspielbar`), Herunterladen wartet auf sie.
    expect((await datei('wiedergabe')).statusCode, 404);
    expect((await datei('original')).statusCode, isIn([202, 422]));

    // Die Fassung liegt da: Sie kommt, das Original nie.
    final fassung = Videofassungen.ziel(
      Directory('${b.ordner.path}/abspielbar'),
      'film',
    );
    await fassung.parent.create(recursive: true);
    await fassung.writeAsBytes(List.filled(32, 9));
    await fassung.setLastModified(DateTime.now().add(const Duration(hours: 1)));
    final laden = await datei('original');
    expect(laden.statusCode, 200);
    expect(
      laden.headers['content-disposition'],
      contains('Film%20am%20Hafen.mp4'),
    );
    expect(await bytesAus(laden), List.filled(32, 9));
    expect(await bytesAus(await datei('wiedergabe')), List.filled(32, 9));

    // Mit Erlaubnis das Original.
    await frag(
      'PUT',
      '/api/v1/alben/urlaub/teilungen/${max.id}',
      token: erikaToken,
      kopf: {'content-type': 'application/json'},
      inhalt: jsonEncode({'beitragen': false, 'mitOrt': true}),
    );
    expect(await bytesAus(await datei('original')), List.filled(64, 7));
    expect(await bytesAus(await datei('wiedergabe')), List.filled(64, 7));
  });

  test('Serverdatenbank 13: bestehende Teilungen bleiben ohne Ort', () async {
    final ordner = await Directory.systemTemp.createTemp('pv_teilung_ort_');
    final datei = File('${ordner.path}/server.sqlite');
    var bank = Serverdatenbank.oeffne(datei);
    try {
      bank.db.execute(
        "INSERT INTO konten (id, name, angelegt) VALUES ('a', 'eins', 1), "
        "('b', 'zwei', 1)",
      );
      bank.db.execute('ALTER TABLE albumteilungen DROP COLUMN mit_ort');
      bank.db.execute('ALTER TABLE partnerfreigaben DROP COLUMN mit_ort');
      bank.db.execute(
        'INSERT INTO albumteilungen (id, besitzer, album, empfaenger, '
        "beitragen, angelegt) VALUES ('t', 'a', 'x', 'b', 1, 1)",
      );
      bank.db.execute(
        'INSERT INTO partnerfreigaben (besitzer, partner, angelegt) '
        "VALUES ('a', 'b', 1)",
      );
      bank.db.execute('PRAGMA user_version = 13');
      bank.schliesse();
      bank = Serverdatenbank.oeffne(datei);
      final dienst = Albumteilungen(bank);
      expect(dienst.vonAlbum('a', 'x').single.mitOrt, isFalse);
      expect(dienst.vonAlbum('a', 'x').single.beitragen, isTrue);
      expect(dienst.partnerfreigabe('a', 'b')!.mitOrt, isFalse);
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
