import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/konten.dart';
import 'package:kern/abgleich/speicher.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:drift/native.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/bilder.dart';
import 'package:photo_vault_mobil/seiten/anmelden.dart';
import 'package:photo_vault_mobil/seiten/auswahl.dart';
import 'package:photo_vault_mobil/seiten/betrachter.dart';
import 'package:photo_vault_mobil/seiten/erinnerungen.dart';
import 'package:photo_vault_mobil/seiten/karte.dart';
import 'package:photo_vault_mobil/seiten/konten.dart';
import 'package:photo_vault_mobil/seiten/konto.dart';
import 'package:photo_vault_mobil/seiten/raster.dart';
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

  testWidgets('Auswahl im Raster: Favorit, Album, Papierkorb', (tester) async {
    final ordner = Directory.systemTemp.createTempSync('pv_auswahl_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    for (final id in ['a1', 'a2', 'a3']) {
      await db.insertAsset(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'pruef-$id',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2025),
          importedAt: DateTime(2026),
        ),
      );
    }
    // Echte Ein-/Ausgabe im Widget-Test nur über runAsync – sonst hängt
    // das await wortlos.
    final pfade = (await tester.runAsync(
      () => StoragePaths.forTesting(ordner),
    ))!;
    final sitzung = Sitzung()
      ..db = db
      ..paths = pfade;
    final zeilen = [_zeile('a1', 0, 0), _zeile('a2', 0, 0), _zeile('a3', 0, 0)];

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: AufnahmenRaster(sitzung: sitzung, zeilen: zeilen),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(AufnahmenRaster)));
    expect(find.byType(Auswahlleiste), findsNothing);

    // Lang drücken wählt, ein Tipp sammelt weitere ein.
    await tester.longPress(find.byType(Miniatur).at(0));
    await tester.pumpAndSettle();
    expect(find.text(t.auswahlAnzahl(1)), findsOneWidget);
    await tester.tap(find.byType(Miniatur).at(1));
    await tester.pumpAndSettle();
    expect(find.text(t.auswahlAnzahl(2)), findsOneWidget);

    await tester.tap(find.text(t.auswahlFavorit));
    await tester.pumpAndSettle();
    expect(
      find.byType(Auswahlleiste),
      findsNothing,
      reason: 'danach aufgehoben',
    );
    Future<AssetData> a(String id) async => (await db.assetById(id))!;
    expect((await a('a1')).isFavorite, isTrue);
    expect((await a('a2')).isFavorite, isTrue);
    expect((await a('a3')).isFavorite, isFalse);

    // Ins neue Album.
    await tester.longPress(find.byType(Miniatur).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.auswahlAlbum));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.auswahlAlbumNeu));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Urlaub');
    await tester.tap(find.text(t.auswahlAlbumAnlegen));
    // Die Meldung steht nur vier Sekunden – nachsehen, bevor sie weg ist.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(t.auswahlImAlbum(1, 'Urlaub')), findsOneWidget);
    // Weg mit der Meldung – sie läge sonst über der Leiste.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    final album = (await db.alleAlben()).single;
    expect(album.name, 'Urlaub');
    final imAlbum = await tester.runAsync(
      () => db.watchAlbumAssets(album.id).first,
    );
    expect(imAlbum!.map((x) => x.id), ['a3']);

    // In den Papierkorb, mit Rückfrage.
    await tester.longPress(find.byType(Miniatur).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.auswahlPapierkorb));
    await tester.pumpAndSettle();
    expect(find.text(t.auswahlPapierkorbTitel(1)), findsOneWidget);
    await tester.tap(find.text(t.betrachterPapierkorb));
    await tester.pumpAndSettle();
    expect((await a('a1')).isTrashed, isTrue);
    expect((await a('a2')).isTrashed, isFalse);
    expect(find.byType(Auswahlleiste), findsNothing);
  });

  testWidgets('Erinnerungen: ein Kärtchen je Jahrgang, Tipp öffnet ihn', (
    tester,
  ) async {
    final ordner = Directory.systemTemp.createTempSync('pv_erinnerungen_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final heute = DateTime(2026, 10, 15, 9);
    // Nicht zur vollen Stunde – das gälte als erfundene Uhrzeit.
    for (final (id, wann) in [
      ('vor2', DateTime(2024, 10, 15, 10, 17)),
      ('vor5a', DateTime(2021, 10, 15, 8, 3)),
      ('vor5b', DateTime(2021, 10, 15, 19, 41)),
      ('anderer', DateTime(2021, 3, 2, 12, 5)),
    ]) {
      await db.insertAsset(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'pruef-$id',
          type: 'IMAGE',
          fileCreatedAt: wann,
          importedAt: DateTime(2026),
        ),
      );
    }
    final pfade = (await tester.runAsync(
      () => StoragePaths.forTesting(ordner),
    ))!;
    final sitzung = Sitzung()
      ..db = db
      ..paths = pfade;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: ListView(
            children: [Erinnerungsstreifen(sitzung: sitzung, heute: heute)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(Erinnerungsstreifen)));
    expect(find.text(t.erinnerungenVorJahren(2)), findsOneWidget);
    expect(find.text(t.erinnerungenVorJahren(5)), findsOneWidget);
    expect(find.text(t.erinnerungenAnzahl(2)), findsOneWidget);
    expect(find.text(t.erinnerungenVorJahren(1)), findsNothing);

    await tester.tap(find.text(t.erinnerungenVorJahren(5)));
    await tester.pumpAndSettle();
    expect(find.byType(Betrachter), findsOneWidget);
  });

  testWidgets('die Kontoseite zeigt den Speicher des Servers', (tester) async {
    final sitzung = Sitzung()
      ..verbindung = Verbindungsdatei(
        server: Uri.parse('https://fotos.example.de/'),
        konto: 'anna',
        geraet: 'Telefon',
        token: 't',
      )
      ..serverspeicher = const Serverspeicher(
        stufe: 'knapp',
        gesamt: 200 << 30,
        frei: 20 << 30,
      );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Konto(sitzung: sitzung),
      ),
    );
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(Konto)));
    expect(find.text(t.speicherStand('20.00 GB', '200.00 GB')), findsOneWidget);
    expect(tester.takeException(), isNull);
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
