import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/server_eigenes_konto_screen.dart';

/// „Mein Konto“ am Rechner (Issue #110): Geräte, Passwort und die
/// Verknüpfung mit dem Anbieter – wie in Browser und Handy.
void main() {
  late List<String> anfragen;
  late List<Map<String, Object?>> geraete;
  late bool oidc;

  setUp(() {
    anfragen = [];
    oidc = true;
    geraete = [
      {'id': 'g1', 'name': 'Rechner', 'zuletzt': '2026-10-19T08:00:00Z'},
      {
        'id': 'g2',
        'name': 'iPhone',
        'zuletzt': '2026-10-18T19:30:00Z',
        'adresse': '198.51.100.7',
      },
    ];
  });

  Serververbindung verbindung() => Serververbindung(
    Uri.parse('http://server/'),
    'token',
    client: MockClient((r) async {
      anfragen.add('${r.method} ${r.url.path}');
      http.Response json(Object o) => http.Response(
        jsonEncode(o),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
      return switch ((r.method, r.url.path)) {
        ('GET', '/api/v1/konto') => json({
          'name': 'erika',
          'verwalter': true,
          'totp': true,
          'oidc': <String>[],
          'geraet': 'g1',
        }),
        ('GET', '/api/v1/geraete') => json({'geraete': geraete}),
        ('GET', '/api/v1/zustand') => json({
          'protokoll': 2,
          'anmeldung': {'totp': true, 'oidc': oidc},
        }),
        ('DELETE', '/api/v1/geraete/g2') => () {
          geraete.removeWhere((g) => g['id'] == 'g2');
          return http.Response('', 204);
        }(),
        ('POST', '/api/v1/konto/passwort') => () {
          final k = jsonDecode(r.body) as Map;
          expect(k['code'], '123456', reason: 'mit TOTP der Code');
          return json({'ok': true});
        }(),
        _ => http.Response('nicht da', 404),
      };
    }),
  );

  Future<AppTexte> zeige(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: ServerEigenesKontoScreen(verbindung: verbindung()),
      ),
    );
    await tester.pumpAndSettle();
    return AppTexte.of(tester.element(find.byType(ServerEigenesKontoScreen)));
  }

  testWidgets('Konto, Geräte, ein anderes Gerät abmelden', (tester) async {
    final t = await zeige(tester);
    expect(
      find.text(
        'erika · ${t.serverKontoVerwalter} · '
        '${t.serverKontoMitTotp}',
      ),
      findsOneWidget,
    );
    expect(find.text('Rechner (${t.serverDiesesGeraet})'), findsOneWidget);
    expect(find.text('iPhone'), findsOneWidget);
    expect(find.textContaining('198.51.100.7'), findsOneWidget);
    // Nur das andere Gerät hat einen Knopf – dieser Rechner geht über
    // „Trennen“.
    expect(find.text(t.serverGeraetAbmelden), findsOneWidget);
    await tester.tap(find.text(t.serverGeraetAbmelden));
    await tester.pumpAndSettle();
    expect(find.text(t.serverGeraetAbmeldenFrage('iPhone')), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, t.serverGeraetAbmelden));
    await tester.pumpAndSettle();
    expect(anfragen, contains('DELETE /api/v1/geraete/g2'));
    expect(find.text('iPhone'), findsNothing);
  });

  testWidgets('Passwort ändern: mit Code, ungleich wird abgefangen', (
    tester,
  ) async {
    final t = await zeige(tester);
    await tester.tap(find.text(t.serverPasswortAendern));
    await tester.pumpAndSettle();
    final felder = find.byType(TextField);
    expect(felder, findsNWidgets(4), reason: 'alt, neu, neu, Code');
    await tester.enterText(felder.at(0), 'alt passwort 1');
    await tester.enterText(felder.at(1), 'ein neues langes passwort');
    await tester.enterText(felder.at(2), 'ein anderes langes passwort');
    await tester.tap(find.text(t.serverAendern));
    await tester.pumpAndSettle();
    expect(find.text(t.serverPasswortUngleich), findsOneWidget);
    expect(anfragen, isNot(contains('POST /api/v1/konto/passwort')));
    await tester.enterText(felder.at(2), 'ein neues langes passwort');
    await tester.enterText(felder.at(3), '123456');
    await tester.tap(find.text(t.serverAendern));
    await tester.pumpAndSettle();
    expect(anfragen, contains('POST /api/v1/konto/passwort'));
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('die Verknüpfung steht nur da, wo der Server einen Anbieter '
      'kennt', (tester) async {
    var t = await zeige(tester);
    expect(find.text(t.serverOidcTitel), findsOneWidget);
    expect(find.text(t.serverOidcNicht), findsOneWidget);
    expect(find.text(t.serverOidcVerknuepfen), findsOneWidget);

    oidc = false;
    await tester.pumpWidget(const SizedBox());
    t = await zeige(tester);
    expect(find.text(t.serverOidcTitel), findsNothing);
  });
}
