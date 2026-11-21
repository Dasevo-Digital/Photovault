// Nachlasskontakt: behobene Befunde aus dem Prüfkatalog der Handy-App
// (MOB, Issue #418): je Befund ein Test, der ohne die Korrektur scheitert.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:teilen_ui/geteilte_alben.dart';

void main() {
  testWidgets('MOB-107 gleich nach dem Ablehnen erneut verlangen: der Grund '
      'des Servers, nicht seine rohe Antwort', (tester) async {
    const grund = 'Gerade erst abgelehnt – später wieder.';
    final client = MockClient((r) async {
      if (r.url.path == '/api/v1/nachlass') {
        return http.Response(
          jsonEncode({
            'kontakte': const [],
            'fuerMich': [
              {'konto': 'k-a', 'name': 'Konto A', 'frist': 7},
            ],
            'fristen': [7, 14, 30, 90],
          }),
          200,
        );
      }
      if (r.url.path == '/api/v1/konten/andere') {
        return http.Response(jsonEncode({'konten': const []}), 200);
      }
      if (r.method == 'POST' &&
          r.url.path == '/api/v1/nachlass/von/k-a/anfordern') {
        return http.Response(
          jsonEncode({'fehler': grund}),
          409,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('', 404);
    });
    final v = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
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
              onPressed: () => nachlassVerwalten(context, v),
              child: const Text('nachlass'),
            ),
          ),
        ),
      ),
    );
    Future<void> warte() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('nachlass'));
    await warte();
    final t = teilenTexte(tester.element(find.text('nachlass')));
    await tester.tap(find.text(t.nachlassVerlangen));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, t.nachlassVerlangen));
    await warte();
    expect(find.text(grund), findsOneWidget);
    expect(find.textContaining('{"fehler"'), findsNothing);
  });
}
