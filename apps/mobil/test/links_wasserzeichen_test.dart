// Wasserzeichen für Links (#497): Das Blatt zeichnet den Text zu einem PNG
// und schickt es mit; ein Server, der das nicht kennt, behält keinen Link
// ohne das gewünschte Zeichen.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/services/wasserzeichen.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/freigaben.dart';

final t = lookupAppTexte(const Locale('de'));

/// Was der Server zu sehen bekam.
class _Mitschrift {
  final anfragen = <http.Request>[];

  Map<String, Object?>? get angelegt {
    for (final r in anfragen) {
      if (r.method == 'POST' && r.url.path.endsWith('api/v1/freigaben')) {
        return (jsonDecode(r.body) as Map).cast<String, Object?>();
      }
    }
    return null;
  }
}

/// [serverKennt]: ob die Antwort auf das Anlegen `wasserzeichen` trägt;
/// [meldetFunktion]: ob der Zustand des Servers die Funktion nennt.
Future<_Mitschrift> _oeffne(
  WidgetTester tester, {
  required bool serverKennt,
  bool? meldetFunktion,
}) async {
  final mitschrift = _Mitschrift();
  final client = MockClient((r) async {
    mitschrift.anfragen.add(r);
    if (r.method == 'DELETE') return http.Response('{"geloescht":true}', 200);
    if (r.method == 'GET' && r.url.path.endsWith('api/v1/zustand')) {
      return http.Response(
        jsonEncode({
          'dienst': 'photo-vault',
          'funktionen': {
            'papierkorb': 1,
            if (meldetFunktion ?? serverKennt) 'wasserzeichen': 1,
          },
        }),
        200,
      );
    }
    final k = (jsonDecode(r.body) as Map).cast<String, Object?>();
    return http.Response(
      jsonEncode({
        'id': 'f1',
        'titel': k['titel'],
        'link': 'https://fotos.example/teilen/abcdefghijklmnopqrstuv',
        // Ein Server von vor #497 lässt das Feld weg.
        if (serverKennt) 'wasserzeichen': k['wasserzeichen'] != null,
      }),
      201,
    );
  });
  final verbindung = Serververbindung(
    Uri.parse('https://fotos.example/'),
    'token',
    client: client,
  );
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
              ids: const ['a'],
              titel: 'Feier',
            ),
            child: const Text('teilen'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('teilen'));
  await tester.pumpAndSettle();
  return mitschrift;
}

