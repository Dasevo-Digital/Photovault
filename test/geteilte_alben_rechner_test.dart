import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/geteilt_rechner.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:teilen_ui/geteilte_alben.dart';
import 'package:teilen_ui/l10n/teilen_texte.dart';

/// Geteilte Alben am Rechner (#289): dieselbe Oberfläche wie am Telefon
/// (packages/teilen_ui), mit Dateidialog und media_kit.
void main() {
  test('ohne Server kein Zugang – dann auch kein Abschnitt', () {
    expect(teilungszugang(LibraryState()), isNull);
  });

  test('gewählte Dateien gehen mit Namen und Änderungszeit', () async {
    final ordner = Directory.systemTemp.createTempSync('pv_beitraege_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final f = File('${ordner.path}/IMG_0001.HEIC')..writeAsBytesSync([1, 2]);
    f.setLastModifiedSync(DateTime(2026, 8, 14, 19, 30));

    final b = beitraegeAus([f, File('${ordner.path}/weg.jpg')]);

    expect(b, hasLength(1), reason: 'was es nicht gibt, fällt heraus');
    expect(b.single.name, 'IMG_0001.HEIC');
    expect(b.single.geaendert, DateTime(2026, 8, 14, 19, 30));
    expect((await b.single.datei())!.path, f.path);
  });

  Future<void> oeffne(WidgetTester tester, Size groesse) async {
    tester.view.physicalSize = groesse;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final v = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: MockClient((r) async {
        final body = r.url.path.endsWith('/teilungen')
            ? {'teilungen': []}
            : {'konten': []};
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => mitKontenTeilen(
                context,
                v,
                albumId: 'urlaub',
                titel: 'Urlaub',
              ),
              child: const Text('teilen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('teilen'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('„Urlaub“ mit Konten teilen'), findsOneWidget);
    expect(
      find.text('Auf diesem Server gibt es kein weiteres Konto.'),
      findsOneWidget,
    );
  }

  testWidgets('am Rechner ein Dialog', (tester) async {
    await oeffne(tester, const Size(1200, 800));
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text('Schliessen'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('am schmalen Bildschirm ein Blatt von unten', (tester) async {
    await oeffne(tester, const Size(400, 800));
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });
  // SIC-196: Scheiterte das Beitragen an etwas anderem als einem Server-
  // oder Verbindungsfehler, blieb das Fenster „Lade 1 von 1 hoch …“ offen.
  testWidgets('Beitragen: das Fenster schliesst bei jedem Fehler', (
    tester,
  ) async {
    final v = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: MockClient(
        (r) async => http.Response(
          jsonEncode({
            'album': {'name': 'Urlaub', 'besitzer': 'B', 'beitragen': true},
            'aufnahmen': [],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    final zugang = Teilungszugang(
      verbindung: v,
      waehle: (_) async => [
        Beitragsdatei(
          name: 'kaputt.jpg',
          geaendert: DateTime(2026, 8, 14),
          datei: () async => throw const FileSystemException('nicht lesbar'),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: GeteiltesAlbumSeite(
          zugang: zugang,
          album: const GeteiltesAlbum(
            id: 'a1',
            name: 'Urlaub',
            besitzer: 'B',
            beitragen: true,
            anzahl: 0,
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    final t = lookupTeilenTexte(const Locale('de'));
    await tester.tap(find.byTooltip(t.geteiltHinzufuegen));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(t.geteiltFehler('kaputt.jpg')), findsOneWidget);
  });

  testWidgets('#463 am Rechner: „Mit Ort“ in beiden Dialogen, ohne Überlauf', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gesendet = <Object?>[];
    final v = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: MockClient((r) async {
        if (r.method == 'PUT') {
          gesendet.add(jsonDecode(r.body));
          return http.Response('', 204);
        }
        final body = switch (r.url.path) {
          '/api/v1/alben/urlaub/teilungen' => {
            'teilungen': [
              {
                'id': 's1',
                'konto': 'k-max',
                'name': 'Maximilian Mustermann',
                'beitragen': false,
                'mitOrt': true,
              },
            ],
          },
          '/api/v1/partner' => {
            'meine': [
              {'konto': 'k-max', 'name': 'Maximilian Mustermann'},
            ],
            'mitMir': [],
          },
          _ => {
            'konten': [
              {'id': 'k-max', 'name': 'Maximilian Mustermann'},
              {'id': 'k-eva', 'name': 'Eva'},
            ],
          },
        };
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => mitKontenTeilen(
                    context,
                    v,
                    albumId: 'urlaub',
                    titel: 'Urlaub',
                  ),
                  child: const Text('album'),
                ),
                TextButton(
                  onPressed: () => bibliothekTeilen(context, v),
                  child: const Text('bibliothek'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final t = lookupTeilenTexte(const Locale('de'));
    for (final (knopf, zeile, neu) in [
      ('album', t.kontenMitOrt, t.kontenOhneOrt),
      ('bibliothek', t.kontenOhneOrt, t.kontenOhneOrt),
    ]) {
      await tester.tap(find.text(knopf));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget, reason: knopf);
      // Die Zeile des Kontos und die Wahl für ein neues.
      expect(find.text(zeile), findsWidgets, reason: knopf);
      expect(find.text(neu), findsWidgets, reason: knopf);
      expect(find.text(t.kontenOrtHinweis), findsOneWidget, reason: knopf);
      expect(tester.takeException(), isNull, reason: knopf);
      await tester.tap(find.text(t.schliessen));
      await tester.pumpAndSettle();
    }
  });
}
