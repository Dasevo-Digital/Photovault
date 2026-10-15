import 'dart:convert';
import 'dart:io';

import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class _Verbindung implements HttpConnectionInfo {
  _Verbindung(String adresse) : remoteAddress = InternetAddress(adresse);
  @override
  final InternetAddress remoteAddress;
  @override
  int get localPort => 8790;
  @override
  int get remotePort => 40000;
}

/// Das erste Konto aus der App und die Konten in der Hand des Verwalters.
void main() {
  // Private Adressen als Zahlen – im Text sähen sie aus wie ein echtes Netz.
  String v4(int a, int b, int c, int d) => '$a.$b.$c.$d';
  final heim = v4(192, 168, 1, 20);
  final proxy = v4(192, 168, 1, 2);
  const draussen = '203.0.113.9';

  late Directory ordner;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late Handler api;

  void baue({bool totp = false, List<String> vertraut = const []}) {
    konten = Kontodienst(
      sdb,
      Tresorschluessel(List.filled(32, 7)),
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: totp,
    );
    api = baueApi(
      konten: konten,
      bibliotheken: bibliotheken,
      absender: Absender(vertraut),
    );
  }

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_konten_');
    sdb = Serverdatenbank.imSpeicher();
    bibliotheken = Bibliotheken(
      wurzel: Directory('${ordner.path}/bibliotheken'),
      eingang: Directory('${ordner.path}/eingang'),
      ruhe: Duration.zero,
      selbst: const {},
    );
    baue();
  });
  tearDown(() async {
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  Future<(int, Map<String, Object?>)> frag(
    String methode,
    String pfad, {
    String? von,
    String? token,
    Object? inhalt,
    Map<String, String> kopf = const {},
  }) async {
    final r = await api(
      Request(
        methode,
        Uri.parse('http://server/api/v1/$pfad'),
        headers: {
          'authorization': ?(token == null ? null : 'Bearer $token'),
          ...kopf,
        },
        body: inhalt == null ? null : jsonEncode(inhalt),
        context: {'shelf.io.connection_info': _Verbindung(von ?? heim)},
      ),
    );
    final text = await r.readAsString();
    return (
      r.statusCode,
      text.isEmpty
          ? <String, Object?>{}
          : (jsonDecode(text) as Map).cast<String, Object?>(),
    );
  }

  Map<String, Object?> erstes([String name = 'erika']) => {
    'name': name,
    'passwort': 'ein langes passwort',
    'geraet': 'Rechner',
  };

  group('Ersteinrichtung', () {
    test(
      'aus dem Heimnetz: angeboten, angelegt, Verwalter, danach zu',
      () async {
        expect((await frag('GET', 'zustand')).$2['einrichten'], isTrue);
        final (status, j) = await frag('POST', 'einrichten', inhalt: erstes());
        expect(status, 200);
        expect(j['token'], isA<String>());
        expect(konten.kontoNamens('erika')!.verwalter, isTrue);

        expect(
          (await frag('GET', 'zustand')).$2.containsKey('einrichten'),
          isFalse,
        );
        final (zweites, _) = await frag(
          'POST',
          'einrichten',
          inhalt: erstes('max'),
        );
        expect(zweites, 409);
        expect(konten.alle(), hasLength(1));
      },
    );

    test('mit TOTP-Pflicht folgt die Einrichtung wie beim Anmelden', () async {
      baue(totp: true);
      final (status, j) = await frag('POST', 'einrichten', inhalt: erstes());
      expect(status, 200);
      expect(j['schritt'], 'totp_einrichten');
      expect(j['token'], isNull);
    });

    test('von aussen nicht – auch nicht über einen fremden Proxy', () async {
      expect(
        (await frag(
          'GET',
          'zustand',
          von: draussen,
        )).$2.containsKey('einrichten'),
        isFalse,
      );
      expect(
        (await frag('POST', 'einrichten', von: draussen, inhalt: erstes())).$1,
        403,
      );
      // Ein Proxy im Heimnetz, dem der Server nicht traut: Dahinter kann
      // jeder stehen.
      expect(
        (await frag(
          'POST',
          'einrichten',
          von: proxy,
          kopf: {'x-forwarded-for': draussen},
          inhalt: erstes(),
        )).$1,
        403,
      );
      expect(konten.eingerichtet, isFalse);
    });

    test('hinter dem vertrauten Proxy zählt der Absender dahinter', () async {
      baue(vertraut: [proxy]);
      expect(
        (await frag(
          'POST',
          'einrichten',
          von: proxy,
          kopf: {'x-forwarded-for': draussen},
          inhalt: erstes(),
        )).$1,
        403,
      );
      final (status, _) = await frag(
        'POST',
        'einrichten',
        von: proxy,
        kopf: {'x-forwarded-for': v4(10, 8, 0, 5)},
        inhalt: erstes(),
      );
      expect(status, 200, reason: 'aus dem VPN im Heimnetz');
    });

    test('zwei zugleich: nur einer bekommt den Server', () async {
      final antworten = await Future.wait([
        frag('POST', 'einrichten', inhalt: erstes('erika')),
        frag('POST', 'einrichten', inhalt: erstes('max')),
      ]);
      expect(antworten.map((a) => a.$1).toList()..sort(), [200, 409]);
      expect(konten.alle(), hasLength(1));
    });

    test(
      'ein schlechter Name oder ein kurzes Passwort legt nichts an',
      () async {
        expect(
          (await frag(
            'POST',
            'einrichten',
            inhalt: {'name': 'x', 'passwort': 'ein langes passwort'},
          )).$1,
          400,
        );
        expect(
          (await frag(
            'POST',
            'einrichten',
            inhalt: {'name': 'erika', 'passwort': 'kurz'},
          )).$1,
          400,
        );
        expect(konten.eingerichtet, isFalse);
      },
    );
  });

  group('Konten in der Hand des Verwalters', () {
    late String verwalter;

    Future<String> anmelden(String name, String passwort) async {
      final (status, j) = await frag(
        'POST',
        'anmelden',
        inhalt: {'name': name, 'passwort': passwort, 'geraet': 'Telefon'},
      );
      expect(status, 200, reason: '$j');
      return j['token']! as String;
    }

    setUp(() async {
      await frag('POST', 'einrichten', inhalt: erstes());
      verwalter = await anmelden('erika', 'ein langes passwort');
    });

    test('anlegen, auflisten – und nur der Verwalter darf das', () async {
      final (status, neu) = await frag(
        'POST',
        'konten',
        token: verwalter,
        inhalt: {'name': 'max', 'passwort': 'noch ein passwort'},
      );
      expect(status, 201);
      expect((neu['name'], neu['verwalter']), ('max', false));
      expect(
        (await frag(
          'POST',
          'konten',
          token: verwalter,
          inhalt: {'name': 'Max', 'passwort': 'noch ein passwort'},
        )).$1,
        409,
        reason: 'Namen ohne Rücksicht auf Gross und klein',
      );

      final (_, liste) = await frag('GET', 'konten', token: verwalter);
      final eintraege = (liste['konten']! as List).cast<Map>();
      expect(
        [for (final k in eintraege) (k['name'], k['du'])],
        [('erika', true), ('max', false)],
      );

      final max = await anmelden('max', 'noch ein passwort');
      expect((await frag('GET', 'konten', token: max)).$1, 403);
      expect(
        (await frag(
          'POST',
          'konten',
          token: max,
          inhalt: {'name': 'eve', 'passwort': 'noch ein passwort'},
        )).$1,
        403,
      );
    });

    test('Passwort neu setzen meldet die Geräte ab', () async {
      final (_, neu) = await frag(
        'POST',
        'konten',
        token: verwalter,
        inhalt: {'name': 'max', 'passwort': 'noch ein passwort'},
      );
      final max = await anmelden('max', 'noch ein passwort');
      final id = neu['id']! as String;
      expect(
        (await frag(
          'POST',
          'konten/$id/passwort',
          token: verwalter,
          inhalt: {'neu': 'ein ganz neues passwort'},
        )).$1,
        200,
      );
      expect((await frag('GET', 'konto', token: max)).$1, 401);
      await anmelden('max', 'ein ganz neues passwort');
      expect(
        (await frag(
          'POST',
          'konten/$id/totp-zuruecksetzen',
          token: verwalter,
        )).$1,
        200,
      );
      expect(
        (await frag('POST', 'konten/$id/entsperren', token: verwalter)).$1,
        200,
      );
    });

    test(
      'entfernen legt die Bibliothek beiseite; das eigene Konto nie',
      () async {
        final (_, neu) = await frag(
          'POST',
          'konten',
          token: verwalter,
          inhalt: {'name': 'max', 'passwort': 'noch ein passwort'},
        );
        final id = neu['id']! as String;
        final max = await anmelden('max', 'noch ein passwort');
        await bibliotheken.fuer(id);

        final eigenes = konten.kontoNamens('erika')!.id;
        expect(
          (await frag('DELETE', 'konten/$eigenes', token: verwalter)).$1,
          409,
        );
        expect(
          (await frag(
            'POST',
            'konten/$eigenes/passwort',
            token: verwalter,
            inhalt: {'neu': 'ein ganz neues passwort'},
          )).$1,
          409,
        );

        final (status, j) = await frag(
          'DELETE',
          'konten/$id',
          token: verwalter,
        );
        expect(status, 200);
        expect(j['bibliothekBeiseite'], isTrue);
        expect(konten.konto(id), isNull);
        expect((await frag('GET', 'konto', token: max)).$1, 401);
        final ordnerNamen = [
          for (final e in Directory('${ordner.path}/bibliotheken').listSync())
            e.uri.pathSegments.where((s) => s.isNotEmpty).last,
        ];
        expect(
          ordnerNamen.where((n) => n.startsWith('$id.entfernt-')),
          hasLength(1),
        );
        expect(ordnerNamen, isNot(contains(id)));
        expect((await frag('DELETE', 'konten/$id', token: verwalter)).$1, 404);
      },
    );
  });
}
