import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show FlutterMap;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/konten.dart';
import 'package:kern/abgleich/speicher.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/kartengruppen.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/bilder.dart';
import 'package:photo_vault_mobil/lokal/lokalbetrachter.dart';
import 'package:photo_vault_mobil/lokal/ungesichert.dart';
import 'package:photo_vault_mobil/seiten/anmelden.dart';
import 'package:photo_vault_mobil/seiten/auswahl.dart';
import 'package:photo_vault_mobil/seiten/betrachter.dart';
import 'package:photo_vault_mobil/seiten/erinnerungen.dart';
import 'package:photo_vault_mobil/seiten/konten.dart';
import 'package:photo_vault_mobil/seiten/konto.dart';
import 'package:photo_vault_mobil/seiten/raster.dart';
import 'package:photo_vault_mobil/seiten/reisen.dart';
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

final _spaeter = DateTime(2026, 10, 15, 12);
final _frueher = DateTime(2020, 1, 1, 12);

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
    // Das neue Album steht als erste Kachel im Streifen des Blatts.
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

  Future<(Sitzung, AppTexte)> rasterMitTagen(
    WidgetTester tester,
    List<Rasterzeile> zeilen,
  ) async {
    final ordner = Directory.systemTemp.createTempSync('pv_tage_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
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
          body: AufnahmenRaster(
            sitzung: sitzung,
            zeilen: zeilen,
            nachTagen: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (sitzung, AppTexte.of(tester.element(find.byType(AufnahmenRaster))));
  }

  Rasterzeile amTag(String id, DateTime wann) {
    final z = _zeile(id, 0, 0);
    return Rasterzeile(
      id: z.id,
      type: z.type,
      originalFileName: z.originalFileName,
      relativePath: z.relativePath,
      thumbnailRelativePath: null,
      fileCreatedAt: wann,
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
      latitude: null,
      longitude: null,
      cameraMake: null,
      isLocked: false,
    );
  }

  testWidgets('Tipp auf das Datum wählt den ganzen Tag, ein zweiter hebt auf', (
    tester,
  ) async {
    final montag = DateTime(2025, 6, 2, 12);
    final sonntag = DateTime(2025, 6, 1, 12);
    final (_, t) = await rasterMitTagen(tester, [
      amTag('m1', montag),
      amTag('m2', montag.subtract(const Duration(hours: 1))),
      amTag('s1', sonntag),
    ]);
    final tagMontag = DateFormat.MMMMEEEEd('de').format(montag);
    final tagSonntag = DateFormat.MMMMEEEEd('de').format(sonntag);
    // Ein Monatskopf, darunter die Tage ohne Jahr.
    expect(find.text(DateFormat.yMMMM('de').format(montag)), findsOneWidget);
    expect(find.text(tagMontag), findsOneWidget);

    await tester.tap(find.text(tagMontag));
    await tester.pumpAndSettle();
    expect(find.text(t.auswahlAnzahl(2)), findsOneWidget);
    // Zwei gewählte Kacheln und der Kreis am Datum tragen den Haken.
    expect(find.byIcon(Icons.check_circle), findsNWidgets(3));

    await tester.tap(find.text(tagSonntag));
    await tester.pumpAndSettle();
    expect(find.text(t.auswahlAnzahl(3)), findsOneWidget);

    await tester.tap(find.text(tagMontag));
    await tester.pumpAndSettle();
    expect(find.text(t.auswahlAnzahl(1)), findsOneWidget);
    await tester.tap(find.text(tagSonntag));
    await tester.pumpAndSettle();
    expect(find.byType(Auswahlleiste), findsNothing);
  });

  testWidgets('Lang drücken und ziehen wählt die Strecke dazwischen', (
    tester,
  ) async {
    final tag = DateTime(2025, 6, 2, 12);
    final (_, t) = await rasterMitTagen(tester, [
      for (var i = 0; i < 4; i++)
        amTag('z$i', tag.subtract(Duration(minutes: i))),
    ]);
    final kacheln = find.byType(Miniatur);
    final zug = await tester.startGesture(tester.getCenter(kacheln.at(0)));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(find.text(t.auswahlAnzahl(1)), findsOneWidget);
    await zug.moveTo(tester.getCenter(kacheln.at(1)));
    await tester.pump();
    await zug.moveTo(tester.getCenter(kacheln.at(2)));
    await tester.pump();
    expect(find.text(t.auswahlAnzahl(3)), findsOneWidget);
    // Zurück nimmt wieder heraus, was nicht mehr in der Strecke liegt.
    await zug.moveTo(tester.getCenter(kacheln.at(1)));
    await tester.pump();
    expect(find.text(t.auswahlAnzahl(2)), findsOneWidget);
    await zug.up();
    await tester.pumpAndSettle();
    expect(find.text(t.auswahlAnzahl(2)), findsOneWidget);

    // Ein Zug, der auf einer gewählten Kachel beginnt, wählt ab.
    final ab = await tester.startGesture(tester.getCenter(kacheln.at(1)));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await ab.moveTo(tester.getCenter(kacheln.at(0)));
    await tester.pump();
    await ab.up();
    await tester.pumpAndSettle();
    expect(find.byType(Auswahlleiste), findsNothing);
  });

  testWidgets('zwei Finger ändern die Spaltenzahl', (tester) async {
    final tag = DateTime(2025, 6, 2, 12);
    await rasterMitTagen(tester, [
      for (var i = 0; i < 12; i++)
        amTag('k$i', tag.subtract(Duration(minutes: i))),
    ]);
    int spalten() =>
        (tester.widget<SliverGrid>(find.byType(SliverGrid).first).gridDelegate
                as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount;
    expect(spalten(), 4);
    final mitte = tester.getCenter(find.byType(AufnahmenRaster));
    // Auseinander: grössere Kacheln, weniger Spalten.
    final a = await tester.startGesture(mitte - const Offset(40, 0));
    final b = await tester.startGesture(mitte + const Offset(40, 0));
    await tester.pump();
    for (var i = 1; i <= 8; i++) {
      await a.moveTo(mitte - Offset(40.0 + i * 12, 0));
      await b.moveTo(mitte + Offset(40.0 + i * 12, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(spalten(), lessThan(4));
    final weniger = spalten();
    // Zusammen: mehr Spalten.
    final c = await tester.startGesture(mitte - const Offset(150, 0));
    final d = await tester.startGesture(mitte + const Offset(150, 0));
    await tester.pump();
    for (var i = 1; i <= 10; i++) {
      await c.moveTo(mitte - Offset(150.0 - i * 13, 0));
      await d.moveTo(mitte + Offset(150.0 - i * 13, 0));
      await tester.pump();
    }
    await c.up();
    await d.up();
    await tester.pumpAndSettle();
    expect(spalten(), greaterThan(weniger));
  });

  Future<(Sitzung, AppDatabase)> sitzungMit(
    WidgetTester tester,
    List<String> ids, {
    bool imPapierkorb = false,
  }) async {
    final ordner = Directory.systemTemp.createTempSync('pv_betrachter_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    for (final id in ids) {
      await db.insertAsset(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'pruef-$id',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2025),
          importedAt: DateTime(2026),
          isTrashed: Value(imPapierkorb),
        ),
      );
    }
    final pfade = (await tester.runAsync(
      () => StoragePaths.forTesting(ordner),
    ))!;
    return (
      Sitzung()
        ..db = db
        ..paths = pfade,
      db,
    );
  }

  testWidgets('Betrachter: nach unten wischen schliesst ihn', (tester) async {
    final (sitzung, _) = await sitzungMit(tester, ['b1']);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  betrachterWeg(
                    Betrachter(
                      sitzung: sitzung,
                      zeilen: [_zeile('b1', 0, 0)],
                      start: 0,
                    ),
                  ),
                ),
                child: const Text('auf'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('auf'));
    await tester.pumpAndSettle();
    expect(find.byType(Betrachter), findsOneWidget);
    // Ein kurzer Zug federt zurück.
    await tester.drag(find.byType(Betrachter), const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(find.byType(Betrachter), findsOneWidget);
    await tester.drag(find.byType(Betrachter), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.byType(Betrachter), findsNothing);
    expect(find.text('auf'), findsOneWidget);
  });

  testWidgets('Papierkorb: das Blatt holt zurück statt wegzuwerfen', (
    tester,
  ) async {
    final (sitzung, db) = await sitzungMit(tester, [
      'p1',
      'p2',
    ], imPapierkorb: true);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: AufnahmenRaster(
            sitzung: sitzung,
            zeilen: [_zeile('p1', 0, 0), _zeile('p2', 0, 0)],
            papierkorb: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(AufnahmenRaster)));
    await tester.longPress(find.byType(Miniatur).at(0));
    await tester.pumpAndSettle();
    expect(find.text(t.auswahlPapierkorb), findsNothing);
    expect(find.text(t.auswahlAlbumTitel), findsNothing);
    await tester.tap(find.text(t.auswahlZurueckholen));
    await tester.pumpAndSettle();
    expect((await db.assetById('p1'))!.isTrashed, isFalse);
    expect((await db.assetById('p2'))!.isTrashed, isTrue);
  });

  testWidgets('Reisen: oben die Reisen, darunter die Aktivitäten – wie im '
      'Browser; Aktivität mit Route, Reise mit ihren Aktivitäten', (
    tester,
  ) async {
    final (sitzung, db) = await sitzungMit(tester, ['r1', 'r2', 'r3', 'r4']);
    for (final (id, breite, stunde) in [('r1', 47.0, 9), ('r2', 47.1, 12)]) {
      await (db.update(db.assets)..where((t) => t.id.equals(id))).write(
        AssetsCompanion(
          latitude: Value(breite),
          longitude: const Value(11.0),
          locationCity: const Value('Innsbruck'),
          locationState: const Value('Tirol'),
          locationCountry: const Value('Austria'),
          fileCreatedAt: Value(DateTime(2026, 7, 3, stunde)),
        ),
      );
    }
    await db.reiseAnlegen(
      ReisenCompanion.insert(
        id: 'alpen',
        name: 'Alpen',
        von: DateTime(2026, 7, 1),
        bis: DateTime(2026, 7, 9),
        angelegtAm: DateTime(2026, 7, 10),
      ),
      ['r1', 'r2', 'r3'],
    );
    await db.aktivitaetAnlegen(
      AktivitaetenCompanion.insert(
        id: 'tour',
        name: 'Zur Hütte',
        art: 'wanderung',
        von: DateTime(2026, 7, 3, 9),
        bis: DateTime(2026, 7, 3, 12),
        reiseId: const Value('alpen'),
        angelegtAm: DateTime(2026, 7, 10),
      ),
      ['r1', 'r2'],
    );
    await db.aktivitaetAnlegen(
      AktivitaetenCompanion.insert(
        id: 'runde',
        name: 'Abendrunde',
        art: 'Gassi',
        von: DateTime(2026, 8, 1, 18),
        bis: DateTime(2026, 8, 1, 19),
        angelegtAm: DateTime(2026, 8, 2),
      ),
      ['r4'],
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(body: ReisenSeite(sitzung: sitzung)),
      ),
    );
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(ReisenSeite)));
    expect(find.text('Alpen'), findsOneWidget);
    expect(find.text('Innsbruck, Tirol, Österreich'), findsOneWidget);
    expect(find.text(t.aktivitaetenTitel), findsOneWidget);
    expect(find.text('Zur Hütte'), findsOneWidget);
    expect(
      find.text('Innsbruck, Tirol, Österreich · Gehört zu: Alpen'),
      findsOneWidget,
    );
    // Eine selbst eingetragene Art ist ihr eigener Name.
    expect(find.text('Gassi'), findsOneWidget);
    expect(find.text(t.aktArtWanderung), findsOneWidget);
    // Oben die Reise, darunter die Aktivitäten.
    expect(
      tester.getTopLeft(find.text('Alpen')).dy,
      lessThan(tester.getTopLeft(find.text(t.aktivitaetenTitel)).dy),
    );

    await tester.ensureVisible(find.text('Zur Hütte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zur Hütte'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Wanderung · 03.07.2026 · 09:00–12:00 · 3\u00a0h 0\u00a0min · '
        '11,1\u00a0km · 2 Aufnahmen',
      ),
      findsOneWidget,
    );
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byType(Miniatur), findsNWidgets(2));
    await tester.tap(find.text('Gehört zu: Alpen'));
    await tester.pumpAndSettle();
    expect(find.text(t.aktivitaetenTitel), findsOneWidget);
    expect(find.textContaining('3 Aufnahmen'), findsOneWidget);
    expect(find.text('Zur Hütte'), findsOneWidget);
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

  test('Telefon-Aufnahmen reihen sich nach Datum zwischen die vom Server', () {
    final server = [_zeile('s1', 0, 0), _zeile('s2', 0, 0)];
    final lokal = [
      LokaleAufnahme(id: 'neu', aufgenommen: _spaeter, video: false),
      LokaleAufnahme(id: 'alt', aufgenommen: _frueher, video: true),
    ];
    final g = mischeMitServer(server, lokal);
    expect(g.zeilen.map((z) => z.id), ['lokal:neu', 's1', 's2', 'lokal:alt']);
    expect(g.lokal.keys, ['lokal:neu', 'lokal:alt']);
    expect(g.zeilen.last.type, 'VIDEO');
    expect(mischeMitServer(server, const []).zeilen, same(server));
  });

  testWidgets(
    'Telefon-Aufnahmen im Raster: Wolke, keine Auswahl, eigener Betrachter',
    (tester) async {
      final ordner = Directory.systemTemp.createTempSync('pv_lokal_');
      addTearDown(() => ordner.deleteSync(recursive: true));
      final pfade = (await tester.runAsync(
        () => StoragePaths.forTesting(ordner),
      ))!;
      final sitzung = Sitzung()
        ..db = AppDatabase(NativeDatabase.memory())
        ..paths = pfade;
      addTearDown(sitzung.db.close);
      final l = LokaleAufnahme(id: 'p1', aufgenommen: _spaeter, video: false);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          home: Scaffold(
            body: AufnahmenRaster(
              sitzung: sitzung,
              zeilen: [l.zeile, _zeile('s1', 0, 0)],
              lokal: {l.kennung: l},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);

      await tester.longPress(find.byType(Miniatur).at(0));
      await tester.pumpAndSettle();
      expect(find.byType(Auswahlleiste), findsNothing, reason: 'nicht wählbar');

      await tester.tap(find.byType(Miniatur).at(0));
      await tester.pumpAndSettle();
      expect(find.byType(Lokalbetrachter), findsOneWidget);
      final t = AppTexte.of(tester.element(find.byType(Lokalbetrachter)));
      expect(find.text(t.lokalNochNichtGesichert), findsOneWidget);
    },
  );

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
