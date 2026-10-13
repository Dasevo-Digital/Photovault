import 'dart:convert';
import 'dart:io';

import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

/// Ein OIDC-Anbieter zum Prüfen: gibt Codes aus, wie der Prüfstand es
/// sagt, und löst sie ein wie ein echter – mit Client-Geheimnis, PKCE und
/// derselben Weiterleitungsadresse.
class _Anbieter {
  late HttpServer _server;
  String get aussteller => 'http://127.0.0.1:${_server.port}';
  final codes =
      <
        String,
        ({String nonce, String challenge, String sub, String redirect})
      >{};

  /// Was das ID-Token anders sagen soll als richtig.
  Map<String, Object?> verfaelscht = {};
  String? andererAussteller;

  Future<void> starte() async {
    _server = await shelf_io.serve(_antworte, '127.0.0.1', 0);
  }

  Future<void> beende() => _server.close(force: true);

  /// Der Anbieter meldet [sub] an – die Angaben aus der Weiterleitung des
  /// Servers, der Code für den Rückweg.
  String meldeAn(Uri weiterleitung, String sub) {
    final q = weiterleitung.queryParameters;
    expect(q['response_type'], 'code');
    expect(q['code_challenge_method'], 'S256');
    final code = 'c${codes.length + 1}';
    codes[code] = (
      nonce: q['nonce']!,
      challenge: q['code_challenge']!,
      sub: sub,
      redirect: q['redirect_uri']!,
    );
    return code;
  }

  Future<Response> _antworte(Request r) async {
    if (r.url.path == '.well-known/openid-configuration') {
      return Response.ok(
        jsonEncode({
          'issuer': andererAussteller ?? aussteller,
          'authorization_endpoint': '$aussteller/anmelden',
          'token_endpoint': '$aussteller/token',
        }),
        headers: {'content-type': 'application/json'},
      );
    }
    if (r.url.path == 'token' && r.method == 'POST') {
      final basic = 'Basic ${base64.encode(utf8.encode('fotos:geheim'))}';
      if (r.headers['authorization'] != basic) return Response(401);
      final f = Uri.splitQueryString(await r.readAsString());
      final c = codes.remove(f['code']);
      if (c == null ||
          f['grant_type'] != 'authorization_code' ||
          f['redirect_uri'] != c.redirect ||
          Oidc.s256(f['code_verifier'] ?? '') != c.challenge) {
        return Response(400, body: '{"error":"invalid_grant"}');
      }
      String teil(Map<String, Object?> m) =>
          base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
      final jetzt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final idToken = [
        teil({'alg': 'RS256', 'typ': 'JWT'}),
        teil({
          'iss': aussteller,
          'aud': 'fotos',
          'sub': c.sub,
          'nonce': c.nonce,
          'iat': jetzt,
          'exp': jetzt + 300,
          ...verfaelscht,
        }),
        'unterschrift',
      ].join('.');
      return Response.ok(
        jsonEncode({
          'access_token': 'a',
          'token_type': 'Bearer',
          'id_token': idToken,
        }),
        headers: {'content-type': 'application/json'},
      );
    }
    return Response.notFound(null);
  }
}

