import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/passkey_anmeldung.dart';

/// Die Anmeldung mit Passkey auf einem Gerät (#277): Die App öffnet die
/// Seite des Servers, der Browser kehrt mit einem Code auf einen Port nur
/// auf diesem Gerät zurück, und die App löst ihn mit ihrem Prüfer ein.
/// Hier spielt der Test den Browser.
void main() {
  test('Seite öffnen, Rückkehr mit Code, einlösen mit Prüfer', () async {
    String? gesendeterPruefer;
    final client = MockClient((r) async {
      expect(r.url.path, '/api/v1/anmelden/passkey/einloesen');
      final k = jsonDecode(r.body) as Map;
      expect(k['code'], 'der-code');
      gesendeterPruefer = k['pruefer'] as String;
      return http.Response(jsonEncode({'token': 'pv1_neu'}), 200);
    });
    late Uri geoeffnet;
    late Future<String> seite;
    final s =
        await PasskeyAnmeldung(
          Uri.parse('https://fotos.example.de'),
          client: client,
        ).melde(
          geraet: 'Mein Telefon',
          antwort: 'Angemeldet.',
          oeffne: (adresse) async {
            geoeffnet = adresse;
            final q = adresse.queryParameters;
            // Der Browser, nachdem der Server den Passkey geprüft hat.
            final zurueck = Uri.parse(q['rueckweg']!).replace(
              queryParameters: {'code': 'der-code', 'zustand': q['zustand']!},
            );
            // Wie launchUrl: zurück, ohne auf den Browser zu warten.
            seite = () async {
              final c = HttpClient();
              final a = await (await c.getUrl(zurueck)).close();
              final text = await a.transform(utf8.decoder).join();
              c.close();
              return text;
            }();
          },
        );
    expect(await seite, contains('Angemeldet.'));
    expect(geoeffnet.host, 'fotos.example.de');
    expect(geoeffnet.path, '/app/passkey.html');
    expect(geoeffnet.queryParameters['geraet'], 'Mein Telefon');
    expect(Uri.parse(geoeffnet.queryParameters['rueckweg']!).host, '127.0.0.1');
    expect(s, isA<AnmeldungFertig>());
    expect((s! as AnmeldungFertig).token, 'pv1_neu');
    // Der Server prüft den Prüfer gegen den Prüfwert aus der Adresse.
    expect(
      base64Url
          .encode(sha256.convert(ascii.encode(gesendeterPruefer!)).bytes)
          .replaceAll('=', ''),
      geoeffnet.queryParameters['pruefwert'],
    );
  });

  test('ein falscher Zustand löst nichts ein', () async {
    final client = MockClient((r) async => fail('nichts einzulösen'));
    final s =
        await PasskeyAnmeldung(
          Uri.parse('https://fotos.example.de'),
          client: client,
        ).melde(
          geraet: 'x',
          antwort: '',
          oeffne: (adresse) async {
            final zurueck = Uri.parse(
              adresse.queryParameters['rueckweg']!,
            ).replace(queryParameters: {'code': 'c', 'zustand': 'fremd'});
            unawaited(() async {
              final c = HttpClient();
              await (await c.getUrl(zurueck)).close();
              c.close();
            }());
          },
        );
    expect(s, isNull);
  });
}
