import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kern/abgleich/kachelumleitung.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

/// Kartenkacheln über den eigenen Server (#180): Rechner und Handy lenken
/// die Abrufe von OpenStreetMap und OpenTopoMap zu ihm um, sobald er es
/// kann – und nur diese. Die Adresse der Kachel bleibt dabei die des
/// Anbieters, damit der Kachelspeicher auf der Platte für beide Wege gilt.
void main() {
  final server = Serververbindung(
    Uri.parse('http://heimserver.test/fotos'),
    'pv1_geheim',
  );

  group('Kachelumleitung', () {
    late _Fang fang;
    late Serververbindung? ziel;
    late Kachelumleitung netz;

    setUp(() {
      fang = _Fang();
      ziel = server;
      netz = Kachelumleitung(fang, server: () => ziel);
    });

    test('OSM und OpenTopoMap gehen zum Server, mit Token', () async {
      await netz.get(
        Uri.parse('https://tile.openstreetmap.org/3/4/2.png#2'),
        headers: {'User-Agent': 'flutter_map (PhotoVault)'},
      );
      await netz.get(Uri.parse('https://tile.opentopomap.org/17/1/131071.png'));
      expect(fang.adressen, [
        'http://heimserver.test/fotos/api/v1/karte/osm/3/4/2.png',
        'http://heimserver.test/fotos/api/v1/karte/topo/17/1/131071.png',
      ]);
      expect(fang.anfragen.first.headers['authorization'], 'Bearer pv1_geheim');
      expect(
        fang.anfragen.first.headers['user-agent'],
        'flutter_map (PhotoVault)',
      );
    });

    test('alles andere geht unverändert und ohne Token weiter', () async {
      for (final adresse in [
        // CARTO trägt den eigenen Schlüssel – der gehört nicht zum Server.
        'https://a.basemaps.cartocdn.com/dark_all/3/4/2.png?key=abc',
        // Die eigene Kartenquelle.
        'https://kacheln.beispiel.test/3/4/2.png',
        'https://tile.openstreetmap.org/copyright',
        'https://tile.openstreetmap.org/3/4/2.png?x=1',
      ]) {
        await netz.get(Uri.parse(adresse));
        expect(fang.adressen.last, adresse);
        expect(fang.anfragen.last.headers['authorization'], isNull);
      }
      await netz.post(Uri.parse('https://tile.openstreetmap.org/3/4/2.png'));
      expect(fang.anfragen.last.url.host, 'tile.openstreetmap.org');

      // Ohne Server (lokale Bibliothek, Server bis 3.66) direkt.
      ziel = null;
      await netz.get(Uri.parse('https://tile.openstreetmap.org/3/4/2.png'));
      expect(fang.adressen.last, 'https://tile.openstreetmap.org/3/4/2.png');
      expect(fang.anfragen.last.headers['authorization'], isNull);
    });

    test('der Abbruch der Karte schlägt durch', () async {
      final abbruch = Completer<void>();
      await netz.send(
        http.AbortableRequest(
          'GET',
          Uri.parse('https://tile.openstreetmap.org/3/4/2.png'),
          abortTrigger: abbruch.future,
        ),
      );
      final umgelenkt = fang.anfragen.single;
      expect(umgelenkt, isA<http.Abortable>());
      expect((umgelenkt as http.Abortable).abortTrigger, same(abbruch.future));
    });

    test(
      'kommt der Server nicht an die Kachel, ist es wie kein Netz',
      () async {
        fang.status = 502;
        await expectLater(
          netz.get(Uri.parse('https://tile.openstreetmap.org/3/4/2.png')),
          throwsA(isA<http.ClientException>()),
        );
        // Abgemeldet oder Token abgelaufen: ebenso, damit am Rechner die
        // Kopie auf der Platte greift statt einer leeren Karte.
        for (final s in [401, 403]) {
          fang.status = s;
          await expectLater(
            netz.get(Uri.parse('https://tile.openstreetmap.org/3/4/2.png')),
            throwsA(isA<http.ClientException>()),
            reason: '$s',
          );
        }
        // Eine echte Antwort bleibt eine: 404 heisst, die Kachel gibt es
        // nicht (oder OpenTopoMap rendert sie noch).
        fang.status = 404;
        final r = await netz.get(
          Uri.parse('https://tile.openstreetmap.org/3/4/2.png'),
        );
        expect(r.statusCode, 404);
      },
    );

    test('nur ein Server mit `funktionen.karte` liefert Kacheln', () {
      expect(
        serverLiefertKacheln({
          'funktionen': {'karte': 1},
        }),
        isTrue,
      );
      expect(
        serverLiefertKacheln({
          'funktionen': {'karte': 0},
        }),
        isFalse,
      );
      expect(
        serverLiefertKacheln({
          'funktionen': {'fotokammer': 4},
        }),
        isFalse,
      );
      expect(serverLiefertKacheln({}), isFalse);
    });
  });

  test('am Rechner läuft der gemeinsame Kachelweg über den Server, sobald '
      'er gesetzt ist', () async {
    // Ein eigener Server auf dieser Maschine – flutter_test schöbe sonst
    // einen Ersatz unter, der jede Anfrage mit 400 beantwortet.
    HttpOverrides.global = null;
    final gesehen = <(String, String?)>[];
    final heim = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      heim.forEach((anfrage) async {
        gesehen.add((
          anfrage.uri.path,
          anfrage.headers.value(HttpHeaders.authorizationHeader),
        ));
        anfrage.response.headers.contentType = ContentType('image', 'png');
        anfrage.response.add([0x89, 0x50, 0x4E, 0x47]);
        await anfrage.response.close();
      }),
    );
    addTearDown(() async {
      setzeKachelserver(null);
      await heim.close(force: true);
    });

    setzeKachelserver(
      Serververbindung(
        Uri.parse('http://127.0.0.1:${heim.port}/'),
        'pv1_rechner',
      ),
    );
    final r = await kachelNetzClient().get(
      Uri.parse('https://tile.openstreetmap.org/5/16/10.png'),
    );
    expect(r.statusCode, 200);
    expect(gesehen, [('/api/v1/karte/osm/5/16/10.png', 'Bearer pv1_rechner')]);
  });
}

/// Fängt jede Anfrage und antwortet mit [status].
class _Fang extends http.BaseClient {
  final anfragen = <http.BaseRequest>[];
  var status = 200;

  List<String> get adressen => [for (final a in anfragen) '${a.url}'];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest anfrage) async {
    anfragen.add(anfrage);
    return http.StreamedResponse(const Stream.empty(), status);
  }
}