void main() {
  late _Anbieter anbieter;
  late Directory ordner;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late Oidc oidc;
  late Handler api;
  late Konto erika;
  late String tokenErika;

  const pruefer = 'ein-pruefer-den-nur-die-app-kennt-0123456789abcdefghijk';
  final rueckweg = Uri.parse('http://127.0.0.1:47011/zurueck');

  setUp(() async {
    anbieter = _Anbieter();
    await anbieter.starte();
    ordner = await Directory.systemTemp.createTemp('pv_oidc_');
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
    oidc = Oidc(
      OidcEinstellungen(
        aussteller: Uri.parse(anbieter.aussteller),
        client: 'fotos',
        geheimnis: 'geheim',
        oeffentlich: Uri.parse('https://fotos.example.org/'),
      ),
    );
    api = baueApi(konten: konten, bibliotheken: bibliotheken, oidc: oidc);
    erika = await konten.legeAn('erika', 'ein langes passwort');
    tokenErika = konten.meldeAn(erika.id, 'Rechner', 'x').token;
  });
  tearDown(() async {
    oidc.schliesse();
    await anbieter.beende();
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  Future<Response> frag(
    String methode,
    String pfad, {
    Object? json,
    String? token,
  }) async => api(
    Request(
      methode,
      Uri.parse('http://server$pfad'),
      headers: {
        if (token != null) 'authorization': 'Bearer $token',
        if (json != null) 'content-type': 'application/json',
      },
      body: json == null ? null : jsonEncode(json),
    ),
  );

  Future<Map<String, Object?>> jsonAus(Response r) async =>
      (jsonDecode(await r.readAsString()) as Map).cast<String, Object?>();

  /// Vom Anbieter zurück zum Server; gibt die Weiterleitung zur App.
  Future<Uri> zurueck(Uri weiterleitung, String sub) async {
    final code = anbieter.meldeAn(weiterleitung, sub);
    final r = await frag(
      'GET',
      '/api/v1/anmelden/oidc/zurueck?code=$code'
          '&state=${weiterleitung.queryParameters['state']}',
    );
    expect(r.statusCode, 302);
    return Uri.parse(r.headers['location']!);
  }

  Future<Uri> starteAnmeldung() async {
    final r = await frag(
      'GET',
      '/api/v1/anmelden/oidc?geraet=Pixel'
          '&rueckweg=${Uri.encodeComponent('$rueckweg')}'
          '&pruefwert=${Oidc.s256(pruefer)}&zustand=z1',
    );
    expect(r.statusCode, 302);
    final ziel = Uri.parse(r.headers['location']!);
    expect(ziel.toString(), startsWith('${anbieter.aussteller}/anmelden'));
    expect(
      ziel.queryParameters['redirect_uri'],
      'https://fotos.example.org/api/v1/anmelden/oidc/zurueck',
    );
    return ziel;
  }

  Future<void> verknuepfe(String sub) async {
    final start = await jsonAus(
      await frag(
        'POST',
        '/api/v1/konto/oidc',
        token: tokenErika,
        json: {'rueckweg': '$rueckweg', 'pruefwert': Oidc.s256(pruefer)},
      ),
    );
    final zurApp = await zurueck(Uri.parse(start['adresse']! as String), sub);
    expect(zurApp.toString(), startsWith('$rueckweg?'));
    final r = await frag(
      'POST',
      '/api/v1/anmelden/oidc/einloesen',
      token: tokenErika,
      json: {'code': zurApp.queryParameters['code'], 'pruefer': pruefer},
    );
    expect(await jsonAus(r), {'verknuepft': true});
  }

  test('verknüpfen, dann über den Anbieter anmelden', () async {
    await verknuepfe('nutzer-17');
    expect(konten.oidcAussteller(erika.id), [anbieter.aussteller]);

    final zurApp = await zurueck(await starteAnmeldung(), 'nutzer-17');
    expect(zurApp.queryParameters['zustand'], 'z1');
    final r = await jsonAus(
      await frag(
        'POST',
        '/api/v1/anmelden/oidc/einloesen',
        json: {'code': zurApp.queryParameters['code'], 'pruefer': pruefer},
      ),
    );
    final token = r['token']! as String;
    expect(konten.pruefeToken(token, 'x')!.konto.id, erika.id);
    expect((r['geraet']! as Map)['name'], 'Pixel');
  });

  test('der Code taugt nur mit dem Prüfer und nur einmal', () async {
    await verknuepfe('nutzer-17');
    final zurApp = await zurueck(await starteAnmeldung(), 'nutzer-17');
    final code = zurApp.queryParameters['code'];
    final falsch = await frag(
      'POST',
      '/api/v1/anmelden/oidc/einloesen',
      json: {
        'code': code,
        'pruefer': 'ein-anderer-pruefer-der-nicht-passt-0123456789abcd',
      },
    );
    expect(falsch.statusCode, 401);
    final nochmal = await frag(
      'POST',
      '/api/v1/anmelden/oidc/einloesen',
      json: {'code': code, 'pruefer': pruefer},
    );
    expect(nochmal.statusCode, 401, reason: 'ein Fehlversuch verbraucht ihn');
  });

  test('ohne Verknüpfung keine Anmeldung', () async {
    final zurApp = await zurueck(await starteAnmeldung(), 'fremd');
    final r = await frag(
      'POST',
      '/api/v1/anmelden/oidc/einloesen',
      json: {'code': zurApp.queryParameters['code'], 'pruefer': pruefer},
    );
    expect(r.statusCode, 403);
  });

  test('ein Rückweg ins Netz wird nicht angenommen', () async {
    final r = await frag(
      'GET',
      '/api/v1/anmelden/oidc?geraet=x'
          '&rueckweg=${Uri.encodeComponent('https://angreifer.example/')}'
          '&pruefwert=${Oidc.s256(pruefer)}',
    );
    expect(r.statusCode, 400);
    expect(r.headers['content-type'], startsWith('text/html'));
    expect(Oidc.rueckwegErlaubt(Uri.parse('photovault:/anmeldung')), isTrue);
    expect(Oidc.rueckwegErlaubt(Uri.parse('http://127.0.0.1:9000/x')), isTrue);
    expect(
      Oidc.rueckwegErlaubt(Uri.parse('http://127.0.0.1.angreifer.example/')),
      isFalse,
    );
  });

  test(
    'eine Verknüpfung löst nur das Konto ein, das sie begonnen hat',
    () async {
      final max = await konten.legeAn('max', 'ein anderes passwort');
      final tokenMax = konten.meldeAn(max.id, 'Telefon', 'x').token;
      final start = await jsonAus(
        await frag(
          'POST',
          '/api/v1/konto/oidc',
          token: tokenErika,
          json: {'rueckweg': '$rueckweg', 'pruefwert': Oidc.s256(pruefer)},
        ),
      );
      final zurApp = await zurueck(
        Uri.parse(start['adresse']! as String),
        'x1',
      );
      final r = await frag(
        'POST',
        '/api/v1/anmelden/oidc/einloesen',
        token: tokenMax,
        json: {'code': zurApp.queryParameters['code'], 'pruefer': pruefer},
      );
      expect(r.statusCode, 401);
      expect(konten.oidcAussteller(max.id), isEmpty);
      expect(konten.oidcAussteller(erika.id), isEmpty);
    },
  );

  test(
    'ein ID-Token mit falscher nonce oder falschem Empfänger gilt nicht',
    () async {
      for (final falsch in [
        {'nonce': 'eine andere'},
        {'aud': 'jemand-anders'},
        {'exp': 1000},
        {'iss': 'https://anderer.example'},
      ]) {
        anbieter.verfaelscht = falsch;
        final zurApp = await zurueck(await starteAnmeldung(), 'nutzer-17');
        expect(zurApp.queryParameters['fehler'], 'token', reason: '$falsch');
        expect(zurApp.queryParameters.containsKey('code'), isFalse);
      }
    },
  );

  test(
    'ein Anbieter, der sich als ein anderer ausgibt, wird abgelehnt',
    () async {
      anbieter.andererAussteller = 'https://anderer.example';
      final r = await frag(
        'GET',
        '/api/v1/anmelden/oidc?geraet=x'
            '&rueckweg=${Uri.encodeComponent('$rueckweg')}'
            '&pruefwert=${Oidc.s256(pruefer)}',
      );
      expect(r.statusCode, 400);
    },
  );

  test('eine unbekannte Rückkehr zeigt eine Seite statt zu leiten', () async {
    final r = await frag(
      'GET',
      '/api/v1/anmelden/oidc/zurueck?code=c1&state=erfunden',
    );
    expect(r.statusCode, 400);
    expect(await r.readAsString(), contains('unbekannt oder abgelaufen'));
  });
}
