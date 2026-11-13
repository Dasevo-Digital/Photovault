import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:photo_vault_server/src/anmeldung_api.dart' show webCookie;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Kartenkacheln über den eigenen Server (#180): Der Server holt sie mit
/// eigener Kennung beim Anbieter, hält sie vor und liefert sie an
/// angemeldete Geräte – ein Besucher der Weboberfläche oder ein Telefon
/// verrät OpenStreetMap so weder seine IP-Adresse noch, welche Gegend es
/// ansieht. Der Anbieter ist hier ein Ersatz; echte Kachelserver fragt der
/// Test nie.
void main() {
  late Directory ordner;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late String token;
  late DateTime jetzt;
  late List<http.BaseRequest> beimAnbieter;

  /// Was der Ersatz-Anbieter auf die nächste Frage antwortet.
  late Future<http.Response> Function(http.Request) anbieter;

  final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]);
  http.Response kachel({
    String cacheControl = 'max-age=3600',
    List<int>? bytes,
    Map<String, String> stand = const {},
  }) => http.Response.bytes(
    bytes ?? png,
    200,
    headers: {
      'content-type': 'image/png',
      'cache-control': cacheControl,
      ...stand,
    },
  );

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_kartenkacheln_');
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
    final erika = await konten.legeAn('erika', 'ein langes passwort');
    token = konten.meldeAn(erika.id, 'Telefon', 'x').token;
    jetzt = DateTime.now();
    beimAnbieter = [];
    anbieter = (_) async => kachel();
  });

  tearDown(() async {
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  Kartenkacheln karte({int grenze = 1 << 30, int gleichzeitig = 4}) =>
      Kartenkacheln(
        Directory('${ordner.path}/kartenkacheln'),
        netz: MockClient((r) {
          beimAnbieter.add(r);
          return anbieter(r);
        }),
        grenze: grenze,
        gleichzeitig: gleichzeitig,
        frist: const Duration(milliseconds: 200),
        uhr: () => jetzt,
      );

  Handler api(Kartenkacheln? k) =>
      baueApi(konten: konten, bibliotheken: bibliotheken, karte: k);

  Future<Response> hole(
    Handler h,
    String pfad, {
    bool angemeldet = true,
    Map<String, String> kopf = const {},
  }) async => h(
    Request(
      'GET',
      Uri.parse('http://server/api/v1/karte/$pfad'),
      headers: {if (angemeldet) 'authorization': 'Bearer $token', ...kopf},
    ),
  );

  int maxAge(Response r) => int.parse(
    RegExp(r'max-age=(\d+)').firstMatch(r.headers['cache-control']!)![1]!,
  );

  Future<List<int>> inhalt(Response r) => r.read().expand((b) => b).toList();

  test('der Server meldet die Fähigkeit, ein älterer Aufbau nicht', () async {
    Future<Object?> stufe(Handler h) async {
      final r = await h(
        Request('GET', Uri.parse('http://server/api/v1/zustand')),
      );
      return ((jsonDecode(await r.readAsString()) as Map)['funktionen']
          as Map)['karte'];
    }

    expect(await stufe(api(karte())), 1);
    expect(await stufe(api(null)), 0);
    // Ohne Kacheln über den Server (PV_KARTEN=aus) geht der Browser zum
    // Anbieter (#382) – nur zu den bekannten, kein offener Umleiter.
    final weiter = await hole(api(null), 'osm/3/4/2.png');
    expect(weiter.statusCode, 302);
    expect(
      weiter.headers['location'],
      'https://tile.openstreetmap.org/3/4/2.png',
    );
    // OSM sperrt Browser ohne Referer (#179): Die Weiterleitung darf den
    // Ursprung nicht wegnehmen. Und sie wird nicht vorgehalten.
    expect(
      weiter.headers['referrer-policy'],
      'strict-origin-when-cross-origin',
    );
    expect(weiter.headers['cache-control'], 'no-store');
    expect(
      (await hole(api(null), 'topo/5/1/2.png')).headers['location'],
      'https://tile.opentopomap.org/5/1/2.png',
    );
    expect((await hole(api(null), 'fremd/3/4/2.png')).statusCode, 404);
    expect(
      (await hole(api(null), 'osm/3/4/2.png', angemeldet: false)).statusCode,
      401,
    );
  });

  test('nur angemeldet – mit Token oder dem Cookie des Browsers', () async {
    final h = api(karte());
    expect((await hole(h, 'osm/3/4/2.png', angemeldet: false)).statusCode, 401);
    expect(beimAnbieter, isEmpty, reason: 'ohne Anmeldung kein Abruf');

    final browser = await hole(
      h,
      'osm/3/4/2.png',
      angemeldet: false,
      kopf: {'cookie': '$webCookie=$token'},
    );
    expect(browser.statusCode, 200);
  });

  test('beim ersten Mal vom Anbieter, mit eigener Kennung, danach von der '
      'Platte', () async {
    final h = api(karte());
    final erste = await hole(h, 'osm/3/4/2.png');
    expect(erste.statusCode, 200);
    expect(erste.headers['content-type'], 'image/png');
    expect(await erste.read().expand((b) => b).toList(), png);
    expect(beimAnbieter, hasLength(1));
    final frage = beimAnbieter.single;
    expect(frage.url.toString(), 'https://tile.openstreetmap.org/3/4/2.png');
    expect(frage.headers['user-agent'], startsWith('PhotoVault-Server/'));
    // Nichts vom Gerät geht mit: weder Token noch Cookie.
    expect(frage.headers.keys, isNot(contains('authorization')));
    expect(frage.headers.keys, isNot(contains('cookie')));
    expect(frage.headers.keys, isNot(contains('referer')));

    // Der Anbieter sagte eine Stunde; vorgehalten wird mindestens eine
    // Woche, und so lange darf auch das Gerät die Kachel behalten.
    expect(erste.headers['cache-control'], startsWith('private, '));
    expect(maxAge(erste), closeTo(const Duration(days: 7).inSeconds, 5));
    final etikett = erste.headers['etag']!;

    jetzt = jetzt.add(const Duration(days: 6));
    final zweite = await hole(h, 'osm/3/4/2.png');
    expect(zweite.statusCode, 200);
    expect(beimAnbieter, hasLength(1), reason: 'nach sechs Tagen noch frisch');
    expect(maxAge(zweite), closeTo(const Duration(days: 1).inSeconds, 5));

    final unveraendert = await hole(
      h,
      'osm/3/4/2.png',
      kopf: {'if-none-match': etikett},
    );
    expect(unveraendert.statusCode, 304);
    expect(beimAnbieter, hasLength(1));

    // OpenTopoMap hat seinen eigenen Platz.
    expect((await hole(h, 'topo/3/4/2.png')).statusCode, 200);
    expect(
      beimAnbieter.last.url.toString(),
      'https://tile.opentopomap.org/3/4/2.png',
    );
  });

  test('eine längere Haltbarkeit des Anbieters gilt', () async {
    anbieter = (_) async => kachel(cacheControl: 'public, max-age=2592000');
    final h = api(karte());
    final r = await hole(h, 'osm/5/16/10.png');
    expect(maxAge(r), closeTo(const Duration(days: 30).inSeconds, 5));
    jetzt = jetzt.add(const Duration(days: 20));
    await hole(h, 'osm/5/16/10.png');
    expect(beimAnbieter, hasLength(1));
  });

  test('abgelaufen wird nur nachgefragt: Bei 304 bleiben die Bytes, und die '
      'Frist beginnt von vorn (#379)', () async {
    const zeit = 'Tue, 03 Nov 2026 10:00:00 GMT';
    anbieter = (_) async =>
        kachel(stand: {'etag': '"v1"', 'last-modified': zeit});
    final h = api(karte());
    expect((await hole(h, 'osm/3/4/2.png')).statusCode, 200);
    final erste = beimAnbieter.single.headers.keys;
    expect(erste, isNot(contains('if-none-match')), reason: 'noch keine Kopie');
    expect(erste, isNot(contains('if-modified-since')));

    // Nach Ablauf fragt der Server, ob sich die Kachel geändert hat.
    jetzt = jetzt.add(const Duration(days: 8));
    anbieter = (_) async =>
        http.Response('', 304, headers: {'cache-control': 'max-age=1209600'});
    final bestaetigt = await hole(h, 'osm/3/4/2.png');
    expect(bestaetigt.statusCode, 200);
    expect(await inhalt(bestaetigt), png, reason: 'die Bytes bleiben');
    expect(maxAge(bestaetigt), closeTo(const Duration(days: 14).inSeconds, 5));
    expect(beimAnbieter, hasLength(2));
    expect(beimAnbieter.last.headers['if-none-match'], '"v1"');
    expect(beimAnbieter.last.headers['if-modified-since'], zeit);

    // So lange wieder von der Platte.
    jetzt = jetzt.add(const Duration(days: 13));
    expect((await hole(h, 'osm/3/4/2.png')).statusCode, 200);
    expect(beimAnbieter, hasLength(2));

    // Ein 304 ohne Angaben: mindestens eine Woche, wie bei jeder Kachel.
    jetzt = jetzt.add(const Duration(days: 2));
    anbieter = (_) async => http.Response('', 304);
    final ohne = await hole(h, 'osm/3/4/2.png');
    expect(maxAge(ohne), closeTo(const Duration(days: 7).inSeconds, 5));
    expect(beimAnbieter, hasLength(3));

    // Hat sie sich geändert, kommt sie ganz, mit ihrem neuen Stand.
    jetzt = jetzt.add(const Duration(days: 8));
    final neu = [...png, 9];
    anbieter = (_) async => kachel(bytes: neu, stand: {'etag': '"v2"'});
    expect(await inhalt(await hole(h, 'osm/3/4/2.png')), neu);
    jetzt = jetzt.add(const Duration(days: 8));
    anbieter = (_) async => http.Response('', 304);
    expect(await inhalt(await hole(h, 'osm/3/4/2.png')), neu);
    expect(beimAnbieter.last.headers['if-none-match'], '"v2"');
    expect(
      beimAnbieter.last.headers.keys,
      isNot(contains('if-modified-since')),
      reason: 'der neue Stand nennt keine Zeit',
    );

    // Ohne Stand ist ein 304 keine Antwort: Wer ohne Bedingung fragt, muss
    // die Kachel bekommen.
    anbieter = (_) async => http.Response('', 304);
    expect((await hole(h, 'osm/3/4/3.png')).statusCode, 502);
  });

  test('kein offener Vermittler: fremde Stile, Stufen und Koordinaten sind '
      '404, ohne den Anbieter zu fragen', () async {
    final h = api(karte());
    for (final pfad in [
      'carto/3/4/2.png',
      'osm/20/0/0.png', // OSM liefert bis 19
      'topo/18/0/0.png', // OpenTopoMap bis 17
      'osm/3/8/0.png', // auf Stufe 3 gibt es x = 0 … 7
      'osm/3/0/8.png',
      'osm/3/4/2.jpg',
      'osm/3/4/x.png',
      'osm/3/4/2.png/mehr',
      'osm/123/0/0.png',
      'osm/3/-1/0.png',
    ]) {
      expect((await hole(h, pfad)).statusCode, 404, reason: pfad);
    }
    expect(beimAnbieter, isEmpty);
    expect((await hole(h, 'osm/19/524287/524287.png')).statusCode, 200);
    expect((await hole(h, 'topo/17/0/131071.png')).statusCode, 200);
  });

  test('ist der Anbieter weg, gilt die alte Kachel – und nach drei '
      'Fehlern in Folge wird er eine Weile in Ruhe gelassen', () async {
    final h = api(karte());
    expect((await hole(h, 'osm/3/4/2.png')).statusCode, 200);
    jetzt = jetzt.add(const Duration(days: 8));
    anbieter = (r) async => throw http.ClientException('weg', r.url);

    final alt = await hole(h, 'osm/3/4/2.png');
    expect(alt.statusCode, 200);
    expect(await alt.read().expand((b) => b).toList(), png);
    expect(maxAge(alt), 0, reason: 'beim nächsten Mal wieder fragen');
    expect(beimAnbieter, hasLength(2));

    // Ohne Kopie: ein klarer Fehler. Ein einzelner Fehler legt den Stil
    // aber nicht lahm (#180): Die nächsten Kacheln werden noch gefragt.
    final ohne = await hole(h, 'osm/3/4/3.png');
    expect(ohne.statusCode, 502);
    expect(ohne.headers['content-type'], startsWith('application/json'));
    expect(beimAnbieter, hasLength(3));
    expect((await hole(h, 'osm/3/4/4.png')).statusCode, 502);
    expect(beimAnbieter, hasLength(4));
    // Der dritte Fehler in Folge: Ruhe, kein Abruf mehr.
    expect((await hole(h, 'osm/3/4/5.png')).statusCode, 502);
    expect(beimAnbieter, hasLength(4));

    // Nach der Ruhe wieder, und eine neue Kachel ersetzt die alte.
    jetzt = jetzt.add(const Duration(minutes: 1));
    final neu = Uint8List.fromList([...png, 9]);
    anbieter = (_) async => kachel(bytes: neu);
    final frisch = await hole(h, 'osm/3/4/2.png');
    expect(await frisch.read().expand((b) => b).toList(), neu);
    expect(maxAge(frisch), greaterThan(0));
    expect(beimAnbieter, hasLength(5));
  });

  test('429 vom Anbieter heisst gleich: in Ruhe lassen', () async {
    final h = api(karte());
    anbieter = (_) async => http.Response('zu viele', 429);
    expect((await hole(h, 'osm/5/1/1.png')).statusCode, 502);
    expect((await hole(h, 'osm/5/1/2.png')).statusCode, 502);
    expect(beimAnbieter, hasLength(1));
    // Der andere Stil bleibt unberührt.
    anbieter = (_) async => kachel();
    expect((await hole(h, 'topo/5/1/2.png')).statusCode, 200);
  });

  test('Fehlerseiten, 404 und Schweigen des Anbieters', () async {
    final h = api(karte());
    anbieter = (_) async => http.Response('nicht gerendert', 404);
    expect((await hole(h, 'topo/12/1/1.png')).statusCode, 404);
    // 404 ist eine Antwort, keine Störung: die nächste Kachel wird gefragt.
    anbieter = (_) async => http.Response(
      '<html>Fehler</html>',
      200,
      headers: {'content-type': 'text/html'},
    );
    expect((await hole(h, 'topo/12/1/2.png')).statusCode, 502);
    expect(beimAnbieter, hasLength(2));

    jetzt = jetzt.add(const Duration(minutes: 1));
    anbieter = (_) => Completer<http.Response>().future;
    expect((await hole(h, 'osm/12/1/3.png')).statusCode, 502);
    expect(
      Directory('${ordner.path}/kartenkacheln').existsSync()
          ? Directory('${ordner.path}/kartenkacheln').listSync()
          : const <FileSystemEntity>[],
      isEmpty,
      reason: 'nichts davon landet auf der Platte',
    );
  });

  test(
    'höchstens wenige Abrufe gleichzeitig, dieselbe Kachel nur einmal',
    () async {
      var gleichzeitig = 0, hoechstens = 0;
      final h = api(karte(gleichzeitig: 2));
      anbieter = (_) async {
        gleichzeitig++;
        if (gleichzeitig > hoechstens) hoechstens = gleichzeitig;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        gleichzeitig--;
        return kachel();
      };
      final antworten = await Future.wait([
        for (var x = 0; x < 8; x++) hole(h, 'osm/4/$x/5.png'),
        for (var i = 0; i < 3; i++) hole(h, 'osm/4/9/9.png'),
      ]);
      expect(antworten.map((r) => r.statusCode), everyElement(200));
      expect(hoechstens, 2);
      expect(beimAnbieter, hasLength(9), reason: '8 + einmal 4/9/9');
    },
  );

  test('der Speicher bleibt unter seiner Grenze', () async {
    final gross = List<int>.filled(1000, 7);
    anbieter = (_) async => kachel(bytes: gross, stand: {'etag': '"e"'});
    final k = karte(grenze: 3500);
    final h = api(k);
    for (var x = 0; x < 10; x++) {
      jetzt = jetzt.add(const Duration(seconds: 1));
      expect((await hole(h, 'osm/4/$x/0.png')).statusCode, 200);
    }
    await k.aufraeumenFertig();
    final dateien = Directory(
      '${ordner.path}/kartenkacheln',
    ).listSync().whereType<File>().toList();
    final kacheln = dateien.where((f) => f.path.endsWith('.png'));
    final summe = kacheln.fold<int>(0, (s, f) => s + f.lengthSync());
    expect(summe, lessThanOrEqualTo(3500));
    // Die zuletzt geholte bleibt immer.
    final namen = dateien.map((f) => f.uri.pathSegments.last).toSet();
    expect(namen, contains('osm-4-9-0.png'));
    // Der Stand einer Kachel geht mit ihr, und nur mit ihr (#379).
    expect(namen, hasLength(kacheln.length * 2));
    for (final kachel in kacheln) {
      expect(namen, contains('${kachel.uri.pathSegments.last}.stand'));
    }
  });
}
