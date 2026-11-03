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
}
