import 'dart:io';

import 'package:photo_vault_server/src/absender.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

/// `X-Forwarded-Host` und `X-Forwarded-Proto` gelten nur von einem
/// vertrauten Proxy (#401).
///
/// Über einen echten HTTP-Server, nicht mit einer gebauten `Request`:
/// Der Fehler sass in dart:io, das `requestedUri` selbst aus diesen Köpfen
/// baut – gleich wer sie schickt. Freigabe-Links bekamen so die Adresse
/// eines beliebigen Absenders, und ein Cookie trug `Secure`, obwohl die
/// Verbindung unverschlüsselt war.
void main() {
  Future<(String, bool)> frage(
    Absender absender,
    Map<String, String> kopf,
  ) async {
    final server = await shelf_io.serve(
      (Request r) =>
          Response.ok('${absender.herkunft(r)}|${absender.verschluesselt(r)}'),
      InternetAddress.loopbackIPv4,
      0,
    );
    final client = HttpClient();
    try {
      final anfrage = await client.get('127.0.0.1', server.port, '/');
      kopf.forEach(anfrage.headers.set);
      final antwort = await anfrage.close();
      final text = await antwort.transform(systemEncoding.decoder).join();
      final teile = text.split('|');
      return (teile[0], teile[1] == 'true');
    } finally {
      client.close(force: true);
      await server.close(force: true);
    }
  }

  const fremd = {
    'x-forwarded-host': 'boese.test',
    'x-forwarded-proto': 'https',
  };

  test('ohne vertrauten Proxy zählen die Köpfe nicht', () async {
    final (herkunft, sicher) = await frage(Absender(), fremd);
    expect(herkunft, startsWith('http://127.0.0.1:'));
    expect(herkunft, isNot(contains('boese.test')));
    expect(sicher, isFalse);
  });

  test('nur Proto, nur Host – einzeln ebenso wenig', () async {
    final (h1, s1) = await frage(Absender(), {'x-forwarded-proto': 'https'});
    expect(h1, startsWith('http://127.0.0.1:'));
    expect(s1, isFalse);
    final (h2, s2) = await frage(Absender(), {'x-forwarded-host': 'x.test'});
    expect(h2, startsWith('http://127.0.0.1:'));
    expect(s2, isFalse);
  });

  test('vom vertrauten Proxy gelten sie', () async {
    final (herkunft, sicher) = await frage(Absender(['127.0.0.1']), {
      'x-forwarded-host': 'fotos.example',
      'x-forwarded-proto': 'https',
    });
    expect(herkunft, 'https://fotos.example');
    expect(sicher, isTrue);
  });

  test('vertrauter Proxy ohne Proto: Host gilt, Schema https', () async {
    final (herkunft, sicher) = await frage(Absender(['127.0.0.1']), {
      'x-forwarded-host': 'fotos.example',
    });
    expect(herkunft, 'https://fotos.example');
    expect(sicher, isFalse, reason: 'Secure nur, wenn der Proxy es sagt');
  });

  test('vertrauter Proxy mit nur Proto: eigener Host', () async {
    final (herkunft, sicher) = await frage(Absender(['127.0.0.1']), {
      'x-forwarded-proto': 'https',
    });
    expect(herkunft, startsWith('https://127.0.0.1:'));
    expect(sicher, isTrue);
  });

  test('ohne Köpfe: die Verbindung selbst', () async {
    final (herkunft, sicher) = await frage(Absender(['127.0.0.1']), {});
    expect(herkunft, startsWith('http://127.0.0.1:'));
    expect(sicher, isFalse);
  });
}
