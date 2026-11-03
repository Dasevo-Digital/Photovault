import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as kr;
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:photo_vault_server/src/konten/passkeys.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Passkeys (#277) mit einem nachgebauten Gerät: Es erzeugt echte
/// Schlüssel, schreibt `authenticatorData` und unterschreibt wie ein
/// Telefon oder ein Sicherheitsschlüssel. So prüft der Test die
/// Rechnung des Servers, nicht eine Attrappe davon.
void main() {
  const herkunft = 'http://localhost:18791';
  late Directory ordner;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Konto konto;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_passkeys_');
    sdb = Serverdatenbank.imSpeicher();
    konten = Kontodienst(
      sdb,
      Tresorschluessel(List.filled(32, 7)),
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: false,
    );
    konto = await konten.legeAn('erika', 'ein langes passwort');
  });
  tearDown(() async {
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  test('ES256: anlegen, anmelden, und was abgewiesen wird', () async {
    final geraet = _Geraet.es256();
    final angelegt = await konten.passkeys.lege(
      kontoId: konto.id,
      herkunft: herkunft,
      antwort: geraet.anlegen(
        konten.passkeys.anlegeoptionen(
          kontoId: konto.id,
          kontoName: konto.name,
          rp: 'localhost',
          servername: 'Photo Vault',
        ),
        herkunft,
      ),
      name: 'Testschlüssel',
    );
    expect(angelegt.name, 'Testschlüssel');
    expect(konten.passkeys.von(konto.id).single.id, geraet.kennung);

    Map<String, Object?> anmelden({
      String origin = herkunft,
      int merkmale = 0x05,
      bool verfaelschen = false,
      Map<String, Object?>? optionen,
    }) => geraet.anmelden(
      optionen ?? konten.passkeys.anmeldeoptionen(rp: 'localhost'),
      origin,
      merkmale: merkmale,
      verfaelschen: verfaelschen,
      konto: konto.id,
    );

    expect(
      await konten.passkeys.pruefeAnmeldung(
        herkunft: herkunft,
        antwort: anmelden(),
      ),
      konto.id,
    );

    Future<void> abgewiesen(Map<String, Object?> antwort, String grund) =>
        expectLater(
          konten.passkeys.pruefeAnmeldung(herkunft: herkunft, antwort: antwort),
          throwsA(isA<PasskeyFehler>()),
          reason: grund,
        );
    await abgewiesen(anmelden(verfaelschen: true), 'Unterschrift falsch');
    await abgewiesen(anmelden(merkmale: 0x01), 'ohne Prüfung des Menschen');
    await abgewiesen(
      anmelden(origin: 'http://localhost:9999'),
      'andere Seite als die, die fragt',
    );
    final einmal = konten.passkeys.anmeldeoptionen(rp: 'localhost');
    expect(
      await konten.passkeys.pruefeAnmeldung(
        herkunft: herkunft,
        antwort: anmelden(optionen: einmal),
      ),
      konto.id,
    );
    await abgewiesen(
      anmelden(optionen: einmal),
      'eine Herausforderung gilt einmal',
    );
    await abgewiesen(
      _Geraet.es256().anmelden(
        konten.passkeys.anmeldeoptionen(rp: 'localhost'),
        herkunft,
        konto: konto.id,
      ),
      'unbekannter Passkey',
    );

    expect(konten.passkeys.entferne(konto.id, geraet.kennung), isTrue);
    await abgewiesen(anmelden(), 'entfernt');
  });

  test('EdDSA und ein Zähler, der nicht wachsen darf', () async {
    final geraet = await _Geraet.ed25519();
    await konten.passkeys.lege(
      kontoId: konto.id,
      herkunft: herkunft,
      antwort: geraet.anlegen(
        konten.passkeys.anlegeoptionen(
          kontoId: konto.id,
          kontoName: konto.name,
          rp: 'localhost',
          servername: 'Photo Vault',
        ),
        herkunft,
        zaehler: 3,
      ),
      name: '',
    );
    Future<String> mit(int zaehler) async => konten.passkeys.pruefeAnmeldung(
      herkunft: herkunft,
      antwort: await geraet.anmeldenAsync(
        konten.passkeys.anmeldeoptionen(rp: 'localhost'),
        herkunft,
        zaehler: zaehler,
        konto: konto.id,
      ),
    );
    expect(await mit(4), konto.id);
    await expectLater(
      mit(4),
      throwsA(isA<PasskeyFehler>()),
      reason: 'kopierter Schlüssel',
    );
    expect(konten.passkeys.von(konto.id).single.name, 'Passkey');
  });

  test('nur über HTTPS oder auf diesem Rechner', () {
    expect(Passkeys.rpAus('https://fotos.example.de'), 'fotos.example.de');
    expect(Passkeys.rpAus('http://localhost:8790'), 'localhost');
    expect(
      () => Passkeys.rpAus('http://fotos.example.de'),
      throwsA(isA<PasskeyFehler>()),
    );
  });

  group('über die Schnittstelle', () {
    late Handler api;
    setUp(
      () => api = baueApi(
        konten: konten,
        bibliotheken: Bibliotheken(
          wurzel: Directory('${ordner.path}/b'),
          eingang: Directory('${ordner.path}/e'),
        ),
      ),
    );

    Future<Map<String, Object?>> frag(
      String methode,
      String pfad, {
      Object? inhalt,
      String? token,
      int erwartet = 200,
    }) async {
      final r = await api(
        Request(
          methode,
          Uri.parse('http://localhost:18791$pfad'),
          headers: {
            'origin': herkunft,
            'content-type': 'application/json',
            if (token != null) 'authorization': 'Bearer $token',
          },
          body: inhalt == null ? null : jsonEncode(inhalt),
        ),
      );
      expect(r.statusCode, erwartet, reason: '$methode $pfad');
      return jsonDecode(await r.readAsString()) as Map<String, Object?>;
    }

    test('das Telefon: Ticket, anlegen, anmelden, Code einlösen', () async {
      final token = konten.meldeAn(konto.id, 'Telefon', 'lokal').token;
      final zustand = await frag('GET', '/api/v1/zustand');
      expect((zustand['anmeldung']! as Map)['passkeys'], isTrue);

      final t = await frag(
        'POST',
        '/api/v1/konto/passkeys/ticket',
        token: token,
      );
      final ticket = Uri.parse(
        t['adresse']! as String,
      ).queryParameters['ticket']!;
      final geraet = _Geraet.es256();
      final o = await frag(
        'POST',
        '/api/v1/passkeys/ticket/optionen',
        inhalt: {'ticket': ticket},
      );
      await frag(
        'POST',
        '/api/v1/passkeys/ticket',
        inhalt: {
          'ticket': ticket,
          'name': 'iPhone',
          'antwort': geraet.anlegen(
            (o['optionen']! as Map).cast<String, Object?>(),
            herkunft,
          ),
        },
      );
      await frag(
        'POST',
        '/api/v1/passkeys/ticket',
        inhalt: {'ticket': ticket, 'antwort': {}},
        erwartet: 401,
      );
      final liste = await frag('GET', '/api/v1/konto/passkeys', token: token);
      expect(
        (liste['passkeys']! as List).single,
        containsPair('name', 'iPhone'),
      );

      const pruefer = 'ein-pruefer-der-nur-die-app-kennt-0123456789abcdef';
      final pruefwert = Oidc.s256(pruefer);
      final a = await frag('POST', '/api/v1/anmelden/passkey/optionen');
      final weiter = await frag(
        'POST',
        '/api/v1/anmelden/passkey',
        inhalt: {
          'antwort': geraet.anmelden(
            (a['optionen']! as Map).cast<String, Object?>(),
            herkunft,
            konto: konto.id,
          ),
          'pruefwert': pruefwert,
          'rueckweg': 'http://127.0.0.1:53111/passkey',
          'zustand': 'z1',
          'geraet': 'iPhone von Erika',
        },
      );
      final zurueck = Uri.parse(weiter['weiter']! as String);
      expect(zurueck.host, '127.0.0.1');
      expect(zurueck.queryParameters['zustand'], 'z1');
      final code = zurueck.queryParameters['code']!;
      await frag(
        'POST',
        '/api/v1/anmelden/passkey/einloesen',
        inhalt: {'code': code, 'pruefer': 'falsch'},
        erwartet: 401,
      );
      // Der Code ist mit dem falschen Prüfer verbraucht – neu anmelden.
      final a2 = await frag('POST', '/api/v1/anmelden/passkey/optionen');
      final w2 = await frag(
        'POST',
        '/api/v1/anmelden/passkey',
        inhalt: {
          'antwort': geraet.anmelden(
            (a2['optionen']! as Map).cast<String, Object?>(),
            herkunft,
            konto: konto.id,
          ),
          'pruefwert': pruefwert,
          'rueckweg': 'http://127.0.0.1:53111/passkey',
          'geraet': 'iPhone von Erika',
        },
      );
      final e = await frag(
        'POST',
        '/api/v1/anmelden/passkey/einloesen',
        inhalt: {
          'code': Uri.parse(w2['weiter']! as String).queryParameters['code'],
          'pruefer': pruefer,
        },
      );
      expect(e['token'], startsWith('pv1_'));
      expect((e['geraet']! as Map)['name'], 'iPhone von Erika');
    });

    test('ein Rückweg ausserhalb des Telefons wird abgewiesen', () async {
      final a = await frag('POST', '/api/v1/anmelden/passkey/optionen');
      await frag(
        'POST',
        '/api/v1/anmelden/passkey',
        inhalt: {
          'antwort': _Geraet.es256().anmelden(
            (a['optionen']! as Map).cast<String, Object?>(),
            herkunft,
            konto: konto.id,
          ),
          'pruefwert': Oidc.s256('x' * 40),
          'rueckweg': 'https://boese.example/fang',
        },
        erwartet: 400,
      );
    });
  });
}

// --- Das nachgebaute Gerät ------------------------------------------------------

class _Geraet {
  _Geraet._(this.cose, this._unterschreibe, this._unterschreibeAsync)
    : kennungRoh = Uint8List.fromList(
        List.generate(16, (_) => Random.secure().nextInt(256)),
      );

  factory _Geraet.es256() {
    final zufall = pc.FortunaRandom()
      ..seed(
        pc.KeyParameter(
          Uint8List.fromList(
            List.generate(32, (_) => Random.secure().nextInt(256)),
          ),
        ),
      );
    final erzeuger = pc.ECKeyGenerator()
      ..init(
        pc.ParametersWithRandom(
          pc.ECKeyGeneratorParameters(pc.ECCurve_secp256r1()),
          zufall,
        ),
      );
    final paar = erzeuger.generateKeyPair();
    final oeffentlich = paar.publicKey;
    final privat = paar.privateKey;
    Uint8List zahl(BigInt v) {
      final b = Uint8List(32);
      for (var i = 31; i >= 0; i--) {
        b[i] = (v & BigInt.from(0xFF)).toInt();
        v >>= 8;
      }
      return b;
    }

    Uint8List unterschreibe(Uint8List daten) {
      final s = pc.ECDSASigner(pc.SHA256Digest())
        ..init(
          true,
          pc.ParametersWithRandom(pc.PrivateKeyParameter(privat), zufall),
        );
      final sig = s.generateSignature(daten) as pc.ECSignature;
      List<int> ganz(BigInt v) {
        var b = zahl(v).toList();
        while (b.length > 1 && b[0] == 0 && b[1] < 0x80) {
          b = b.sublist(1);
        }
        if (b[0] >= 0x80) b = [0, ...b];
        return [0x02, b.length, ...b];
      }

      final inhalt = [...ganz(sig.r), ...ganz(sig.s)];
      return Uint8List.fromList([0x30, inhalt.length, ...inhalt]);
    }

    return _Geraet._(
      {
        1: 2,
        3: -7,
        -1: 1,
        -2: zahl(oeffentlich.Q!.x!.toBigInteger()!),
        -3: zahl(oeffentlich.Q!.y!.toBigInteger()!),
      },
      unterschreibe,
      null,
    );
  }

  static Future<_Geraet> ed25519() async {
    final algo = kr.Ed25519();
    final paar = await algo.newKeyPair();
    final oeffentlich = await paar.extractPublicKey();
    return _Geraet._(
      {1: 1, 3: -8, -1: 6, -2: Uint8List.fromList(oeffentlich.bytes)},
      null,
      (daten) async =>
          Uint8List.fromList((await algo.sign(daten, keyPair: paar)).bytes),
    );
  }

  final Map<int, Object> cose;
  final Uint8List kennungRoh;
  final Uint8List Function(Uint8List)? _unterschreibe;
  final Future<Uint8List> Function(Uint8List)? _unterschreibeAsync;

  String get kennung => _b64(kennungRoh);

  Map<String, Object?> anlegen(
    Map<String, Object?> optionen,
    String origin, {
    int zaehler = 0,
  }) {
    final rp = (optionen['rp']! as Map)['id']! as String;
    final daten = BytesBuilder()
      ..add(sha256.convert(utf8.encode(rp)).bytes)
      ..addByte(0x45) // UP, UV, angehängte Schlüsseldaten
      ..add(_u32(zaehler))
      ..add(Uint8List(16)) // AAGUID
      ..add([kennungRoh.length >> 8, kennungRoh.length & 0xFF])
      ..add(kennungRoh)
      ..add(_cbor(cose));
    return {
      'id': kennung,
      'rawId': kennung,
      'type': 'public-key',
      'response': {
        'clientDataJSON': _client(
          'webauthn.create',
          optionen['challenge']! as String,
          origin,
        ),
        'attestationObject': _b64(
          _cbor({
            'fmt': 'none',
            'attStmt': <Object, Object>{},
            'authData': daten.toBytes(),
          }),
        ),
      },
    };
  }

  ({Uint8List daten, String client, Uint8List geraeteRoh}) _vorbereiten(
    Map<String, Object?> optionen,
    String origin,
    int merkmale,
    int zaehler,
  ) {
    final rp = optionen['rpId']! as String;
    final geraeteRoh = Uint8List.fromList([
      ...sha256.convert(utf8.encode(rp)).bytes,
      merkmale,
      ..._u32(zaehler),
    ]);
    final client = _client(
      'webauthn.get',
      optionen['challenge']! as String,
      origin,
    );
    final daten = Uint8List.fromList([
      ...geraeteRoh,
      ...sha256.convert(_ausB64(client)).bytes,
    ]);
    return (daten: daten, client: client, geraeteRoh: geraeteRoh);
  }

  Map<String, Object?> _antwort(
    String client,
    Uint8List geraeteRoh,
    Uint8List signatur,
    String konto,
  ) => {
    'id': kennung,
    'rawId': kennung,
    'type': 'public-key',
    'response': {
      'clientDataJSON': client,
      'authenticatorData': _b64(geraeteRoh),
      'signature': _b64(signatur),
      'userHandle': _b64(utf8.encode(konto)),
    },
  };

  Map<String, Object?> anmelden(
    Map<String, Object?> optionen,
    String origin, {
    int merkmale = 0x05,
    int zaehler = 0,
    bool verfaelschen = false,
    required String konto,
  }) {
    final v = _vorbereiten(optionen, origin, merkmale, zaehler);
    final sig = _unterschreibe!(v.daten);
    if (verfaelschen) sig[sig.length - 1] ^= 0x01;
    return _antwort(v.client, v.geraeteRoh, sig, konto);
  }

  Future<Map<String, Object?>> anmeldenAsync(
    Map<String, Object?> optionen,
    String origin, {
    int zaehler = 0,
    required String konto,
  }) async {
    final v = _vorbereiten(optionen, origin, 0x05, zaehler);
    return _antwort(
      v.client,
      v.geraeteRoh,
      await _unterschreibeAsync!(v.daten),
      konto,
    );
  }
}

String _client(String typ, String challenge, String origin) => _b64(
  utf8.encode(
    jsonEncode({
      'type': typ,
      'challenge': challenge,
      'origin': origin,
      'crossOrigin': false,
    }),
  ),
);

List<int> _u32(int v) => [
  v >> 24 & 0xFF,
  v >> 16 & 0xFF,
  v >> 8 & 0xFF,
  v & 0xFF,
];

Uint8List _cbor(Object? wert) {
  final aus = BytesBuilder();
  void kopf(int art, int n) {
    if (n < 24) {
      aus.addByte(art << 5 | n);
    } else if (n < 256) {
      aus
        ..addByte(art << 5 | 24)
        ..addByte(n);
    } else {
      aus
        ..addByte(art << 5 | 25)
        ..addByte(n >> 8)
        ..addByte(n & 0xFF);
    }
  }

  void schreibe(Object? v) {
    switch (v) {
      case int i when i >= 0:
        kopf(0, i);
      case int i:
        kopf(1, -1 - i);
      case Uint8List b:
        kopf(2, b.length);
        aus.add(b);
      case String s:
        final u = utf8.encode(s);
        kopf(3, u.length);
        aus.add(u);
      case Map m:
        kopf(5, m.length);
        for (final e in m.entries) {
          schreibe(e.key);
          schreibe(e.value);
        }
      default:
        throw ArgumentError('$v');
    }
  }

  schreibe(wert);
  return aus.toBytes();
}

String _b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');

Uint8List _ausB64(String s) =>
    base64Url.decode(s.padRight((s.length + 3) ~/ 4 * 4, '='));
