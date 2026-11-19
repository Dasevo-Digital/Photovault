import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:teilen_ui/beschriftungen.dart';
import 'package:teilen_ui/geteilte_alben.dart';

void main() {
  testWidgets(
    'Gleichnamige Personen lassen sich nachladen und gezielt auswählen',
    (tester) async {
      final anfragen = <Uri>[];
      Map? entscheidung;
      final client = MockClient((r) async {
        anfragen.add(r.url);
        if (r.method == 'POST') {
          entscheidung = jsonDecode(r.body) as Map;
          return http.Response('{}', 200);
        }
        final seite = r.url.queryParameters['personenseite'];
        return http.Response(
          jsonEncode({
            'besitzer': true,
            'mehr': false,
            'gesichter': [],
            'personenMehr': seite != '1',
            'personen': seite == null
                ? []
                : [
                    {
                      'id': seite == '0' ? 'p-erste' : 'p-spaet',
                      'name': 'Gleicher Name',
                    },
                  ],
            'vorschlaege': [
              {
                'id': 'v1',
                'aufnahme': 'a',
                'art': 'person',
                'wert': 'Gleicher Name',
                'von': 'Testgast',
                'angelegt': '2026-11-19T10:00:00Z',
                'aktuell': '',
                'stand': 'geprueft',
                'zustand': entscheidung == null ? 'offen' : 'angenommen',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final verbindung = Serververbindung(
        Uri.parse('http://server/'),
        'test',
        client: client,
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          home: Scaffold(
            body: Beschriftungsknopf(
              ort: Aktivitaetsort.besitzer(verbindung, 'album'),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(Beschriftungsknopf));
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await tester.ensureVisible(find.text('Weitere gleichnamige Personen'));
        await tester.tap(find.text('Weitere gleichnamige Personen'));
        await tester.pumpAndSettle();
      }
      expect(
        anfragen
            .where((u) => u.queryParameters['personenname'] == 'Gleicher Name')
            .map((u) => u.queryParameters['personenseite']),
        ['0', '1'],
      );
      expect(find.text('Weitere gleichnamige Personen'), findsNothing);
      final auswahl = find.byType(DropdownButton<String>).last;
      await tester.ensureVisible(auswahl);
      await tester.tap(auswahl);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gleicher Name (p-spaet)').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Übernehmen'));
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect(entscheidung, {
        'annehmen': true,
        'stand': 'geprueft',
        'person': 'p-spaet',
      });
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Schliessen'));
      await tester.pumpAndSettle();
      client.close();
    },
  );

  testWidgets(
    'Besitzer prüft alte Angabe und sendet genau den geprüften Stand',
    (tester) async {
      Map? entscheidung;
      var angenommen = false;
      final client = MockClient((r) async {
        expect(r.url.path, startsWith('/api/v1/alben/album/beschriftungen'));
        if (r.method == 'POST') {
          expect(r.url.path, endsWith('/v1'));
          entscheidung = jsonDecode(r.body) as Map;
          angenommen = true;
          return http.Response('{}', 200);
        }
        return http.Response(
          jsonEncode({
            'besitzer': true,
            'mehr': false,
            'personen': [],
            'gesichter': [],
            'vorschlaege': [
              {
                'id': 'v1',
                'aufnahme': 'a',
                'art': 'ort',
                'wert': 'Testort',
                'von': 'Testgast',
                'angelegt': '2026-11-19T10:00:00Z',
                'aktuell': 'Alter Ort',
                'stand': 'gepruefter-stand',
                'zustand': angenommen ? 'angenommen' : 'offen',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final verbindung = Serververbindung(
        Uri.parse('http://server/'),
        'test',
        client: client,
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          home: Scaffold(
            body: Beschriftungsknopf(
              ort: Aktivitaetsort.besitzer(verbindung, 'album'),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(Beschriftungsknopf));
      await tester.pumpAndSettle();
      expect(find.textContaining('Alter Ort'), findsOneWidget);
      expect(find.textContaining('Testgast'), findsOneWidget);
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect(entscheidung, {'annehmen': true, 'stand': 'gepruefter-stand'});
      expect(find.text('Angenommen'), findsOneWidget);
      expect(find.text('Übernehmen'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Schliessen'));
      await tester.pumpAndSettle();
      client.close();
    },
  );
}
