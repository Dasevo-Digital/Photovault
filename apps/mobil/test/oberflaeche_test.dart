import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/konten.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/anmelden.dart';
import 'package:photo_vault_mobil/seiten/karte.dart';
import 'package:photo_vault_mobil/seiten/konten.dart';
import 'package:photo_vault_mobil/seiten/sicherung.dart';
import 'package:photo_vault_mobil/sicherung/dienst.dart';
import 'package:photo_vault_mobil/sicherung/stand.dart';
import 'package:photo_vault_mobil/sitzung.dart';

Rasterzeile _zeile(String id, double breite, double laenge) => Rasterzeile(
  id: id,
  type: 'IMAGE',
  originalFileName: '$id.jpg',
  relativePath: 'originals/$id.jpg',
  thumbnailRelativePath: null,
  fileCreatedAt: DateTime(2025),
  durationSeconds: null,
  isFavorite: false,
  isStackCover: false,
  stackId: null,
  stackSize: null,
  linkedAssetId: null,
  rating: 0,
  colorLabel: null,
  widthPx: null,
  heightPx: null,
  latitude: breite,
  longitude: laenge,
  cameraMake: null,
  isLocked: false,
);

void main() {
  test('die Karte fasst nahe Fotos zusammen, je nach Zoom', () {
    final orte = [
      _zeile('tor', 52.5163, 13.3777),
      _zeile('dom', 52.5191, 13.4010),
      _zeile('hafen', 53.5413, 9.9841),
    ];
    Set<Set<String>> gruppen(double zoom) => {
      for (final g in kartengruppen(orte, zoom)) {for (final z in g) z.id},
    };
    expect(gruppen(4), {
      {'tor', 'dom'},
      {'hafen'},
    });
    expect(gruppen(16), {
      {'tor'},
      {'dom'},
      {'hafen'},
    });
  });

  test('Deutsch und Englisch haben dieselben Texte', () {
    Set<String> schluessel(String sprache) =>
        (jsonDecode(File('lib/l10n/app_$sprache.arb').readAsStringSync())
                as Map<String, Object?>)
            .keys
            .where((k) => !k.startsWith('@'))
            .toSet();
    expect(schluessel('en'), schluessel('de'));
  });

  testWidgets('die Anmeldung sagt, wenn die Adresse fehlt', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Anmelden(sitzung: Sitzung()),
      ),
    );
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(Anmelden)));
    expect(find.text(t.anmeldenGeraet), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, t.anmeldenGeraet))
          .controller!
          .text,
      t.geraetVorgabe,
    );

    await tester.tap(find.widgetWithText(FilledButton, t.anmeldenAnmelden));
    await tester.pumpAndSettle();
    expect(find.text(t.anmeldenNichtErreichbar), findsOneWidget);
  });

  testWidgets('ein leerer Server: das erste Konto vom Telefon', (tester) async {
    var versuche = 0;
    final client = MockClient((r) async {
      if (r.url.path == '/api/v1/zustand') {
        return http.Response(
          jsonEncode({
            'dienst': 'photo-vault',
            'protokoll': 2,
            'anmeldung': {'totp': true, 'oidc': false},
            'einrichten': true,
          }),
          200,
        );
      }
      if (r.url.path == '/api/v1/einrichten') {
        versuche++;
        // Jemand war schneller.
        return http.Response('{"fehler": "schon eingerichtet"}', 409);
      }
      return http.Response('{}', 404);
    });
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Anmelden(
          sitzung: Sitzung(),
          anmeldungFuer: (s) => Anmeldung(s, client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(Anmelden)));
    await tester.enterText(
      find.widgetWithText(TextField, t.anmeldenAdresse),
      'http://127.0.0.1:8790',
    );
    await tester.enterText(find.widgetWithText(TextField, t.anmeldenName), 'a');
    await tester.enterText(
      find.widgetWithText(TextField, t.anmeldenPasswort),
      'ein langes passwort',
    );
    await tester.tap(find.widgetWithText(FilledButton, t.anmeldenAnmelden));
    await tester.pumpAndSettle();
    expect(find.text(t.anmeldenNameUngueltig), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, t.anmeldenName),
      'anna',
    );
    await tester.tap(find.widgetWithText(FilledButton, t.anmeldenAnmelden));
    await tester.pumpAndSettle();
    expect(find.text(t.anmeldenErstesText('anna')), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, t.anmeldenPasswortWiederholen),
      'ein langes passwort',
    );
    await tester.tap(find.text(t.anmeldenErstesAnlegen));
    await tester.pumpAndSettle();
    expect(versuche, 1);
    expect(find.text(t.anmeldenSchonEingerichtet), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, t.anmeldenAnmelden),
      findsOneWidget,
      reason: 'zurück zur Anmeldung',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Konten: Liste und Aktionen für andere, nicht für sich', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Konten(verwaltung: _Verwaltung()),
      ),
    );
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(Konten)));
    expect(find.text('anna · ${t.kontoDu}'), findsOneWidget);
    await tester.tap(find.text('anna · ${t.kontoDu}'));
    await tester.pumpAndSettle();
    expect(find.text(t.kontoPasswortSetzen), findsNothing);
    await tester.tap(find.text('max'));
    await tester.pumpAndSettle();
    expect(find.text(t.kontoPasswortSetzen), findsOneWidget);
    expect(find.text(t.kontoEntsperren), findsOneWidget);
    expect(find.text(t.kontoTotpZuruecksetzen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('die Sicherungsseite zeigt Stand, Probleme und Knopf', (
    tester,
  ) async {
    final ordner = Directory.systemTemp.createTempSync('pv_sicherungsseite_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    Sicherungsstand.oeffne(ordner)
      ..einstellungen = const Sicherungseinstellungen(an: true)
      ..letzterLauf = Laufbericht(
        ende: DateTime(2026, 10, 13, 9, 30),
        gesamt: 5,
        offen: 1,
        hochgeladen: 3,
        vorhanden: 0,
        fehlgeschlagen: 1,
        vollstaendig: false,
      )
      ..fehlschlag('x', 'Datei nicht verfügbar')
      ..schliesse();
    final dienst = Sicherungsdienst(
      ordner: ordner,
      server: Uri.parse('http://localhost:1/'),
      token: 'pv1_test',
    );
    addTearDown(dienst.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Sicherungsseite(dienst: dienst),
      ),
    );
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(Sicherungsseite)));
    expect(find.text(t.sicherungStand(3, 5)), findsOneWidget);
    expect(find.text(t.sicherungProbleme(1)), findsOneWidget);
    expect(find.text('Datei nicht verfügbar'), findsOneWidget);
    expect(find.text(t.sicherungJetzt), findsOneWidget);
    expect(find.text(t.sicherungAlleFotos), findsOneWidget);
    expect(sicherungKurz(t, dienst), t.sicherungStand(3, 5));
  });
}

/// Eine Kontenverwaltung ohne Server.
class _Verwaltung extends Kontenverwaltung {
  _Verwaltung() : super(Serververbindung(Uri.parse('http://test/'), 't'));

  @override
  Future<List<Kontoeintrag>> liste() async => const [
    Kontoeintrag(
      id: '1',
      name: 'anna',
      verwalter: true,
      totp: true,
      gesperrt: false,
      geraete: 1,
      du: true,
    ),
    Kontoeintrag(
      id: '2',
      name: 'max',
      verwalter: false,
      totp: false,
      gesperrt: true,
      geraete: 0,
      du: false,
    ),
  ];
}
