import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/eigenes_konto.dart';

/// Die Verknüpfung mit dem Anbieter auf dem Telefon (#182) – wie am
/// Rechner: Der Browser kehrt über den Server auf einen Port nur auf diesem
/// Telefon zurück, die App löst den Code mit ihrem Prüfer ein.
void main() {
  late List<String> anbieter;
  late bool oidc;
  late Map<String, Object?> start;
  late Map<String, Object?> einloesung;

  setUp(() {
    anbieter = [];
    oidc = true;
    start = {};
    einloesung = {};
  });

  Serververbindung verbindung() => Serververbindung(
    Uri.parse('https://fotos.example/'),
    't',
    client: MockClient((r) async {
      http.Response json(Object o) => http.Response(jsonEncode(o), 200);
      switch ('${r.method} ${r.url.path}') {
        case 'GET /api/v1/konto':
          return json({'name': 'erika', 'oidc': anbieter, 'geraet': 'g1'});
        case 'GET /api/v1/geraete':
          return json({'geraete': <Object>[]});
        case 'GET /api/v1/zustand':
          return json({
            'protokoll': 2,
            'anmeldung': {'totp': false, 'oidc': oidc},
          });
        case 'POST /api/v1/konto/oidc':
          start = (jsonDecode(r.body) as Map).cast<String, Object?>();
          return json({'adresse': 'https://anbieter.example/anmelden'});
        case 'POST /api/v1/anmelden/oidc/einloesen':
          einloesung = (jsonDecode(r.body) as Map).cast<String, Object?>();
          anbieter = ['https://anbieter.example'];
          return json({'verknuepft': true});
      }
      return http.Response('{}', 404);
    }),
  );

  Future<AppTexte> zeige(
    WidgetTester tester,
    Future<void> Function(Uri) oeffne,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: ListView(
            children: [
              EigenesKonto(
                verbindung: verbindung(),
                abmelden: () {},
                oeffne: oeffne,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppTexte.of(tester.element(find.byType(EigenesKonto)));
  }

  testWidgets('verknüpft über den Rückweg auf dem Telefon', (tester) async {
    // Der nachgebaute Browser braucht echtes HTTP; die Testumgebung legt
    // sonst eine Attrappe darüber, die jede Anfrage mit 400 beantwortet.
    final vorher = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = vorher);
    Future<String>? browser;
    final t = await zeige(tester, (adresse) async {
      expect(adresse.host, 'anbieter.example');
      // Der Browser: angemeldet beim Anbieter, über den Server zurück auf
      // den Port der App – mit dem Zustand, den die App mitgab.
      final rueckweg = Uri.parse('${start['rueckweg']}');
      browser = () async {
        final c = HttpClient();
        try {
          final r = await (await c.getUrl(
            rueckweg.replace(
              queryParameters: {'code': 'c1', 'zustand': '${start['zustand']}'},
            ),
          )).close();
          return await r.transform(utf8.decoder).join();
        } finally {
          c.close();
        }
      }();
    });
    expect(find.text(t.eigenOidcTitel), findsOneWidget);
    expect(find.text(t.eigenOidcNicht), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text(t.eigenOidcVerknuepfen));
      for (var i = 0; i < 200 && einloesung.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await browser, contains(t.eigenOidcSeite));
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (find.text(t.eigenOidcFertig).evaluate().isNotEmpty) break;
      }
    });
    expect(Uri.parse('${start['rueckweg']}').host, '127.0.0.1');
    expect(einloesung['code'], 'c1');
    expect(einloesung['pruefer'], isA<String>());
    expect(find.text(t.eigenOidcFertig), findsOneWidget);
    expect(
      find.text(t.eigenOidcVerknuepft('https://anbieter.example')),
      findsOneWidget,
    );
  });

  testWidgets('ohne Anbieter am Server kein Eintrag', (tester) async {
    oidc = false;
    final t = await zeige(tester, (_) async {});
    expect(find.text(t.eigenOidcTitel), findsNothing);
  });
}
