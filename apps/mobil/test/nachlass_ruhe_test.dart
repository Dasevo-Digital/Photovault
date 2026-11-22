import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:teilen_ui/nachlass.dart';

/// Die 15-Minuten-Uhr des Nachlass-Hinweises steht am Telefon, solange
/// die App nicht zu sehen ist (#437); am Rechner läuft sie wie bisher.
void main() {
  late int abfragen;
  late Serververbindung v;

  setUp(() {
    abfragen = 0;
    v = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: MockClient((r) async {
        if (r.url.path == '/api/v1/nachlass') {
          abfragen++;
          return http.Response(
            jsonEncode({'kontakte': [], 'fuerMich': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('', 404);
      }),
    );
  });

  Future<void> zeige(WidgetTester tester, {required bool anhalten}) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: NachlassHinweis(verbindung: v, imHintergrundAnhalten: anhalten),
        ),
      ),
    );
    await tester.pump();
  }

  void inDenHintergrund(WidgetTester tester) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }

  void zurueck(WidgetTester tester) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  testWidgets('am Telefon steht die Uhr im Hintergrund', (tester) async {
    await zeige(tester, anhalten: true);
    expect(abfragen, 1, reason: 'beim Start');
    await tester.pump(const Duration(minutes: 15));
    expect(abfragen, 2, reason: 'nach 15 Minuten');

    inDenHintergrund(tester);
    await tester.pump(const Duration(minutes: 45));
    expect(abfragen, 2, reason: 'im Hintergrund keine Abfrage');

    zurueck(tester);
    await tester.pump(const Duration(minutes: 15));
    expect(abfragen, greaterThanOrEqualTo(3), reason: 'die Uhr läuft wieder');
  });

  testWidgets('am Rechner läuft die Uhr wie bisher', (tester) async {
    await zeige(tester, anhalten: false);
    expect(abfragen, 1);
    inDenHintergrund(tester);
    await tester.pump(const Duration(minutes: 15));
    expect(abfragen, 2);
    zurueck(tester);
  });
}
