import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/retry.dart';
import 'package:http/testing.dart';
import 'package:photo_vault/services/kachelmitschnitt.dart';

Kachelabruf abruf({
  String adresse = 'https://tile.openstreetmap.org/8/134/85.png',
  int? status = 200,
  String? fehler,
  int bytes = 1000,
  bool dauerverbindung = true,
  bool abgebrochen = false,
  Duration dauer = const Duration(milliseconds: 90),
}) =>
    Kachelabruf(
      zeit: DateTime(2026, 8, 28),
      adresse: adresse,
      dauer: dauer,
      status: status,
      fehler: fehler,
      bytes: bytes,
      dauerverbindung: dauerverbindung,
      abgebrochen: abgebrochen,
    );

String kachelAdresse(int z, int x, int y) =>
    'https://tile.openstreetmap.org/$z/$x/$y.png';

void main() {
  group('bilanzAus', () {
    test('leer bleibt leer und teilt nicht durch null', () {
      final b = bilanzAus(const []);
      expect(b.abrufe, 0);
      expect(b.verbindungenJeAbruf, 0);
      expect(b.abrufeJeAdresse, 0);
      expect(b.mittlereDauer, Duration.zero);
    });

    test('trennt Abrufe, Adressen und Verbindungen – die drei Zahlen der Frage', () {
      // Zehn Abrufe auf fünf verschiedene Kacheln, dabei zwanzig
      // Verbindungen: Das ist genau die Lage, die von aussen nicht zu
      // unterscheiden war.
      final b = bilanzAus(
        [
          for (var i = 0; i < 5; i++) ...[
            abruf(adresse: kachelAdresse(8, 134, i)),
            abruf(adresse: kachelAdresse(8, 134, i)),
          ],
        ],
        verbindungen: 20,
      );
      expect(b.abrufe, 10);
      expect(b.adressen, 5);
      expect(b.wiederholte, 5);
      expect(b.abrufeJeAdresse, 2.0);
      expect(b.verbindungenJeAbruf, 2.0);
    });

    test('zählt Statuscodes und Fehler getrennt, das Häufigste zuerst', () {
      final b = bilanzAus([
        abruf(status: 200),
        abruf(status: 404, adresse: kachelAdresse(8, 1, 1)),
        abruf(status: 404, adresse: kachelAdresse(8, 1, 2)),
        abruf(status: 404, adresse: kachelAdresse(8, 1, 3)),
        abruf(status: 500, adresse: kachelAdresse(8, 1, 4)),
        abruf(status: null, fehler: 'SocketException: Verbindung abgelehnt'),
      ]);
      expect(b.abrufe, 6);
      expect(b.geglueckt, 1);
      expect(b.fehlgeschlagen, 5);
      expect(b.abgebrochen, 0);
      expect(b.nachStatus.keys.first, 404);
      expect(b.nachStatus, {404: 3, 200: 1, 500: 1});
      expect(b.nachFehler, {'SocketException: Verbindung abgelehnt': 1});
    });

    test('hält fest, wie oft der Server die Verbindung zumachen wollte', () {
      // Der Verdacht, den nur diese Spalte belegen oder entkräften kann:
      // Wer nach jeder Kachel schliesst, erzwingt für die nächste einen
      // neuen Handschlag.
      final b = bilanzAus([
        abruf(dauerverbindung: false),
        abruf(dauerverbindung: false, adresse: kachelAdresse(8, 2, 1)),
        abruf(adresse: kachelAdresse(8, 2, 2)),
      ]);
      expect(b.ohneDauerverbindung, 2);
    });

    test('mittlere und längste Dauer, Bytes', () {
      final b = bilanzAus([
        abruf(dauer: const Duration(milliseconds: 100), bytes: 1000),
        abruf(dauer: const Duration(milliseconds: 300), bytes: 2000),
      ]);
      expect(b.mittlereDauer, const Duration(milliseconds: 200));
      expect(b.laengsteDauer, const Duration(milliseconds: 300));
      expect(b.bytes, 3000);
    });
  });

  group('Kachelabruf.kachel', () {
    test('kürzt die Adresse auf Stufe/x/y', () {
      expect(abruf(adresse: kachelAdresse(14, 8623, 5487)).kachel, '14/8623/5487');
      expect(
        abruf(adresse: 'https://tile.opentopomap.org/5/16/10.png').kachel,
        '5/16/10',
      );
    });

    test('lässt stehen, was nicht auf das Muster passt', () {
      expect(abruf(adresse: 'https://example.org/kachel').kachel,
          'https://example.org/kachel');
    });
  });

  group('fehlertext', () {
    test('nimmt der Meldung die Adresse, damit sich Fehler häufen können', () {
      // Ohne diese Kürzung wäre jeder Fehler einzigartig – und eine
      // Häufung von hundert gleichen Fehlern sähe aus wie hundert
      // verschiedene.
      final a = fehlertext(ClientException(
          'Connection closed', Uri.parse(kachelAdresse(8, 1, 1))));
      final b = fehlertext(ClientException(
          'Connection closed', Uri.parse(kachelAdresse(8, 1, 2))));
      expect(a, b);
      expect(a, contains('ClientException'));
    });

    test('behält den Typ, wenn die Meldung leer ist', () {
      expect(fehlertext(const FormatException('')), contains('FormatException'));
    });
  });

  group('Kachelmitschnitt', () {
    test('schreibt nichts mit, solange er nicht läuft', () {
      final m = Kachelmitschnitt();
      m.notiere(abruf());
      m.verbindungGeoeffnet();
      expect(m.eintraege, isEmpty);
      expect(m.bilanz.verbindungen, 0);
    });

    test('starten wirft den vorigen Durchgang weg', () {
      final m = Kachelmitschnitt()..starte();
      m.notiere(abruf());
      expect(m.eintraege, hasLength(1));
      m.starte();
      expect(m.eintraege, isEmpty);
      expect(m.bilanz.verbindungen, 0);
    });

    test('bei Überlauf fallen die ältesten heraus und werden gezählt', () {
      final m = Kachelmitschnitt()..starte();
      for (var i = 0; i < kachelMitschnittGrenze + 7; i++) {
        m.notiere(abruf(adresse: kachelAdresse(8, i, 0)));
      }
      expect(m.eintraege, hasLength(kachelMitschnittGrenze));
      expect(m.bilanz.verworfen, 7);
      // Die ältesten sind weg, nicht die neuesten.
      expect(m.eintraege.first.adresse, kachelAdresse(8, 7, 0));
      expect(m.eintraege.last.adresse,
          kachelAdresse(8, kachelMitschnittGrenze + 6, 0));
    });
  });

  group('MitschnittClient', () {
    test('reicht die Antwort unverändert durch', () async {
      final m = Kachelmitschnitt()..starte();
      final client = MitschnittClient(
        MockClient((_) async => Response('Kacheldaten', 200,
            headers: {'content-type': 'image/png'})),
        m,
      );
      final antwort = await client.get(Uri.parse(kachelAdresse(8, 1, 1)));
      expect(antwort.statusCode, 200);
      expect(antwort.body, 'Kacheldaten');
      expect(antwort.headers['content-type'], 'image/png');
    });

    test('notiert Status, Bytes und Adresse', () async {
      final m = Kachelmitschnitt()..starte();
      final client = MitschnittClient(
        MockClient((_) async => Response('12345', 200)),
        m,
      );
      await client.get(Uri.parse(kachelAdresse(8, 134, 85)));
      expect(m.eintraege, hasLength(1));
      expect(m.eintraege.single.status, 200);
      expect(m.eintraege.single.bytes, 5);
      expect(m.eintraege.single.kachel, '8/134/85');
      expect(m.bilanz.geglueckt, 1);
    });

    test('eine geworfene Ausnahme steht als Eintrag da und wird weitergereicht',
        () async {
      final m = Kachelmitschnitt()..starte();
      final client = MitschnittClient(
        MockClient((anfrage) async =>
            throw ClientException('kein Netz', anfrage.url)),
        m,
      );
      await expectLater(
        client.get(Uri.parse(kachelAdresse(8, 1, 1))),
        throwsA(isA<ClientException>()),
      );
      expect(m.eintraege.single.status, isNull);
      expect(m.eintraege.single.fehler, contains('ClientException'));
      expect(m.bilanz.fehlgeschlagen, 1);
      expect(m.bilanz.abgebrochen, 0);
    });

    test('schreibt nichts mit, wenn der Mitschnitt aus ist', () async {
      final m = Kachelmitschnitt();
      final client = MitschnittClient(
        MockClient((_) async => Response('x', 200)),
        m,
      );
      expect((await client.get(Uri.parse(kachelAdresse(8, 1, 1)))).body, 'x');
      expect(m.eintraege, isEmpty);
    });

    test('jeder Wiederholversuch ist ein eigener Eintrag', () async {
      // Die Reihenfolge der Schichten ist hier die Aussage: Sässe der
      // Mitschnitt ÜBER den Wiederholungen, stünde am Ende ein einziger
      // geglückter Abruf da – und die Wiederholungen wären unsichtbar,
      // obwohl sie einer der Verdächtigen sind.
      final m = Kachelmitschnitt()..starte();
      var nummer = 0;
      final client = RetryClient(
        MitschnittClient(
          MockClient((_) async {
            nummer++;
            return Response('x', nummer < 3 ? 503 : 200);
          }),
          m,
        ),
        retries: 2,
        delay: (_) => Duration.zero,
      );
      final antwort = await client.get(Uri.parse(kachelAdresse(8, 134, 85)));
      expect(antwort.statusCode, 200);
      expect(m.eintraege, hasLength(3));
      expect(m.eintraege.map((e) => e.status), [503, 503, 200]);
      // Die beiden verworfenen Rümpfe stehen als abgebrochen da – und
      // nicht etwa gar nicht.
      expect(m.eintraege.map((e) => e.abgebrochen), [true, true, false]);
      final b = m.bilanz;
      expect(b.abrufe, 3);
      expect(b.adressen, 1);
      expect(b.abrufeJeAdresse, 3.0);
      expect(b.wiederholte, 1);
      expect(b.abgebrochen, 2);
    });

    test('ein Abbruch beim Verbinden zählt als Abbruch, nicht als Fehlschlag',
        () async {
      // Der Normalfall einer Zoomfahrt: flutter_map bricht ab, was aus
      // dem Bild läuft. An echten Servern gemessen waren das 56 von 368
      // Abrufen – als Fehlschläge gezählt hätte die Übersicht eine
      // gesunde Fahrt als kaputt gemeldet.
      final m = Kachelmitschnitt()..starte();
      final client = MitschnittClient(
        MockClient((anfrage) async => throw ClientException(
            'Request aborted by `abortTrigger`', anfrage.url)),
        m,
      );
      await expectLater(
        client.get(Uri.parse(kachelAdresse(8, 1, 1))),
        throwsA(isA<ClientException>()),
      );
      expect(m.bilanz.abgebrochen, 1);
      expect(m.bilanz.fehlgeschlagen, 0);
    });

    test('eine weggezogene Kachel gilt als abgebrochen, nicht als geglückt',
        () async {
      // flutter_map bricht den Abruf ab, wenn die Kachel beim Ziehen aus
      // dem Bild läuft. Der Server hat mit 200 geantwortet, angekommen
      // ist trotzdem nichts.
      final m = Kachelmitschnitt()..starte();
      final client = MitschnittClient(
        MockClient.streaming((_, __) async => StreamedResponse(
              // Ein Strom, der nie fertig wird.
              StreamController<List<int>>().stream,
              200,
            )),
        m,
      );
      final antwort = await client.send(
          Request('GET', Uri.parse(kachelAdresse(8, 134, 85))));
      await antwort.stream.listen((_) {}).cancel();

      expect(m.eintraege.single.status, 200);
      expect(m.eintraege.single.abgebrochen, isTrue);
      expect(m.bilanz.abgebrochen, 1);
      expect(m.bilanz.geglueckt, 0);
      expect(m.bilanz.fehlgeschlagen, 0);
    });
  });
}
