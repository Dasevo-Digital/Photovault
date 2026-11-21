import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/verbindung.dart';

/// Antwortet dort etwas, das kein JSON ist (ein fremder Webserver, ein
/// Proxy mit Fehlerseite), ist das ein [Serverfehler] – keine
/// FormatException, an der jede Meldung der Oberfläche vorbeigeht.
void main() {
  final server = Uri.parse('http://127.0.0.1:9/');
  const html = '<!doctype html><html><body>Willkommen</body></html>';
  final client = MockClient(
    (_) async => http.Response(
      html,
      200,
      headers: {'content-type': 'text/html; charset=utf-8'},
    ),
  );

  // SIC-099: Anmeldung.zustand las die Antwort als JSON, bevor es den
  // Status prüfte; der Bildschirm „Mit Server verbinden“ blieb ohne Meldung.
  test('zustand: ein fremder Webserver mit HTML', () async {
    await expectLater(
      Anmeldung(server, client: client).zustand(),
      throwsA(isA<Serverfehler>()),
    );
  });

  test('anmelden: HTML statt eines Anmeldeschritts', () async {
    await expectLater(
      Anmeldung(server, client: client).anmelden('a', 'b', geraet: 'c'),
      throwsA(isA<Serverfehler>()),
    );
  });

  // SIC-196: Beim Beitragen in ein geteiltes Album blieb das Fenster
  // „Lade 1 von 1 hoch …“ offen, weil die FormatException aus
  // Serververbindung._json nicht gefangen wurde.
  test('schicke: HTML statt JSON', () async {
    await expectLater(
      Serververbindung(server, 'probe', client: client).schicke('api/v1/x', {}),
      throwsA(isA<Serverfehler>()),
    );
  });

  test('schicke: JSON geht weiter durch', () async {
    final ok = MockClient((_) async => http.Response('{"a": 1}', 200));
    expect(
      await Serververbindung(server, 'probe', client: ok).schicke('x', {}),
      {'a': 1},
    );
    final nichts = MockClient((_) async => http.Response('null', 200));
    expect(
      await Serververbindung(server, 'probe', client: nichts).schicke('x', {}),
      {'wert': null},
    );
  });
}
