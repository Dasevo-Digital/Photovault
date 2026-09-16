import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/io_client.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

/// Ein Server, der Verbindungen annimmt und schweigt – genau das, was ein
/// halboffenes TCP nach Ruhezustand oder Netzwechsel hinterlaesst.
Future<({ServerSocket server, List<Socket> offen, Uri ziel})> stummerServer() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final offen = <Socket>[];
  server.listen(offen.add);
  return (
    server: server,
    offen: offen,
    ziel: Uri.parse('http://127.0.0.1:${server.port}/12/2148/1370.png'),
  );
}

void main() {
  group('die Zeitgrenze im Kachelweg', () {
    test('ohne sie legen sechs schweigende Abrufe den ganzen Server still',
        () async {
      // Die Gegenprobe zur eigentlichen Behebung: Genau dieser Zustand
      // liess die Karte fuer den Rest der Sitzung grau bleiben.
      final s = await stummerServer();
      final roh = IOClient(kachelHttpClient());

      final fertig = <int>[];
      for (var i = 0; i < kachelVerbindungen; i++) {
        unawaited(roh.get(s.ziel).then<void>(
            (_) => fertig.add(i),
            onError: (Object _) => fertig.add(-1)));
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(s.offen, hasLength(kachelVerbindungen),
          reason: 'alle erlaubten Verbindungen sind belegt');
      expect(fertig, isEmpty);

      var siebterFertig = false;
      unawaited(roh.get(s.ziel).then<void>(
          (_) => siebterFertig = true,
          onError: (Object _) => siebterFertig = true));
      await Future<void>.delayed(const Duration(seconds: 5));
      expect(siebterFertig, isFalse,
          reason: 'der siebte Abruf wartet auf einen Platz, der nie frei wird');

      roh.close();
      for (final v in s.offen) {
        v.destroy();
      }
      await s.server.close();
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('mit ihr geben sich alle Abrufe nach der Frist geschlagen', () async {
      final s = await stummerServer();
      final client = ZeitgrenzeClient(IOClient(kachelHttpClient()),
          frist: const Duration(seconds: 3));

      final uhr = Stopwatch()..start();
      final ausgang = <String>[];
      await Future.wait([
        for (var i = 0; i < kachelVerbindungen + 4; i++)
          client
              .get(s.ziel)
              .then<void>((_) => ausgang.add('antwort'))
              .catchError((Object e) => ausgang.add('${e.runtimeType}'))
      ]).timeout(const Duration(seconds: 45), onTimeout: () {
        ausgang.add('haengt immer noch');
        return const [];
      });

      expect(ausgang, hasLength(kachelVerbindungen + 4));
      expect(ausgang.every((e) => e == 'ClientException'), isTrue,
          reason: 'jeder Abruf endet als Fehlschlag, nicht als Abbruch: $ausgang');
      expect(uhr.elapsed, lessThan(const Duration(seconds: 30)));

      client.close();
      for (final v in s.offen) {
        v.destroy();
      }
      await s.server.close();
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('und der Fehlschlag ist einer, den die Karte wiederholt', () {
      // Der Punkt der Uebersetzung: Ein RequestAbortedException waere fuer
      // flutter_map ein geplanter Abbruch – durchsichtige Kachel, kein
      // Fehler, kein neuer Versuch. Die Staffel aus [Kachelschicht] liefe
      // nie an.
      final fehler = ClientException(
          'Kachel nach 15 s ohne Antwort abgebrochen',
          Uri.parse('https://tile.openstreetmap.org/12/2148/1370.png'));
      expect(kachelFehlerNochmalVersuchen(fehler), isTrue);
    });

    test('der eigene Abbruch der Karte bleibt ein Abbruch', () async {
      // Kacheln, die beim Ziehen aus dem Bild laufen, bricht flutter_map
      // selbst ab. Die duerfen NICHT als Fehlschlag durchgehen, sonst
      // wiederholt die App Bilder, die niemand mehr sieht.
      final s = await stummerServer();
      final client = ZeitgrenzeClient(IOClient(kachelHttpClient()),
          frist: const Duration(seconds: 30));
      final ausloeser = Completer<void>();
      final lauf = client
          .send(AbortableRequest('GET', s.ziel, abortTrigger: ausloeser.future));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      ausloeser.complete();

      await expectLater(lauf, throwsA(isA<RequestAbortedException>()));

      client.close();
      for (final v in s.offen) {
        v.destroy();
      }
      await s.server.close();
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('eine gewoehnliche Antwort geht unveraendert durch', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(server.forEach((anfrage) async {
        anfrage.response
          ..statusCode = 200
          ..headers.set('content-type', 'image/png')
          ..add(List<int>.filled(4096, 7));
        await anfrage.response.close();
      }));
      final client = ZeitgrenzeClient(IOClient(kachelHttpClient()));
      final antwort = await client
          .get(Uri.parse('http://127.0.0.1:${server.port}/12/2148/1370.png'));
      expect(antwort.statusCode, 200);
      expect(antwort.bodyBytes, hasLength(4096));
      expect(antwort.headers['content-type'], 'image/png');
      client.close();
      await server.close(force: true);
    });

    test('ein langsamer, aber lebendiger Abruf ueberlebt', () async {
      // OpenTopoMap rendert Kacheln bei Bedarf und braucht dafuer
      // gemessene 1,7 s. Solche Abrufe duerfen nicht abgeschnitten
      // werden – nur die, bei denen gar nichts mehr kommt.
      //
      // Der Rumpf kommt dabei am Stueck an, nicht stueckweise: siehe die
      // Messung bei [kachelZeitgrenze]. Deshalb ist es hier die zweite
      // Uhr, die den ganzen Rumpf abdeckt, und nicht eine Frist je Stueck.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(server.forEach((anfrage) async {
        anfrage.response.statusCode = 200;
        for (var i = 0; i < 8; i++) {
          anfrage.response.add(List<int>.filled(128, 3));
          await anfrage.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        await anfrage.response.close();
      }));
      final client = ZeitgrenzeClient(IOClient(kachelHttpClient()),
          frist: const Duration(seconds: 8));
      final uhr = Stopwatch()..start();
      final antwort = await client
          .get(Uri.parse('http://127.0.0.1:${server.port}/12/2148/1370.png'));
      expect(antwort.bodyBytes, hasLength(8 * 128));
      expect(uhr.elapsed, greaterThan(const Duration(seconds: 1)),
          reason: 'der Abruf brauchte ueber eine Sekunde und kam trotzdem an');
      client.close();
      await server.close(force: true);
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('ein Rumpf, der mittendrin verstummt, laeuft in die Frist', () async {
      // Die Gegenprobe dazu: Kopfzeilen da, dann nichts mehr. Ohne die
      // zweite Uhr bliebe dieser Abruf fuer immer offen – und mit ihm die
      // Verbindung.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(server.forEach((anfrage) async {
        anfrage.response
          ..statusCode = 200
          ..contentLength = 4096
          ..add(List<int>.filled(64, 3));
        await anfrage.response.flush();
        // und dann fuer immer schweigen
      }));
      final client = ZeitgrenzeClient(IOClient(kachelHttpClient()),
          frist: const Duration(seconds: 2));
      final uhr = Stopwatch()..start();
      await expectLater(
        client.get(Uri.parse('http://127.0.0.1:${server.port}/12/2148/1370.png')),
        throwsA(isA<ClientException>()),
      );
      expect(uhr.elapsed, lessThan(const Duration(seconds: 15)));
      client.close();
      await server.close(force: true);
    }, timeout: const Timeout(Duration(minutes: 1)));
  });
}
