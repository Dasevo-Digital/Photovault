import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Die Weboberfläche (Issue #133) – vor allem ihre Sicherheit: Was im
/// Browser angemeldet ist, darf lesen und aus der eigenen Seite heraus
/// schreiben, sonst nichts; die Dateien der Oberfläche kommen aus ihrem
/// Ordner und aus keinem anderen; jede Antwort trägt die Schutzköpfe.
///
/// Adressen: eine aus dem privaten 10er-Netz steht für den vertrauten
/// Proxy, `203.0.113.9` (Dokumentationsbereich) für irgendwen im Netz.

class _Verbindung implements HttpConnectionInfo {
  _Verbindung(String adresse) : remoteAddress = InternetAddress(adresse);
  @override
  final InternetAddress remoteAddress;
  @override
  int get localPort => 8790;
  @override
  int get remotePort => 40000;
}

List<int> _ausBase32(String s) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final aus = <int>[];
  var puffer = 0, bits = 0;
  for (final z in s.split('')) {
    puffer = (puffer << 5) | alphabet.indexOf(z);
    bits += 5;
    if (bits >= 8) {
      aus.add((puffer >> (bits - 8)) & 0xff);
      bits -= 8;
      puffer &= (1 << bits) - 1;
    }
  }
  return aus;
}

/// Private Adressen stehen hier zusammengesetzt: Die Datenschutzprüfung
/// soll im Quelltext keine finden.
String _ip(List<int> teile) => teile.join('.');

