import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/konten.dart';
import 'package:kern/abgleich/sicherung.dart';
import 'package:kern/abgleich/speicher.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/einstellungen/einstellungsstand.dart';
import 'package:photo_vault/screens/einstellungen/server.dart';
import 'package:photo_vault/screens/einstellungen/server_sicherung.dart';
import 'package:photo_vault/screens/server_konten_screen.dart';
import 'package:photo_vault/screens/server_verbinden_screen.dart';
import 'package:photo_vault/services/library_location.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/qr_bild.dart';

/// Die Oberfläche zum Verbinden mit einem Server (Issue #86, Stufe 2):
/// Sie steht, auch schmal, und sagt, was sie tut.
void main() {
  late Directory ordner;
  late LibraryState bib;

  setUp(() async {
    ordner = Directory.systemTemp.createTempSync('pv_server_ui_');
    LibraryLocation.nutzeFuerTests(anker: ordner);
    PackageInfo.setMockInitialValues(
      appName: 'Photo Vault',
      packageName: 'test',
      version: '0',
      buildNumber: '0',
      buildSignature: '',
    );
    bib = LibraryState()
      ..db = AppDatabase(NativeDatabase.memory())
      ..paths = await StoragePaths.forTesting(
        Directory('${ordner.path}/library'),
      );
  });
  tearDown(() async {
    await bib.db.close();
    LibraryLocation.zuruecksetzenFuerTests();
    ordner.deleteSync(recursive: true);
  });

  Future<AppTexte> zeige(
    WidgetTester tester,
    Widget Function(Einstellungsstand) seite,
  ) async {
    await tester.binding.setSurfaceSize(const Size(380, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late Einstellungsstand stand;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Builder(
          builder: (context) {
            stand = Einstellungsstand(
              bib,
              kontext: () => context,
              aktiv: () => true,
            );
            return Scaffold(body: SingleChildScrollView(child: seite(stand)));
          },
        ),
      ),
    );
    await tester.pump();
    addTearDown(stand.dispose);
    return AppTexte.of(tester.element(find.byType(Scaffold).first));
  }

  testWidgets('ohne Verbindung: Erklärung und der Weg dorthin', (tester) async {
    final t = await zeige(tester, ServerGruppe.new);
    expect(find.text(t.serverErklaerung), findsOneWidget);
    expect(find.text(t.serverVerbinden), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('der erste Schritt steht auch schmal', (tester) async {
    final t = await zeige(
      tester,
      (stand) =>
          SizedBox(height: 800, child: ServerVerbindenScreen(stand: stand)),
    );
    expect(find.text(t.serverAdresse), findsOneWidget);
    expect(find.text(t.serverPasswort), findsOneWidget);
    expect(find.text(t.serverAnmelden), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('der QR-Code wird gezeichnet', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: QrBild('otpauth://totp/Photo%20Vault:erika?secret=ABC'),
          ),
        ),
      ),
    );
    expect(find.byType(QrBild), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ein leerer Server: das erste Konto entsteht in der App', (
    tester,
  ) async {
    var versuche = 0;
    final client = MockClient((r) async {
      switch (r.url.path) {
        case '/api/v1/zustand':
          return http.Response(
            jsonEncode({
              'dienst': 'photo-vault',
              'protokoll': 2,
              'anmeldung': {'totp': true, 'oidc': false},
              'einrichten': true,
            }),
            200,
          );
        case '/api/v1/einrichten':
          final k = jsonDecode(r.body) as Map;
          expect((k['name'], k['passwort']), ('anna', 'ein langes passwort'));
          return ++versuche == 1
              ? http.Response('{"fehler": "nur aus dem Heimnetz"}', 403)
              : http.Response(
                  jsonEncode({
                    'token': 'pv1_x',
                    'wiederherstellungscodes': ['eins', 'zwei'],
                  }),
                  200,
                );
      }
      return http.Response('{}', 404);
    });
    final t = await zeige(
      tester,
      (stand) => SizedBox(
        height: 800,
        child: ServerVerbindenScreen(
          stand: stand,
          anmeldungFuer: (s) => Anmeldung(s, client: client),
        ),
      ),
    );
    final felder = find.byType(TextField);
    await tester.enterText(felder.at(0), 'http://127.0.0.1:8790');
    await tester.enterText(felder.at(1), 'anna');
    await tester.enterText(felder.at(2), 'kurz');
    await tester.tap(find.text(t.serverAnmelden));
    await tester.pumpAndSettle();
    expect(
      find.text(t.serverPasswortZuKurz(passwortMindestlaenge)),
      findsOneWidget,
    );

    await tester.enterText(felder.at(2), 'ein langes passwort');
    await tester.tap(find.text(t.serverAnmelden));
    await tester.pumpAndSettle();
    expect(find.text(t.serverErstesTitel), findsOneWidget);
    expect(find.text(t.serverErstesText('anna')), findsOneWidget);

    final wiederholen = find.widgetWithText(
      TextField,
      t.serverPasswortWiederholen,
    );
    await tester.enterText(wiederholen, 'ein anderes passwort');
    await tester.tap(find.text(t.serverErstesAnlegen));
    await tester.pumpAndSettle();
    expect(find.text(t.serverPasswortUngleich), findsOneWidget);
    expect(versuche, 0, reason: 'erst gar nicht gefragt');

    await tester.enterText(wiederholen, 'ein langes passwort');
    await tester.tap(find.text(t.serverErstesAnlegen));
    await tester.pumpAndSettle();
    expect(find.text(t.serverErstesNurHeimnetz), findsOneWidget);

    await tester.tap(find.text(t.serverErstesAnlegen));
    await tester.pumpAndSettle();
    expect(find.text(t.serverCodesTitel), findsOneWidget);
    expect(versuche, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Konten verwalten: Liste, Menü nur für andere, Anlegen', (
    tester,
  ) async {
    final verwaltung = _Verwaltung();
    final t = await zeige(
      tester,
      (_) => SizedBox(
        height: 800,
        child: ServerKontenScreen(verwaltung: verwaltung),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('anna · ${t.serverKontoDu}'), findsOneWidget);
    expect(find.text('max'), findsOneWidget);
    expect(find.textContaining(t.serverKontoGesperrt), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text(t.serverKontoEntsperren), findsOneWidget);
    expect(find.text(t.serverKontoTotpZuruecksetzen), findsNothing);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.serverKontoAnlegen));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    final felder = find.descendant(
      of: dialog,
      matching: find.byType(TextField),
    );
    await tester.enterText(felder.at(0), 'x');
    await tester.tap(find.text(t.allgSpeichern));
    await tester.pumpAndSettle();
    expect(find.text(t.serverNameUngueltig), findsOneWidget);
    await tester.enterText(felder.at(0), 'eva');
    await tester.enterText(felder.at(1), 'ein langes passwort');
    await tester.enterText(felder.at(2), 'ein langes passwort');
    await tester.tap(find.text(t.allgSpeichern));
    await tester.pumpAndSettle();
    expect(verwaltung.angelegt, ['eva']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('der Speicher des Servers: Stand, knapp in Rot, voll', (
    tester,
  ) async {
    const gib = 1 << 30;
    bib.verbindung = Verbindungsdatei(
      server: Uri.parse('https://fotos.example.de/'),
      konto: 'anna',
      geraet: 'Rechner',
      token: 't',
    );
    bib.serverspeicherFuerTests = const Serverspeicher(
      stufe: 'ausreichend',
      gesamt: 200 * gib,
      frei: 120 * gib,
    );
    var t = await zeige(tester, ServerGruppe.new);
    expect(
      find.text(t.serverSpeicherStand('120.00 GB', '200.00 GB')),
      findsOneWidget,
    );

    bib.serverspeicherFuerTests = const Serverspeicher(
      stufe: 'knapp',
      gesamt: 200 * gib,
      frei: 20 * gib,
    );
    t = await zeige(tester, ServerGruppe.new);
    final zeile = tester.widget<Text>(
      find.text(t.serverSpeicherStand('20.00 GB', '200.00 GB')),
    );
    expect(
      zeile.style?.color,
      Theme.of(tester.element(find.byWidget(zeile))).colorScheme.error,
    );

    bib.serverspeicherFuerTests = const Serverspeicher(
      stufe: 'voll',
      gesamt: 200 * gib,
      frei: gib,
    );
    t = await zeige(tester, ServerGruppe.new);
    expect(find.text(t.serverSpeicherVoll), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('die Sicherung des Servers: Stand, Warnung, Einrichten', (
    tester,
  ) async {
    bib.serversicherungFuerTests = Serversicherungsstand(
      stufe: 'ok',
      letzterErfolg: DateTime(2026, 10, 15, 3, 41),
      naechster: DateTime(2026, 10, 16, 3, 30),
      neu: 12,
    );
    var t = await zeige(tester, (_) => ServerSicherungAbschnitt(bib));
    expect(find.textContaining('12'), findsOneWidget);
    expect(find.text(t.serverSicherungJetzt), findsOneWidget);

    bib.serversicherungFuerTests = const Serversicherungsstand(
      stufe: 'zielFehlt',
    );
    t = await zeige(tester, (_) => ServerSicherungAbschnitt(bib));
    expect(find.text(t.serverSicherungZielFehlt), findsOneWidget);
    expect(find.text(t.serverSicherungZielNeu), findsOneWidget);
    expect(find.text(t.serverSicherungJetzt), findsNothing);

    bib.serversicherungFuerTests = const Serversicherungsstand(
      stufe: 'nichtEingerichtet',
      ziel: '/mnt/sicherung',
    );
    t = await zeige(tester, (_) => ServerSicherungAbschnitt(bib));
    await tester.tap(find.text(t.serverSicherungEinrichten));
    await tester.pumpAndSettle();
    final felder = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(felder.at(0), 'zu kurz');
    await tester.enterText(felder.at(1), 'zu kurz');
    await tester.tap(find.text(t.allgFestlegen));
    await tester.pumpAndSettle();
    expect(
      find.text(t.serverPasswortZuKurz(passwortMindestlaenge)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

/// Eine Kontenverwaltung ohne Server.
class _Verwaltung extends Kontenverwaltung {
  _Verwaltung() : super(Serververbindung(Uri.parse('http://test/'), 't'));

  final angelegt = <String>[];

  @override
  Future<List<Kontoeintrag>> liste() async => const [
    Kontoeintrag(
      id: '1',
      name: 'anna',
      verwalter: true,
      totp: true,
      gesperrt: false,
      geraete: 2,
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

  @override
  Future<Kontoeintrag> legeAn(
    String name,
    String passwort, {
    bool verwalter = false,
  }) async {
    angelegt.add(name);
    return Kontoeintrag(
      id: '3',
      name: name,
      verwalter: verwalter,
      totp: false,
      gesperrt: false,
      geraete: 0,
      du: false,
    );
  }
}
