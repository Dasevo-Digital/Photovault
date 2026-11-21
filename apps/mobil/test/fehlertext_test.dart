// Rohe Fehlertexte in der Oberfläche (Prüfkatalog MOB, Issue #418): statt
// „KeineVerbindung(…)“ oder dem JSON-Körper eine verständliche Meldung.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:photo_vault_mobil/fehlertext.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/freigaben.dart';

void main() {
  final t = lookupAppTexte(const Locale('de'));

  test('Fehler werden zu Sätzen, nie zur rohen Ausnahme', () {
    expect(
      fehlertext(t, KeineVerbindung(http.ClientException('refused'))),
      t.fehlerOhneServer,
    );
    expect(
      fehlertext(t, Serverfehler(409, jsonEncode({'fehler': 'Schon da.'}))),
      'Schon da.',
    );
    expect(fehlertext(t, Serverfehler(500, '<html>')), t.fehlerAllgemein);
    expect(fehlertext(t, StateError('intern')), t.fehlerAllgemein);
  });

  testWidgets('Link löschen ohne Server: Meldung statt Ausnahme', (
    tester,
  ) async {
    var geholt = false;
    final client = MockClient((r) async {
      if (r.method == 'GET' && !geholt) {
        geholt = true;
        return http.Response(
          jsonEncode({
            'freigaben': [
              {'id': 'f1', 'titel': 'Urlaub', 'link': 'https://fotos.example/'},
            ],
          }),
          200,
        );
      }
      throw http.ClientException('Connection refused');
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: GeteilteLinks(
            verbindung: Serververbindung(
              Uri.parse('https://fotos.example/'),
              't',
              client: client,
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Urlaub'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.linkLoeschen).last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, t.linkLoeschen));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text(t.fehlerOhneServer), findsOneWidget);
    expect(find.textContaining('KeineVerbindung'), findsNothing);
  });
}