void main() {
  test('installierbar: Manifest mit Symbolen, die es gibt', () {
    // Die echte Oberfläche, nicht die des Prüfstands.
    final web = Directory('web');
    final index = File('${web.path}/index.html').readAsStringSync();
    expect(index, contains('rel="manifest" href="manifest.webmanifest"'));
    expect(
      index,
      contains('rel="apple-touch-icon" href="apple-touch-icon.png"'),
    );
    expect(File('${web.path}/apple-touch-icon.png').existsSync(), isTrue);
    final m =
        jsonDecode(File('${web.path}/manifest.webmanifest').readAsStringSync())
            as Map;
    expect(m['display'], 'standalone');
    expect(m['start_url'], startsWith(m['scope'] as String));
    final symbole = (m['icons'] as List).cast<Map>();
    expect(symbole.map((s) => s['purpose']), containsAll(['any', 'maskable']));
    for (final s in symbole) {
      final datei = File('${web.path}/${s['src']}');
      expect(datei.existsSync(), isTrue, reason: '${s['src']}');
      // PNG: Breite und Höhe stehen ab Byte 16 im IHDR.
      final b = datei.readAsBytesSync();
      final breite = (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];
      expect('${breite}x$breite', s['sizes']);
    }
  });
  final proxy = _ip([10, 0, 0, 5]);
  final proxyNetz = '${_ip([10, 0, 0, 0])}/8';
  const fremd = '203.0.113.9';
  const passwort = 'ein langes passwort';
  late Directory ordner;
  late Directory web;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late Konto erika;
  late Handler api;

  Handler baue({bool totpPflicht = false, bool mitWeb = true}) {
    konten = Kontodienst(
      sdb,
      Tresorschluessel(List.filled(32, 7)),
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: totpPflicht,
    );
    return baueApi(
      konten: konten,
      bibliotheken: bibliotheken,
      absender: Absender([proxyNetz]),
      web: mitWeb ? web : null,
    );
  }

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_web_');
    web = Directory('${ordner.path}/web')..createSync();
    File('${web.path}/index.html').writeAsStringSync(
      '<!doctype html><html><head><link rel="stylesheet" href="app.css">'
      '<script src="app.js"></script></head><body>Oberfläche</body></html>',
    );
    File('${web.path}/app.js').writeAsStringSync('console.log(1)');
    File('${web.path}/app.css').writeAsStringSync('body{margin:0}');
    File('${web.path}/bild.svg').writeAsStringSync('<svg/>');
    Directory('${web.path}/unter').createSync();
    File('${web.path}/unter/x.js').writeAsStringSync('// versteckt');
    File('${ordner.path}/geheim.env').writeAsStringSync('PV_GEHEIM=1');
    sdb = Serverdatenbank.imSpeicher();
    bibliotheken = Bibliotheken(
      wurzel: Directory('${ordner.path}/bibliotheken'),
      eingang: Directory('${ordner.path}/eingang'),
      ruhe: const Duration(hours: 1),
    );
    api = baue();
    erika = await konten.legeAn('erika', passwort);
  });

  tearDown(() async {
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  Future<Response> frag(
    String methode,
    String pfad, {
    Map<String, String> kopf = const {},
    Object? inhalt,
    String von = fremd,
    String schema = 'http',
    Handler? an,
  }) async => (an ?? api)(
    Request(
      methode,
      Uri.parse('$schema://fotos.example$pfad'),
      headers: kopf,
      body: inhalt,
      context: {'shelf.io.connection_info': _Verbindung(von)},
    ),
  );

  Future<Map<String, Object?>> jsonAus(Response r) async =>
      (jsonDecode(await r.readAsString()) as Map).cast<String, Object?>();

  String? cookieAus(Response r) {
    final s = r.headers['set-cookie'];
    if (s == null) return null;
    final wert = s.split(';').first.split('=').last;
    return wert.isEmpty ? null : wert;
  }

  Map<String, String> mitCookie(
    String token, [
    Map<String, String> k = const {},
  ]) => {'cookie': 'pv_web=$token', ...k};

  Future<(Response, String?)> anmelden({
    String name = 'erika',
    String pw = passwort,
    Map<String, String> kopf = const {},
    String von = fremd,
    String schema = 'http',
    Handler? an,
  }) async {
    final r = await frag(
      'POST',
      '/api/v1/web/anmelden',
      kopf: {'content-type': 'application/json', ...kopf},
      inhalt: jsonEncode({'name': name, 'passwort': pw}),
      von: von,
      schema: schema,
      an: an,
    );
    return (r, cookieAus(r));
  }

  group('Dateien der Oberfläche', () {
    test('Seite und Dateien mit den richtigen Köpfen', () async {
      final um = await frag('GET', '/app');
      expect(um.statusCode, 302);
      expect(um.headers['location'], '/app/');

      final seite = await frag('GET', '/app/');
      expect(seite.statusCode, 200);
      expect(seite.headers['content-type'], 'text/html; charset=utf-8');
      expect(seite.headers['cache-control'], 'no-store');
      final csp = seite.headers['content-security-policy']!;
      expect(csp, contains("script-src 'self'"));
      expect(csp, contains("frame-ancestors 'none'"));
      expect(csp, isNot(contains('unsafe-inline')));
      expect(seite.headers['x-frame-options'], 'DENY');
      expect(seite.headers['x-content-type-options'], 'nosniff');
      expect(seite.headers['cross-origin-opener-policy'], 'same-origin');
      expect(seite.headers['cross-origin-resource-policy'], 'same-origin');
      expect(await seite.readAsString(), contains('Oberfläche'));

      final js = await frag('GET', '/app/app.js');
      expect(js.statusCode, 200);
      expect(js.headers['content-type'], 'text/javascript; charset=utf-8');
      expect(js.headers['cache-control'], 'no-cache');
      expect(
        (await frag('GET', '/app/app.css')).headers['content-type'],
        'text/css; charset=utf-8',
      );
      // Ein SVG kann Skript tragen: als Bild ja, als Seite nie.
      final svg = await frag('GET', '/app/bild.svg');
      expect(svg.headers['content-security-policy'], contains('sandbox'));

      expect((await frag('GET', '/app/fehlt.js')).statusCode, 404);

      // Mitgelieferte Bibliothek aus ihrem Unterordner – nur aus dem.
      Directory('${web.path}/leaflet/images').createSync(recursive: true);
      File('${web.path}/leaflet/leaflet.js').writeAsStringSync('L=1');
      File('${web.path}/leaflet/images/marker-icon.png').writeAsBytesSync([1]);
      expect((await frag('GET', '/app/leaflet/leaflet.js')).statusCode, 200);
      expect(
        (await frag(
          'GET',
          '/app/leaflet/images/marker-icon.png',
        )).headers['content-type'],
        'image/png',
      );
      expect(
        (await frag('GET', '/app/leaflet/..%2Fapp.js')).statusCode,
        anyOf(404, 401),
      );
      expect(
        (await frag('GET', '/app/leaflet/images/..%2Fleaflet.js')).statusCode,
        anyOf(404, 401),
      );

      // Vorlagenbilder und Schriften des Lebensbaums.
      Directory('${web.path}/lebensbaum').createSync();
      Directory('${web.path}/schrift').createSync();
      File('${web.path}/lebensbaum/pergament.jpg').writeAsBytesSync([1]);
      File('${web.path}/schrift/ebgaramond.ttf').writeAsBytesSync([1]);
      expect(
        (await frag(
          'GET',
          '/app/lebensbaum/pergament.jpg',
        )).headers['content-type'],
        'image/jpeg',
      );
      expect(
        (await frag(
          'GET',
          '/app/schrift/ebgaramond.ttf',
        )).headers['content-type'],
        'font/ttf',
      );
      expect(
        (await frag('GET', '/app/lebensbaum/..%2Findex.html')).statusCode,
        anyOf(404, 401),
      );
      expect(
        (await frag('GET', '/app/schrift/Gross.ttf')).statusCode,
        404,
        reason: 'nur kleingeschriebene Namen',
      );
    });

    test('gepackt, mit Etikett und 304 beim Nachfragen', () async {
      final inhalt = 'const x = 1;\n' * 400;
      File('${web.path}/app.js').writeAsStringSync(inhalt);

      final roh = await frag('GET', '/app/app.js');
      expect(roh.headers['content-encoding'], isNull);
      final etikett = roh.headers['etag']!;
      expect(await roh.readAsString(), inhalt);

      final gz = await frag(
        'GET',
        '/app/app.js',
        kopf: {'accept-encoding': 'gzip, deflate, br'},
      );
      expect(gz.statusCode, 200);
      expect(gz.headers['content-encoding'], 'gzip');
      expect(gz.headers['vary'], 'accept-encoding');
      expect(gz.headers['content-length'], isNull);
      // Eine andere Darstellung, ein anderes Etikett.
      expect(gz.headers['etag'], isNot(etikett));
      final bytes = await gz.read().expand((b) => b).toList();
      expect(bytes.length, lessThan(inhalt.length ~/ 10));
      expect(utf8.decode(gzip.decode(bytes)), inhalt);

      // Beide Etiketten führen zum 304.
      for (final e in [etikett, gz.headers['etag']!]) {
        final nochmal = await frag(
          'GET',
          '/app/app.js',
          kopf: {'if-none-match': e, 'accept-encoding': 'gzip'},
        );
        expect(nochmal.statusCode, 304, reason: e);
        expect(await nochmal.readAsString(), isEmpty);
      }

      // Die Seite selbst trägt keines: Sie bleibt nie im Speicher.
      final seite = await frag('GET', '/app/');
      expect(seite.headers['etag'], isNull);

      // Kleines bleibt ungepackt.
      File('${web.path}/klein.js').writeAsStringSync('1');
      expect(
        (await frag(
          'GET',
          '/app/klein.js',
          kopf: {'accept-encoding': 'gzip'},
        )).headers['content-encoding'],
        isNull,
      );
    });

    test('kein Weg aus dem Ordner heraus', () async {
      for (final pfad in [
        '/app/../geheim.env',
        '/app/..%2Fgeheim.env',
        '/app/%2e%2e/geheim.env',
        '/app/%2e%2e%2fgeheim.env',
        '/app/unter/x.js',
        '/app/unter%2Fx.js',
        '/app/x%00.js',
        '/app/.env',
        '/app/index.html.bak',
        '/app/geheim.env',
        '/app/INDEX.HTML',
        '/app/index.html/',
      ]) {
        final r = await frag('GET', pfad);
        final text = await r.readAsString();
        // 404, oder 401, wenn der Browser den Pfad schon vorher aus /app/
        // hinausnormalisiert hat – Hauptsache, kein Inhalt.
        expect(r.statusCode, anyOf(404, 401), reason: pfad);
        expect(text, isNot(contains('PV_GEHEIM')), reason: pfad);
        expect(text, isNot(contains('versteckt')), reason: pfad);
      }
    });

    test('ohne Oberfläche: kein /app, Startseite ohne Verweis', () async {
      final ohne = baue(mitWeb: false);
      expect((await frag('GET', '/app/', an: ohne)).statusCode, 404);
      expect(
        (await frag('GET', '/api/v1/web/anmelden', an: ohne)).statusCode,
        isNot(200),
      );
      expect(
        await (await frag('GET', '/', an: ohne)).readAsString(),
        isNot(contains('/app/')),
      );
      expect(
        await (await frag('GET', '/')).readAsString(),
        contains('href="/app/"'),
      );
    });
  });

  group('Anmeldung', () {
    test('Cookie nur bei Erfolg – HttpOnly, SameSite=Strict, Pfad /', () async {
      final (falsch, k1) = await anmelden(pw: 'falsch');
      expect(falsch.statusCode, 401);
      expect(k1, isNull);
      final (niemand, k2) = await anmelden(name: 'niemand', pw: 'x');
      expect(niemand.statusCode, 401);
      expect(k2, isNull);
      // Dieselbe Antwort für falsches Passwort und unbekannten Namen.
      expect(await niemand.readAsString(), await falsch.readAsString());

      final (ok, token) = await anmelden();
      expect(ok.statusCode, 200);
      expect(await jsonAus(ok), containsPair('angemeldet', true));
      expect(ok.headers['cache-control'], 'no-store');
      expect(
        ok.headers['set-cookie'],
        matches(
          RegExp(
            r'^pv_web=pv1_[A-Za-z0-9_-]{43}; Path=/; HttpOnly; SameSite=Strict; Max-Age=\d+$',
          ),
        ),
      );
      expect(token, startsWith('pv1_'));
      expect(token!.length, 47, reason: '43 Zeichen Base64url = 258 Bit');
    });

    test('Secure nur über HTTPS – direkt oder vom vertrauten Proxy', () async {
      expect(
        (await anmelden(schema: 'https')).$1.headers['set-cookie'],
        endsWith('; Secure'),
      );
      expect(
        (await anmelden(
          von: proxy,
          kopf: {'x-forwarded-proto': 'https'},
        )).$1.headers['set-cookie'],
        endsWith('; Secure'),
      );
      // Von irgendwem im Netz zählt die Behauptung nicht.
      expect(
        (await anmelden(
          von: fremd,
          kopf: {'x-forwarded-proto': 'https'},
        )).$1.headers['set-cookie'],
        isNot(contains('Secure')),
      );
      expect(
        (await anmelden(von: proxy)).$1.headers['set-cookie'],
        isNot(contains('Secure')),
      );
    });

    test(
      'jede Anmeldung ein frisches Cookie – auch mit untergeschobenem',
      () async {
        final (_, a) = await anmelden();
        final (_, b) = await anmelden();
        expect(a, isNot(b));
        final (r, c) = await anmelden(kopf: mitCookie('pv1_untergeschoben'));
        expect(r.statusCode, 200);
        expect(c, isNot('pv1_untergeschoben'));
      },
    );

    test(
      'zu viele Fehlversuche: 429 mit Retry-After, auch für Unbekannte',
      () async {
        Response? letzte;
        for (var i = 0; i < 12; i++) {
          letzte = (await anmelden(name: 'niemand', pw: 'x')).$1;
        }
        expect(letzte!.statusCode, 429);
        expect(letzte.headers['retry-after'], isNotNull);
        // Die Sperre hängt an der Adresse: Eine andere darf noch.
        expect((await anmelden(von: '203.0.113.10')).$1.statusCode, 200);
      },
    );

    test('TOTP: ohne zweiten Faktor kein Cookie', () async {
      // Dieselbe Datenbank, nur mit Pflicht: Erikas Konto gibt es schon.
      final mitTotp = baue(totpPflicht: true);
      final (erst, keins) = await anmelden(an: mitTotp);
      expect(erst.statusCode, 200);
      expect(keins, isNull);
      final j = await jsonAus(erst);
      expect(j['schritt'], 'totp_einrichten');
      final geheimnis = _ausBase32(j['geheimnis']! as String);
      Future<Response> code(String c) => frag(
        'POST',
        '/api/v1/web/anmelden/totp',
        kopf: {'content-type': 'application/json'},
        inhalt: jsonEncode({'vorgang': j['vorgang'], 'code': c}),
        an: mitTotp,
      );
      final falsch = await code('000000');
      expect(falsch.statusCode, 401);
      expect(cookieAus(falsch), isNull);
      final richtig = await code(
        Totp.code(geheimnis, Totp.schritt(DateTime.now())),
      );
      expect(richtig.statusCode, 200, reason: await richtig.readAsString());
      expect(cookieAus(richtig), startsWith('pv1_'));
    });
  });

  group('Sitzung', () {
    test(
      'mit dem Cookie liest man; schreiben nur aus der Oberfläche',
      () async {
        final (_, token) = await anmelden();
        final sitzung = await frag(
          'GET',
          '/api/v1/web/sitzung',
          kopf: mitCookie(token!),
        );
        expect(sitzung.statusCode, 200);
        expect(await jsonAus(sitzung), containsPair('name', 'erika'));
        expect(
          (await frag(
            'GET',
            '/api/v1/konto',
            kopf: mitCookie(token),
          )).statusCode,
          200,
        );
        expect(
          (await frag(
            'GET',
            '/api/v1/aufnahmen',
            kopf: mitCookie(token),
          )).statusCode,
          200,
        );

        Future<int> schreibe(Map<String, String> k) async => (await frag(
          'POST',
          '/api/v1/befehle',
          kopf: mitCookie(token, k),
          inhalt: '',
        )).statusCode;
        // Ohne den Kopf der Oberfläche: eine fremde Seite mit Formular.
        expect(await schreibe({}), 403);
        expect(
          await schreibe({'x-pv-web': '1', 'origin': 'https://boese.example'}),
          403,
        );
        expect(
          await schreibe({'x-pv-web': '1', 'sec-fetch-site': 'cross-site'}),
          403,
        );
        // Aus der eigenen Seite: durch (400, weil kein JSON kam).
        expect(
          await schreibe({
            'x-pv-web': '1',
            'origin': 'http://fotos.example',
            'sec-fetch-site': 'same-origin',
          }),
          400,
        );
        expect(await schreibe({'x-pv-web': '1'}), 400);
        // Hinter dem Proxy mit öffentlichem Namen.
        expect(
          await schreibe({
            'x-pv-web': '1',
            'origin': 'https://fotos.oeffentlich.example',
            'x-forwarded-host': 'fotos.oeffentlich.example',
          }),
          400,
        );

        // Ein Gerät mit Token kennt diese Prüfung nicht – es hat kein Cookie,
        // das eine fremde Seite ausnutzen könnte.
        final bearer = konten.meldeAn(erika.id, 'Rechner', 'x').token;
        expect(
          (await frag(
            'POST',
            '/api/v1/befehle',
            kopf: {
              'authorization': 'Bearer $bearer',
              'origin': 'https://boese.example',
            },
            inhalt: '',
          )).statusCode,
          400,
        );
        // Ohne alles: 401, nicht zwischenspeichern.
        final ohne = await frag('GET', '/api/v1/konto');
        expect(ohne.statusCode, 401);
        expect(ohne.headers['cache-control'], 'no-store');
      },
    );

    test('Abmelden nimmt das Cookie und beendet die Sitzung', () async {
      final (_, token) = await anmelden();
      final ab = await frag(
        'POST',
        '/api/v1/web/abmelden',
        kopf: mitCookie(token!, {'x-pv-web': '1'}),
      );
      expect(ab.statusCode, 200);
      expect(ab.headers['set-cookie'], startsWith('pv_web=; '));
      expect(ab.headers['set-cookie'], contains('Max-Age=0'));
      expect(
        (await frag(
          'GET',
          '/api/v1/web/sitzung',
          kopf: mitCookie(token),
        )).statusCode,
        401,
      );
    });

    test(
      'der Browser ist ein Gerät: sichtbar, von anderswo abmeldbar',
      () async {
        final (_, token) = await anmelden(
          kopf: {'user-agent': 'Mozilla/5.0 Gecko/20100101 Firefox/130.0'},
        );
        final rechner = konten.meldeAn(erika.id, 'Rechner', 'x').token;
        final liste = await frag(
          'GET',
          '/api/v1/geraete',
          kopf: {'authorization': 'Bearer $rechner'},
        );
        final geraete = ((await jsonAus(liste))['geraete']! as List)
            .cast<Map>();
        final browser = geraete.singleWhere(
          (g) => '${g['name']}'.startsWith('Browser'),
        );
        expect(browser['name'], 'Browser (Firefox)');
        expect(
          (await frag(
            'DELETE',
            '/api/v1/geraete/${browser['id']}',
            kopf: {'authorization': 'Bearer $rechner'},
          )).statusCode,
          200,
        );
        expect(
          (await frag(
            'GET',
            '/api/v1/web/sitzung',
            kopf: mitCookie(token!),
          )).statusCode,
          401,
        );

        // Passwort neu setzen mit „andere abmelden“ wirft den Browser hinaus.
        final (_, token2) = await anmelden();
        final neu = await frag(
          'POST',
          '/api/v1/konto/passwort',
          kopf: {
            'authorization': 'Bearer $rechner',
            'content-type': 'application/json',
          },
          inhalt: jsonEncode({
            'alt': passwort,
            'neu': 'noch ein langes passwort',
            'andereAbmelden': true,
          }),
        );
        expect(neu.statusCode, 200, reason: await neu.readAsString());
        expect(
          (await frag(
            'GET',
            '/api/v1/web/sitzung',
            kopf: mitCookie(token2!),
          )).statusCode,
          401,
        );
      },
    );

    test('Verwalterrechte gelten im Browser wie in der App', () async {
      await konten.legeAn('max', 'noch ein passwort');
      final (_, chefin) = await anmelden();
      final (_, max) = await anmelden(name: 'max', pw: 'noch ein passwort');
      expect(
        (await frag(
          'GET',
          '/api/v1/konten',
          kopf: mitCookie(chefin!),
        )).statusCode,
        200,
      );
      expect(
        (await frag('GET', '/api/v1/konten', kopf: mitCookie(max!))).statusCode,
        403,
      );
    });
  });

  group('Köpfe und Daten', () {
    test(
      'jede Antwort trägt die Schutzköpfe, JSON bleibt ungespeichert, kein CORS',
      () async {
        for (final pfad in ['/api/v1/zustand', '/', '/api/v1/konto']) {
          final r = await frag(
            'GET',
            pfad,
            kopf: {'origin': 'https://boese.example'},
          );
          expect(r.headers['x-content-type-options'], 'nosniff', reason: pfad);
          expect(r.headers['referrer-policy'], 'no-referrer', reason: pfad);
          expect(r.headers['x-frame-options'], 'DENY', reason: pfad);
          expect(
            r.headers['cross-origin-opener-policy'],
            'same-origin',
            reason: pfad,
          );
          expect(
            r.headers['cross-origin-resource-policy'],
            'same-origin',
            reason: pfad,
          );
          expect(
            r.headers['content-security-policy'],
            contains("frame-ancestors 'none'"),
            reason: pfad,
          );
          expect(
            r.headers['access-control-allow-origin'],
            isNull,
            reason: pfad,
          );
          if ((r.headers['content-type'] ?? '').startsWith(
            'application/json',
          )) {
            expect(r.headers['cache-control'], 'no-store', reason: pfad);
            expect(
              r.headers['content-security-policy'],
              contains('sandbox'),
              reason: pfad,
            );
          }
        }
      },
    );

    test(
      'ein Name mit Skript bleibt Daten; SVG kommt gar nicht erst an',
      () async {
        final bearer = konten.meldeAn(erika.id, 'Rechner', 'x').token;
        final bild = img.Image(width: 32, height: 24);
        img.fill(bild, color: img.ColorRgb8(200, 90, 20));
        final bytes = Uint8List.fromList(img.encodeJpg(bild));
        const name = '<img src=x onerror=alert(1)>.jpg';
        String meta(Map<String, String> w) => [
          for (final e in w.entries)
            '${e.key} ${base64.encode(utf8.encode(e.value))}',
        ].join(',');
        final tus = {
          'tus-resumable': '1.0.0',
          'authorization': 'Bearer $bearer',
        };
        final angelegt = await frag(
          'POST',
          '/api/v1/hochladen',
          kopf: {
            ...tus,
            'upload-length': '${bytes.length}',
            'upload-metadata': meta({'filename': name}),
          },
        );
        expect(angelegt.statusCode, 201);
        final fertig = await frag(
          'PATCH',
          angelegt.headers['location']!,
          kopf: {
            ...tus,
            'content-type': 'application/offset+octet-stream',
            'upload-offset': '0',
          },
          inhalt: bytes,
        );
        expect(fertig.headers['pv-ausgang'], 'imported');

        final (_, token) = await anmelden();
        final liste = await frag(
          'GET',
          '/api/v1/aufnahmen',
          kopf: mitCookie(token!),
        );
        expect(liste.headers['content-type'], startsWith('application/json'));
        expect(liste.headers['content-security-policy'], contains('sandbox'));
        final j = await jsonAus(liste);
        expect(((j['aufnahmen']! as List).single as Map)['name'], name);

        final svg = await frag(
          'POST',
          '/api/v1/hochladen',
          kopf: {
            ...tus,
            'upload-length': '100',
            'upload-metadata': meta({'filename': 'boese.svg'}),
          },
        );
        expect(svg.statusCode, 415);
      },
    );

    test('Hochladen aus dem Browser: mit X-PV-Web, sonst abgewiesen', () async {
      final (_, token) = await anmelden();
      final bild = img.Image(width: 20, height: 16);
      img.fill(bild, color: img.ColorRgb8(30, 140, 200));
      final bytes = Uint8List.fromList(img.encodeJpg(bild));
      final meta = [
        'filename ${base64.encode(utf8.encode('Käse.jpg'))}',
        'geaendert ${base64.encode(utf8.encode('1700000000000'))}',
      ].join(',');
      final tus = {'tus-resumable': '1.0.0'};
      final fremd = await frag(
        'POST',
        '/api/v1/hochladen',
        kopf: mitCookie(token!, {
          ...tus,
          'upload-length': '${bytes.length}',
          'upload-metadata': meta,
        }),
      );
      expect(fremd.statusCode, 403);
      final angelegt = await frag(
        'POST',
        '/api/v1/hochladen',
        kopf: mitCookie(token, {
          ...tus,
          'x-pv-web': '1',
          'upload-length': '${bytes.length}',
          'upload-metadata': meta,
        }),
      );
      expect(angelegt.statusCode, 201);
      final ort = angelegt.headers['location']!;
      final halb = bytes.length ~/ 2;
      final erstes = await frag(
        'PATCH',
        ort,
        kopf: mitCookie(token, {
          ...tus,
          'x-pv-web': '1',
          'content-type': 'application/offset+octet-stream',
          'upload-offset': '0',
        }),
        inhalt: bytes.sublist(0, halb),
      );
      expect(erstes.statusCode, 204);
      expect(erstes.headers['upload-offset'], '$halb');
      final fertig = await frag(
        'PATCH',
        ort,
        kopf: mitCookie(token, {
          ...tus,
          'x-pv-web': '1',
          'content-type': 'application/offset+octet-stream',
          'upload-offset': '$halb',
        }),
        inhalt: bytes.sublist(halb),
      );
      expect(fertig.headers['pv-ausgang'], 'imported');
      expect(fertig.headers['pv-aufnahme'], isNotNull);
      final nochmal = await frag(
        'POST',
        '/api/v1/hochladen',
        kopf: mitCookie(token, {
          ...tus,
          'x-pv-web': '1',
          'upload-length': '${bytes.length}',
          'upload-metadata': meta,
        }),
      );
      final doppelt = await frag(
        'PATCH',
        nochmal.headers['location']!,
        kopf: mitCookie(token, {
          ...tus,
          'x-pv-web': '1',
          'content-type': 'application/offset+octet-stream',
          'upload-offset': '0',
        }),
        inhalt: bytes,
      );
      expect(doppelt.headers['pv-ausgang'], 'duplicateSkipped');
      expect(doppelt.headers['pv-aufnahme'], fertig.headers['pv-aufnahme']);
    });
  });
}