Future<void> _erstellen(WidgetTester tester) async {
  await tester.ensureVisible(find.text(t.linkErstellen));
  await tester.tap(find.text(t.linkErstellen));
  // Das Zeichnen des Textes und die Antwort laufen ausserhalb der
  // gefälschten Zeit.
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mit Wasserzeichen: der Text geht als PNG mit, samt Lage und '
      'Grösse', (tester) async {
    final m = await _oeffne(tester, serverKennt: true);
    expect(find.text(t.linkWasserzeichenText), findsNothing);
    await tester.tap(find.text(t.linkWasserzeichen));
    await tester.pumpAndSettle();
    // Die Felder erst mit dem Schalter, unten rechts vorgewählt.
    expect(find.text(t.lageUntenRechts), findsOneWidget);
    expect(find.text(t.linkWasserzeichenHinweis), findsOneWidget);
    expect(find.text(t.linkWasserzeichenOriginal), findsNothing);
    await tester.tap(find.text(t.linkHerunterladen));
    await tester.pumpAndSettle();
    expect(find.text(t.linkWasserzeichenOriginal), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, t.linkWasserzeichenText),
      '© Erika',
    );
    await _erstellen(tester);

    final k = m.angelegt!;
    final w = Wasserzeichen.ausJson(k['wasserzeichen'])!;
    expect(w.art, Wasserzeichenart.text);
    expect(w.text, '© Erika');
    expect(w.lage, Wasserzeichenlage.untenRechts);
    expect(w.groesse, Wasserzeichen.vorgabeGroesse);
    final masse = Wasserzeichenbild.masse(w.bild!);
    expect(masse, isNotNull, reason: 'ein PNG');
    // So breit, wie das Zeichen in der grössten Ansicht wird.
    expect(
      masse!.breite,
      closeTo(Wasserzeichen.vorgabeGroesse * linkAnsichtBreite, 2),
    );
    expect(Wasserzeichenbild.gueltig(w.bild!), isTrue);
    expect(k['herunterladen'], isTrue);
    expect(find.text(t.linkWerHatSieht), findsOneWidget);
    expect(m.anfragen.where((r) => r.method == 'DELETE'), isEmpty);
  });

  testWidgets('ein Server ohne Wasserzeichen: erst gar kein Link', (
    tester,
  ) async {
    final m = await _oeffne(tester, serverKennt: false);
    await tester.tap(find.text(t.linkWasserzeichen));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, t.linkWasserzeichenText),
      '© Erika',
    );
    await _erstellen(tester);

    // Gefragt, nichts angelegt, nichts zu löschen.
    expect(m.anfragen.map((r) => r.method), ['GET']);
    expect(m.angelegt, isNull);
    expect(find.text(t.linkWasserzeichenServerZuAlt), findsOneWidget);
    expect(find.text(t.linkWerHatSieht), findsNothing);
  });

  testWidgets('sagt die Antwort trotzdem nichts vom Zeichen: der Link geht '
      'gleich wieder', (tester) async {
    final m = await _oeffne(tester, serverKennt: false, meldetFunktion: true);
    await tester.tap(find.text(t.linkWasserzeichen));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, t.linkWasserzeichenText),
      '© Erika',
    );
    await _erstellen(tester);

    expect(m.angelegt!['wasserzeichen'], isNotNull);
    final weg = m.anfragen.where((r) => r.method == 'DELETE').toList();
    expect(weg, hasLength(1));
    expect(weg.single.url.path, endsWith('api/v1/freigaben/f1'));
    expect(find.text(t.linkWasserzeichenServerZuAlt), findsOneWidget);
    // Kein Link zum Kopieren.
    expect(find.text(t.linkWerHatSieht), findsNothing);
  });

  testWidgets('ohne Text gibt es keinen Link, ohne Schalter kein Zeichen', (
    tester,
  ) async {
    final m = await _oeffne(tester, serverKennt: false);
    await tester.tap(find.text(t.linkWasserzeichen));
    await tester.pumpAndSettle();
    await _erstellen(tester);
    expect(find.text(t.linkWasserzeichenTextFehlt), findsOneWidget);
    expect(m.anfragen, isEmpty);

    // Abgeschaltet: wie bisher, auch an einem alten Server.
    await tester.ensureVisible(find.text(t.linkWasserzeichen));
    await tester.tap(find.text(t.linkWasserzeichen));
    await tester.pumpAndSettle();
    await _erstellen(tester);
    expect(m.angelegt!.keys, isNot(contains('wasserzeichen')));
    expect(m.anfragen.where((r) => r.method == 'DELETE'), isEmpty);
    expect(find.text(t.linkWerHatSieht), findsOneWidget);
  });

  testWidgets('in der Liste: ein Zeichen, das der Server nicht mehr lesen '
      'kann', (tester) async {
    final verbindung = Serververbindung(
      Uri.parse('https://fotos.example/'),
      'token',
      client: MockClient(
        (r) async => switch (r.url.path) {
          '/api/v1/freigaben' => http.Response(
            jsonEncode({
              'freigaben': [
                {
                  'id': 'f1',
                  'titel': 'Sommer',
                  'link': 'https://fotos.example/teilen/abcdefghijklmnopqrstuv',
                  'anzahl': 3,
                  'aufrufe': 0,
                  'wasserzeichen': true,
                  'wasserzeichenUnlesbar': true,
                },
                {
                  'id': 'f2',
                  'titel': 'Herbst',
                  'link': 'https://fotos.example/teilen/bcdefghijklmnopqrstuvw',
                  'anzahl': 1,
                  'aufrufe': 0,
                  'wasserzeichen': true,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
          _ => http.Response(jsonEncode({'beitraege': []}), 200),
        },
      ),
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
    expect(find.textContaining(t.linkMitWasserzeichen), findsNWidgets(2));
    expect(find.textContaining(t.linkWasserzeichenUnlesbar), findsOneWidget);
  });
}
