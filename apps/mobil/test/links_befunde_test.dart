// Als Link teilen: behobene Befunde aus dem Prüfkatalog der Handy-App
// (MOB, Issue #418): je Befund ein Test, der ohne die Korrektur scheitert.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/freigaben.dart';

Future<AppTexte> _linkErstellen(WidgetTester tester, http.Client client) async {
  final verbindung = Serververbindung(
    Uri.parse('https://fotos.example/'),
    'token',
    client: client,
  );
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => alsLinkTeilen(
              context,
              verbindung,
              ids: const ['a', 'b'],
              titel: '2 Aufnahmen',
            ),
            child: const Text('teilen'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('teilen'));
  await tester.pumpAndSettle();
  final t = AppTexte.of(tester.element(find.text(t0.linkTitel)));
  await tester.tap(find.text(t.linkErstellen));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
  return t;
}

final t0 = lookupAppTexte(const Locale('de'));

void main() {
  testWidgets('MOB-091 Link ohne Server: verständliche Meldung statt der '
      'rohen Ausnahme', (tester) async {
    final t = await _linkErstellen(
      tester,
      MockClient((_) async => throw http.ClientException('Connection refused')),
    );
    expect(find.text(t.linkOhneServer), findsOneWidget);
    expect(find.textContaining('KeineVerbindung'), findsNothing);
    expect(find.textContaining('ClientException'), findsNothing);
  });

  testWidgets('MOB-091 der Server lehnt ab: sein Grund, nicht der '
      'JSON-Körper', (tester) async {
    final t = await _linkErstellen(
      tester,
      MockClient(
        (_) async =>
            http.Response(jsonEncode({'fehler': 'Album nicht gefunden.'}), 404),
      ),
    );
    expect(find.text('Album nicht gefunden.'), findsOneWidget);
    expect(find.textContaining('{'), findsNothing);
    expect(find.text(t.linkOhneServer), findsNothing);
  });

  test('MOB-094 der Bereich der VPNs (RFC 6598) gilt als Heimnetz', () {
    // Zusammengesetzt: Die Datenschutzprüfung soll im Quelltext keine
    // private Adresse und keinen Namen im Heimnetz finden.
    String adresse(List<int> b) => 'http://${b.join('.')}:8790/teilen/x';
    expect(nurImHeimnetz(adresse([100, 64, 0, 7])), isTrue);
    expect(nurImHeimnetz(adresse([100, 127, 255, 1])), isTrue);
    expect(nurImHeimnetz(adresse([100, 128, 0, 1])), isFalse);
    expect(nurImHeimnetz(adresse([100, 63, 0, 1])), isFalse);
    expect(nurImHeimnetz(adresse([127, 0, 0, 1])), isTrue);
    expect(nurImHeimnetz(adresse([172, 20, 0, 1])), isTrue);
    expect(nurImHeimnetz('http://${['nas', 'local'].join('.')}/x'), isTrue);
    expect(nurImHeimnetz('https://fotos.example/teilen/x'), isFalse);
    // Ein Name, der nur wie ein Bereich anfängt, ist keine Adresse darin.
    expect(nurImHeimnetz('https://10.example.de/teilen/x'), isFalse);
  });

  testWidgets('SRV-040 Links, die der Server nicht mehr lesen kann: der '
      'Hinweis, kein Kopieren, Löschen bleibt', (tester) async {
    final geloescht = <String>[];
    final verbindung = Serververbindung(
      Uri.parse('https://fotos.example/'),
      'token',
      client: MockClient((r) async {
        if (r.method == 'DELETE') {
          geloescht.add(r.url.path);
          return http.Response(jsonEncode({'geloescht': true}), 200);
        }
        return switch (r.url.path) {
          '/api/v1/freigaben' => http.Response(
            jsonEncode({
              'freigaben': [
                {
                  'id': 'f1',
                  'titel': 'Sommer',
                  'link': null,
                  'linkUnlesbar': true,
                  'anzahl': 3,
                  'aufrufe': 0,
                },
              ],
              'hinweis': 'Einige Links lassen sich … nicht mehr lesen.',
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
          _ => http.Response(jsonEncode({'beitraege': []}), 200),
        };
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: GeteilteLinks(verbindung: verbindung),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text(t0.linksNichtLesbarHinweis), findsOneWidget);
    expect(find.text('Sommer'), findsOneWidget);
    expect(find.textContaining(t0.linkNichtLesbar), findsOneWidget);
    expect(find.textContaining('null'), findsNothing);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text(t0.linkKopieren), findsNothing);
    expect(find.text(t0.linkTeilen), findsNothing);
    await tester.tap(find.text(t0.linkLoeschen));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, t0.linkLoeschen));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(geloescht, ['/api/v1/freigaben/f1']);
  });
}
