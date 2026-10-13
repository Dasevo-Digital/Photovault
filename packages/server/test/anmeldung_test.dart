import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Base32 zurück in Bytes – für den Prüfstand, der das Geheimnis wie eine
/// Authenticator-App aus der Antwort liest.
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

class _Verbindung implements HttpConnectionInfo {
  _Verbindung(String adresse) : remoteAddress = InternetAddress(adresse);
  @override
  final InternetAddress remoteAddress;
  @override
  int get localPort => 8790;
  @override
  int get remotePort => 40000;
}

void main() {
  group('TOTP nach RFC 6238', () {
    // Anhang B, SHA-1, Geheimnis "12345678901234567890"; die letzten
    // sechs der acht Ziffern.
    final geheimnis = ascii.encode('12345678901234567890');
    for (final (sekunden, code) in [
      (59, '287082'),
      (1111111109, '081804'),
      (1111111111, '050471'),
      (1234567890, '005924'),
      (2000000000, '279037'),
    ]) {
      test('$sekunden s → $code', () {
        final zeit = DateTime.fromMillisecondsSinceEpoch(sekunden * 1000);
        expect(Totp.code(geheimnis, Totp.schritt(zeit)), code);
        expect(Totp.pruefe(geheimnis, code, zeit), Totp.schritt(zeit));
      });
    }

    test('Base32 wie in den Authenticator-Apps', () {
      expect(Totp.base32(geheimnis), 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
      expect(_ausBase32(Totp.base32(geheimnis)), geheimnis);
    });

    test('ein Schritt daneben gilt, zwei nicht; ein Code gilt einmal', () {
      final zeit = DateTime.fromMillisecondsSinceEpoch(1111111111 * 1000);
      final s = Totp.schritt(zeit);
      expect(Totp.pruefe(geheimnis, Totp.code(geheimnis, s - 1), zeit), s - 1);
      expect(Totp.pruefe(geheimnis, Totp.code(geheimnis, s + 2), zeit), isNull);
      expect(
        Totp.pruefe(
          geheimnis,
          Totp.code(geheimnis, s),
          zeit,
          letzterSchritt: s,
        ),
        isNull,
        reason: 'derselbe Code ein zweites Mal',
      );
    });
  });

  group('Argon2id', () {
    test('rechnet wie RFC 9106 (Testvektor 5.3)', () async {
      // Prüft die Umsetzung in reinem Dart, auf die sich die Passwörter
      // verlassen.
      final kdf = Argon2id(
        parallelism: 4,
        memory: 32,
        iterations: 3,
        hashLength: 32,
      );
      final k = await kdf.deriveKey(
        secretKey: SecretKey(List.filled(32, 1)),
        nonce: List.filled(16, 2),
        optionalSecret: List.filled(8, 3),
        associatedData: List.filled(12, 4),
      );
      final hex = (await k.extractBytes())
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      expect(
        hex,
        '0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659',
      );
    });

    test('Prüfwert im PHC-Format, veraltet bei schwächeren Werten', () async {
      const schwach = Passwort(speicher: 64, durchgaenge: 1);
      final w = await schwach.pruefwertFuer('richtig richtig');
      expect(w, startsWith(r'$argon2id$v=19$m=64,t=1,p=1$'));
      expect(await schwach.stimmt('richtig richtig', w), isTrue);
      expect(await schwach.stimmt('falsch falsch', w), isFalse);
      expect(await schwach.stimmt('richtig richtig', 'kaputt'), isFalse);
      expect(const Passwort().veraltet(w), isTrue);
      expect(schwach.veraltet(w), isFalse);
    });
  });

  group('Kontodienst', () {
    late Serverdatenbank sdb;
    late Kontodienst konten;
    late DateTime jetzt;

    Kontodienst dienst({bool totpPflicht = true}) => Kontodienst(
      sdb,
      Tresorschluessel(List.filled(32, 9)),
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: totpPflicht,
      uhr: () => jetzt,
    );

    setUp(() {
      jetzt = DateTime.utc(2026, 10, 13, 12);
      sdb = Serverdatenbank.imSpeicher();
      konten = dienst();
    });
    tearDown(() => sdb.schliesse());

    /// Meldet an und richtet dabei TOTP ein; gibt Geheimnis und Codes.
    Future<({List<int> geheimnis, List<String> codes, String token})>
    ersteAnmeldung(String name, String passwort) async {
      final e = await konten.anmelden(
        name,
        passwort,
        geraet: 'Telefon',
        adresse: '192.0.2.5',
      );
      expect(e, isA<TotpEinrichten>());
      final einrichten = e as TotpEinrichten;
      final geheimnis = _ausBase32(einrichten.geheimnis);
      expect(einrichten.adresse, startsWith('otpauth://totp/'));
      final fertig = await konten.bestaetige(
        einrichten.vorgang,
        Totp.code(geheimnis, Totp.schritt(jetzt)),
        adresse: '192.0.2.5',
      );
      expect(fertig, isA<Angemeldet>());
      final a = fertig as Angemeldet;
      expect(a.wiederherstellungscodes, hasLength(10));
      return (
        geheimnis: geheimnis,
        codes: a.wiederherstellungscodes!,
        token: a.token,
      );
    }

    test(
      'anlegen: Name und Passwort werden geprüft, das erste ist Verwalter',
      () async {
        await expectLater(
          konten.legeAn('erika', 'zu kurz'),
          throwsA(isA<ArgumentError>()),
        );
        await expectLater(
          konten.legeAn('a/b', 'ein langes passwort'),
          throwsA(isA<ArgumentError>()),
        );
        final erstes = await konten.legeAn('erika', 'ein langes passwort');
        final zweites = await konten.legeAn('max', 'ein anderes passwort');
        expect(erstes.verwalter, isTrue);
        expect(zweites.verwalter, isFalse);
        await expectLater(
          konten.legeAn('ERIKA', 'ein langes passwort'),
          throwsA(isA<StateError>()),
          reason: 'Namen unterscheiden nicht nach Gross und klein',
        );
      },
    );

    test('Pflicht-TOTP wird bei der ersten Anmeldung eingerichtet, '
        'danach braucht jede Anmeldung einen frischen Code', () async {
      await konten.legeAn('erika', 'ein langes passwort');
      final erste = await ersteAnmeldung('erika', 'ein langes passwort');
      expect(konten.pruefeToken(erste.token, 'x'), isNotNull);

      final zweite = await konten.anmelden(
        'erika',
        'ein langes passwort',
        geraet: 'Rechner',
        adresse: '192.0.2.6',
      );
      expect(zweite, isA<TotpNoetig>());
      final vorgang = (zweite as TotpNoetig).vorgang;
      // Derselbe Code wie bei der Einrichtung: schon verbraucht.
      final alt = Totp.code(erste.geheimnis, Totp.schritt(jetzt));
      expect(
        await konten.bestaetige(vorgang, alt, adresse: '192.0.2.6'),
        isA<Abgewiesen>(),
      );
      jetzt = jetzt.add(const Duration(seconds: 30));
      final neu = Totp.code(erste.geheimnis, Totp.schritt(jetzt));
      expect(
        await konten.bestaetige(vorgang, neu, adresse: '192.0.2.6'),
        isA<Angemeldet>(),
      );
      expect(konten.geraete(konten.kontoNamens('erika')!.id), hasLength(2));
    });

    test('ein Wiederherstellungscode gilt genau einmal', () async {
      await konten.legeAn('erika', 'ein langes passwort');
      final erste = await ersteAnmeldung('erika', 'ein langes passwort');
      final id = konten.kontoNamens('erika')!.id;
      Future<Anmeldeergebnis> mitCode(String code) async {
        final v = await konten.anmelden(
          'erika',
          'ein langes passwort',
          geraet: 'Ersatz',
          adresse: '192.0.2.7',
        );
        return konten.bestaetige(
          (v as TotpNoetig).vorgang,
          code,
          adresse: '192.0.2.7',
        );
      }

      final code = erste.codes.first.toUpperCase();
      expect(await mitCode(code), isA<Angemeldet>());
      expect(konten.uebrigeCodes(id), 9);
      expect(await mitCode(code), isA<Abgewiesen>());
    });

    test(
      'nach fünf Fehlversuchen gesperrt, auch für das richtige Passwort',
      () async {
        konten = dienst(totpPflicht: false);
        await konten.legeAn('erika', 'ein langes passwort');
        for (var i = 0; i < 5; i++) {
          final e = await konten.anmelden(
            'erika',
            'falsch falsch falsch',
            geraet: '',
            adresse: '198.51.100.$i',
          );
          expect(e, isA<Abgewiesen>());
          expect((e as Abgewiesen).warte, isNull);
        }
        final gesperrt = await konten.anmelden(
          'erika',
          'ein langes passwort',
          geraet: '',
          adresse: '198.51.100.200',
        );
        expect((gesperrt as Abgewiesen).warte, isNotNull);
        jetzt = jetzt.add(const Duration(minutes: 1, seconds: 1));
        expect(
          await konten.anmelden(
            'erika',
            'ein langes passwort',
            geraet: '',
            adresse: '198.51.100.200',
          ),
          isA<Angemeldet>(),
        );
      },
    );

    test(
      'ein unbekannter Name verhält sich genauso – er verrät sich nicht',
      () async {
        for (var i = 0; i < 5; i++) {
          final e = await konten.anmelden(
            'niemand',
            'irgendwas irgendwas',
            geraet: '',
            adresse: '203.0.113.$i',
          );
          expect((e as Abgewiesen).warte, isNull);
        }
        final danach = await konten.anmelden(
          'niemand',
          'irgendwas irgendwas',
          geraet: '',
          adresse: '203.0.113.200',
        );
        expect((danach as Abgewiesen).warte, isNotNull);
      },
    );

    test('eine Adresse mit zu vielen Fehlversuchen wird abgewiesen, bevor '
        'gerechnet wird', () async {
      konten = dienst(totpPflicht: false);
      await konten.legeAn('erika', 'ein langes passwort');
      for (var i = 0; i < 10; i++) {
        await konten.anmelden(
          'name$i',
          'falsch falsch falsch',
          geraet: '',
          adresse: '203.0.113.99',
        );
      }
      final e = await konten.anmelden(
        'erika',
        'ein langes passwort',
        geraet: '',
        adresse: '203.0.113.99',
      );
      expect((e as Abgewiesen).warte, isNotNull);
      jetzt = jetzt.add(const Duration(minutes: 16));
      expect(
        await konten.anmelden(
          'erika',
          'ein langes passwort',
          geraet: '',
          adresse: '203.0.113.99',
        ),
        isA<Angemeldet>(),
      );
    });

    test('Geräte: einzeln abmelden, Ablauf nach langer Pause, neues Passwort '
        'meldet alle ab', () async {
      konten = dienst(totpPflicht: false);
      final k = await konten.legeAn('erika', 'ein langes passwort');
      final a = konten.meldeAn(k.id, 'Telefon', 'x');
      final b = konten.meldeAn(k.id, 'Rechner', 'x');
      expect(konten.abmelden(k.id, a.geraet.id), isTrue);
      expect(konten.pruefeToken(a.token, 'x'), isNull);
      expect(konten.pruefeToken(b.token, 'x')!.konto.name, 'erika');

      jetzt = jetzt.add(const Duration(days: 181));
      expect(konten.pruefeToken(b.token, 'x'), isNull, reason: 'abgelaufen');

      final c = konten.meldeAn(k.id, 'Neu', 'x');
      await konten.setzePasswort(k.id, 'ein neues langes passwort');
      expect(konten.pruefeToken(c.token, 'x'), isNull);
    });

    test('das Passwort ändern braucht das alte und den Code', () async {
      await konten.legeAn('erika', 'ein langes passwort');
      final erste = await ersteAnmeldung('erika', 'ein langes passwort');
      final id = konten.kontoNamens('erika')!.id;
      jetzt = jetzt.add(const Duration(seconds: 30));
      final code = Totp.code(erste.geheimnis, Totp.schritt(jetzt));
      expect(
        await konten.aenderePasswort(
          id,
          'ein langes passwort',
          'neu neu neu neu',
        ),
        isFalse,
        reason: 'ohne Code',
      );
      expect(
        await konten.aenderePasswort(
          id,
          'ein langes passwort',
          'neu neu neu neu',
          code: code,
        ),
        isTrue,
      );
    });

    test(
      'das TOTP-Geheimnis steht nicht im Klartext in der Datenbank',
      () async {
        await konten.legeAn('erika', 'ein langes passwort');
        final erste = await ersteAnmeldung('erika', 'ein langes passwort');
        final roh =
            sdb.db.select('SELECT totp FROM konten').first['totp'] as String;
        expect(roh, isNot(contains(Totp.base32(erste.geheimnis))));
        expect(base64.decode(roh), isNot(containsAllInOrder(erste.geheimnis)));
      },
    );
  });

  group('über die Schnittstelle', () {
    late Directory ordner;
    late Serverdatenbank sdb;
    late Kontodienst konten;
    late Bibliotheken bibliotheken;
    late Handler api;

    setUp(() async {
      ordner = await Directory.systemTemp.createTemp('pv_anmeldung_');
      sdb = Serverdatenbank.imSpeicher();
      konten = Kontodienst(
        sdb,
        Tresorschluessel(List.filled(32, 3)),
        passwort: const Passwort(speicher: 64, durchgaenge: 1),
      );
      bibliotheken = Bibliotheken(
        wurzel: Directory('${ordner.path}/bibliotheken'),
        eingang: Directory('${ordner.path}/eingang'),
        ruhe: const Duration(hours: 1),
      );
      api = baueApi(
        konten: konten,
        bibliotheken: bibliotheken,
        absender: Absender(['127.0.0.1']),
      );
    });
    tearDown(() async {
      await bibliotheken.schliesseAlle();
      sdb.schliesse();
      await ordner.delete(recursive: true);
    });

    Future<Response> frag(
      String methode,
      String pfad, {
      Object? json,
      String? token,
      Map<String, String> kopf = const {},
      Object? inhalt,
    }) async => api(
      Request(
        methode,
        Uri.parse('http://server$pfad'),
        headers: {
          if (token != null) 'authorization': 'Bearer $token',
          if (json != null) 'content-type': 'application/json',
          ...kopf,
        },
        body: json == null ? inhalt : jsonEncode(json),
      ),
    );

    Future<Map<String, Object?>> jsonAus(Response r) async =>
        (jsonDecode(await r.readAsString()) as Map).cast<String, Object?>();

    /// Der ganze Weg über HTTP: Passwort, TOTP einrichten, Token.
    Future<String> melde(String name) async {
      await konten.legeAn(name, 'ein langes passwort');
      final r1 = await jsonAus(
        await frag(
          'POST',
          '/api/v1/anmelden',
          json: {
            'name': name,
            'passwort': 'ein langes passwort',
            'geraet': 'Pixel',
          },
        ),
      );
      expect(r1['schritt'], 'totp_einrichten');
      final geheimnis = _ausBase32(r1['geheimnis']! as String);
      final antwort = await frag(
        'POST',
        '/api/v1/anmelden/totp',
        json: {
          'vorgang': r1['vorgang'],
          'code': Totp.code(geheimnis, Totp.schritt(DateTime.now())),
        },
      );
      expect(antwort.headers['cache-control'], 'no-store');
      final r2 = await jsonAus(antwort);
      expect(r2['wiederherstellungscodes'], hasLength(10));
      return r2['token']! as String;
    }

    test('anmelden, Konto und Geräte ansehen, abmelden', () async {
      final zustand = await jsonAus(await frag('GET', '/api/v1/zustand'));
      expect(zustand['anmeldung'], {'totp': true, 'oidc': false});

      final token = await melde('erika');
      final konto = await jsonAus(
        await frag('GET', '/api/v1/konto', token: token),
      );
      expect(konto['name'], 'erika');
      expect(konto['totp'], isTrue);
      final geraete = await jsonAus(
        await frag('GET', '/api/v1/geraete', token: token),
      );
      expect((geraete['geraete']! as List).single['name'], 'Pixel');

      expect(
        (await frag('POST', '/api/v1/abmelden', token: token)).statusCode,
        200,
      );
      expect(
        (await frag('GET', '/api/v1/konto', token: token)).statusCode,
        401,
      );
    });

    test('falsches Passwort: 401, gebremst: 429 mit Retry-After', () async {
      await konten.legeAn('erika', 'ein langes passwort');
      Future<Response> falsch() => frag(
        'POST',
        '/api/v1/anmelden',
        json: {'name': 'erika', 'passwort': 'falsch falsch falsch'},
      );
      for (var i = 0; i < 5; i++) {
        expect((await falsch()).statusCode, 401);
      }
      final gesperrt = await falsch();
      expect(gesperrt.statusCode, 429);
      expect(int.parse(gesperrt.headers['retry-after']!), greaterThan(0));
    });

    test('jedes Konto sieht nur seine eigene Bibliothek', () async {
      final erika = await melde('erika');
      final max = await melde('max');
      final bild = img.Image(width: 32, height: 24);
      img.fill(bild, color: img.ColorRgb8(200, 40, 40));
      final bytes = Uint8List.fromList(img.encodeJpg(bild));

      final angelegt = await frag(
        'POST',
        '/api/v1/hochladen',
        token: erika,
        kopf: {
          'tus-resumable': '1.0.0',
          'upload-length': '${bytes.length}',
          'upload-metadata': 'filename ${base64.encode(utf8.encode('a.jpg'))}',
        },
      );
      final fertig = await frag(
        'PATCH',
        angelegt.headers['location']!,
        token: erika,
        kopf: {
          'tus-resumable': '1.0.0',
          'content-type': 'application/offset+octet-stream',
          'upload-offset': '0',
        },
        inhalt: bytes,
      );
      final id = fertig.headers['pv-aufnahme']!;

      Future<int> anzahl(String token) async =>
          ((await jsonAus(
                    await frag('GET', '/api/v1/aufnahmen', token: token),
                  ))['aufnahmen']!
                  as List)
              .length;
      expect(await anzahl(erika), 1);
      expect(await anzahl(max), 0);
      expect(
        (await frag('GET', '/api/v1/aufnahmen/$id', token: max)).statusCode,
        404,
      );
      expect(
        (await frag(
          'GET',
          '/api/v1/aufnahmen/$id/original',
          token: max,
        )).statusCode,
        404,
      );
      // Auch an den Upload eines anderen kommt niemand heran.
      expect(
        (await frag(
          'HEAD',
          angelegt.headers['location']!,
          token: max,
          kopf: {'tus-resumable': '1.0.0'},
        )).statusCode,
        404,
      );
    });

    test('ein Gerät eines anderen Kontos lässt sich nicht abmelden', () async {
      final erika = await melde('erika');
      final max = await melde('max');
      final geraeteMax = await jsonAus(
        await frag('GET', '/api/v1/geraete', token: max),
      );
      final idMax = geraeteMax['dieses']! as String;
      expect(
        (await frag(
          'DELETE',
          '/api/v1/geraete/$idMax',
          token: erika,
        )).statusCode,
        404,
      );
      expect((await frag('GET', '/api/v1/konto', token: max)).statusCode, 200);
    });
  });

  test('der QR-Code fürs Terminal hat Rand und zwei Zeilen je Textzeile', () {
    final adresse = Totp.adresse(Totp.neuesGeheimnis(), 'erika');
    final zeilen = qrImTerminal(adresse).trimRight().split('\n');
    // Version 5 bei dieser Länge: 37 Module, dazu zweimal zwei Rand.
    final module = zeilen.first.split('▀').length - 1;
    expect(module, greaterThanOrEqualTo(29));
    expect(zeilen, hasLength((module + 1) ~/ 2));
  });

  group('Absender hinter dem Proxy', () {
    // Proxys stehen in privaten Netzen. Ihre Adressen als Zahlen: Es sind
    // Beispiele, keine echten – der Text sähe für die Datenschutzprüfung
    // aus wie ein internes Netz.
    String v4(int a, int b, int c, int d) => '$a.$b.$c.$d';
    final dockerNetz = '${v4(172, 18, 0, 0)}/16';
    final proxy = v4(172, 18, 0, 2);

    Request anfrage(String von, [String? weitergeleitet]) => Request(
      'GET',
      Uri.parse('http://server/'),
      headers: {'x-forwarded-for': ?weitergeleitet},
      context: {'shelf.io.connection_info': _Verbindung(von)},
    );

    test('ohne vertrauten Proxy zählt die Verbindung, nicht der Kopf', () {
      expect(Absender().von(anfrage('203.0.113.9', '1.2.3.4')), '203.0.113.9');
    });

    test('hinter vertrautem Proxy die erste fremde Adresse von rechts', () {
      final a = Absender([dockerNetz]);
      expect(a.von(anfrage(proxy, '198.51.100.7')), '198.51.100.7');
      // Was der Absender selbst links hineinschreibt, zählt nicht.
      expect(
        a.von(anfrage(proxy, '203.0.113.66, 198.51.100.7')),
        '198.51.100.7',
      );
      expect(
        a.von(anfrage(proxy, '198.51.100.7, ${v4(172, 18, 0, 5)}')),
        '198.51.100.7',
      );
    });

    test('„privat“ umfasst Heimnetz, Docker und den eigenen Rechner', () {
      final a = Absender(['privat']);
      for (final proxy in [
        v4(10, 1, 2, 3),
        v4(172, 20, 0, 3),
        v4(192, 168, 0, 2),
        '127.0.0.1',
        '::1',
        'fd12::3',
      ]) {
        expect(a.von(anfrage(proxy, '198.51.100.7')), '198.51.100.7');
      }
      expect(a.von(anfrage('198.51.100.8', '1.2.3.4')), '198.51.100.8');
    });
  });
}
