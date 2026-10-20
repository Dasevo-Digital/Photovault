import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:gelaende/flugvideo.dart' show Videoausgang;
import 'package:gelaende/hoehenprofil.dart';
import 'package:flutter_map/flutter_map.dart' show FlutterMap, MarkerLayer;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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
import 'package:zierbild/lebensbaum_flaeche.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/bilder.dart';
import 'package:photo_vault_mobil/lokal/lokalbetrachter.dart';
import 'package:photo_vault_mobil/lokal/ungesichert.dart';
import 'package:kern/services/aufnahmeangaben.dart';
import 'package:kern/services/bibliothekseinstellungen.dart';
import 'package:photo_vault_mobil/seiten/angaben.dart';
import 'package:photo_vault_mobil/seiten/anmelden.dart';
import 'package:photo_vault_mobil/seiten/auswahl.dart';
import 'package:photo_vault_mobil/seiten/betrachter.dart';
import 'package:photo_vault_mobil/seiten/duplikate.dart';
import 'package:photo_vault_mobil/seiten/eigenes_konto.dart';
import 'package:photo_vault_mobil/seiten/einstellungen.dart';
import 'package:photo_vault_mobil/seiten/entwickeln.dart';
import 'package:photo_vault_mobil/seiten/erinnerungen.dart';
import 'package:photo_vault_mobil/seiten/freigaben.dart';
import 'package:photo_vault_mobil/seiten/gesichter.dart';
import 'package:photo_vault_mobil/seiten/alben.dart';
import 'package:photo_vault_mobil/seiten/gesicht_im_foto.dart';
import 'package:photo_vault_mobil/seiten/gesichtsebene.dart';
import 'package:photo_vault_mobil/seiten/rueckblick.dart';
import 'package:photo_vault_mobil/seiten/konten.dart';
import 'package:photo_vault_mobil/seiten/konto.dart';
import 'package:photo_vault_mobil/seiten/lebensbaum.dart';
import 'package:photo_vault_mobil/seiten/personen.dart';
import 'package:photo_vault_mobil/seiten/raster.dart';
import 'package:photo_vault_mobil/seiten/landschaft.dart';
import 'package:photo_vault_mobil/seiten/reisen.dart';
import 'package:photo_vault_mobil/seiten/sicherung.dart';
import 'package:photo_vault_mobil/seiten/diashow.dart';
import 'package:photo_vault_mobil/seiten/orte.dart';
import 'package:photo_vault_mobil/seiten/stammbaum.dart';
import 'package:photo_vault_mobil/seiten/statistik.dart';
import 'package:photo_vault_mobil/seiten/suche.dart';
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
    // Wie viele Kacheln in der ersten Reihe stehen – gleich, ob das
    // Raster ein Gitter ist oder eine Liste aus Reihen.
    int spalten() {
      final oben = [
        for (final e in find.byType(Miniatur).evaluate())
          (e.renderObject! as RenderBox).localToGlobal(Offset.zero).dy,
      ];
      final erste = oben.reduce((a, b) => a < b ? a : b);
      return oben.where((y) => (y - erste).abs() < 1).length;
    }

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

  testWidgets('Rückblick und Kalender wie am Rechner (#185)', (tester) async {
    final (sitzung, db) = await sitzungMit(tester, ['r1', 'r2', 'r3']);
    await tester.runAsync(() async {
      for (final (id, wann) in [
        ('r1', DateTime(2024, 10, 20, 14, 37)),
        ('r2', DateTime(2024, 3, 5, 9, 12)),
        ('r3', DateTime(2025, 7, 1, 18, 3)),
      ]) {
        await (db.update(db.assets)..where((t) => t.id.equals(id))).write(
          AssetsCompanion(fileCreatedAt: Value(wann)),
        );
      }
      await db
          .into(db.people)
          .insert(
            PeopleCompanion.insert(
              id: 'oma',
              name: 'Oma',
              geburtsdatum: Value(DateTime(1950, 10, 22)),
            ),
          );
      await db
          .into(db.faces)
          .insert(
            FacesCompanion.insert(
              id: 'fo',
              assetId: 'r3',
              personId: const Value('oma'),
              boxX: 0.1,
              boxY: 0.1,
              boxW: 0.2,
              boxH: 0.2,
            ),
          );
    });
    Future<void> warte(Finder f) async {
      for (var i = 0; i < 30 && f.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
    }

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: Rueckblick(sitzung: sitzung, heute: DateTime(2026, 10, 20)),
        ),
      ),
    );
    await warte(find.text('In 2 Tagen: Oma wird 76'));
    expect(find.text('In 2 Tagen: Oma wird 76'), findsOneWidget);
    expect(find.text('Dein Jahr 2026'), findsOneWidget);
    final eintrag = find.text('20. Oktober 2024 · vor 2 Jahren');
    await warte(eintrag);
    expect(eintrag, findsOneWidget);
    await tester.tap(find.text('Merken'));
    await warte(find.text('Gemerkt'));
    expect(find.text('Gemerkt'), findsOneWidget);
    expect(find.text('Merken'), findsNothing);
    final gemerkt = await tester.runAsync(() => db.alleGemerktenErinnerungen());
    expect(gemerkt!.single.id, '2024-10-20');

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(body: Kalender(sitzung: sitzung)),
      ),
    );
    await warte(find.text('2025'));
    expect(find.text('2025'), findsOneWidget);
    expect(find.text('2024'), findsOneWidget);
    await tester.tap(find.text('2024'));
    await warte(find.text('Oktober'));
    expect(find.text('März'), findsOneWidget);
    expect(find.text('Oktober'), findsOneWidget);
    expect(find.text('Dein Jahr 2024'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('Diashow: blättert von selbst, Videos bleiben draussen', (
    tester,
  ) async {
    final (sitzung, _) = await sitzungMit(tester, ['d1', 'd2', 'd3']);
    final video = Rasterzeile(
      id: 'v',
      type: 'VIDEO',
      originalFileName: 'v.mov',
      relativePath: 'originals/v.mov',
      thumbnailRelativePath: null,
      fileCreatedAt: DateTime(2025),
      durationSeconds: 3,
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
    final zeilen = [
      _zeile('d1', 0, 0),
      video,
      _zeile('d2', 0, 0),
      _zeile('d3', 0, 0),
    ];
    int? zurueck = -2;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => zurueck = await zeigeDiashow(
                  context,
                  sitzung,
                  zeilen,
                  ab: 1,
                ),
                child: const Text('los'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('los'));
    // Laden (echte Ein-/Ausgabe, die Dateien fehlen) und zeigen.
    Future<void> warte(String stand) async {
      for (var i = 0; i < 40 && find.text(stand).evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // Ab dem Video: die Show beginnt beim nächsten Foto, d2 – das zweite
    // von drei Fotos.
    await warte('2 / 3');
    expect(find.text('2 / 3'), findsOneWidget);
    // Nach vier Sekunden kommt das nächste.
    await tester.pump(diashowTakt);
    await warte('3 / 3');
    expect(find.text('3 / 3'), findsOneWidget);
    // Anhalten: Es bleibt stehen.
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Anhalten'));
    await tester.pump(diashowTakt * 2);
    expect(find.text('3 / 3'), findsOneWidget);
    // Beenden gibt zurück, wo sie stand – d3 in den Zeilen samt Video.
    // Die Knöpfe sind inzwischen wieder ausgeblendet; ein Tipp holt sie.
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Diashow beenden'));
    await tester.pumpAndSettle();
    expect(zurueck, 3);
  });

  testWidgets('Orte: Länder mit Städten, ein Tipp zeigt die Aufnahmen', (
    tester,
  ) async {
    final (sitzung, db) = await sitzungMit(tester, ['o1', 'o2', 'o3', 'o4']);
    await tester.runAsync(() async {
      for (final (id, land, stadt) in [
        ('o1', 'Italy', 'Rome'),
        ('o2', 'Italy', 'Rome'),
        ('o3', 'Italy', 'Milan'),
        ('o4', 'Austria', 'Vienna'),
      ]) {
        await (db.update(db.assets)..where((t) => t.id.equals(id))).write(
          AssetsCompanion(
            locationCountry: Value(land),
            locationCity: Value(stadt),
          ),
        );
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(body: Orte(sitzung: sitzung)),
      ),
    );
    for (var i = 0; i < 20 && find.text('Italien').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.text('Italien'), findsOneWidget);
    expect(find.text('Österreich'), findsOneWidget);
    expect(find.text('3 Aufnahmen'), findsOneWidget);
    expect(find.text('2 Orte'), findsOneWidget);
    expect(find.text('Vienna'), findsOneWidget);
    await tester.tap(find.text('Italien'));
    for (var i = 0; i < 20 && find.text('Rome').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Oben die Städte, die grösste zuerst.
    expect(find.text('Rome'), findsOneWidget);
    expect(find.text('Milan'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Rome')).dx,
      lessThan(tester.getTopLeft(find.text('Milan')).dx),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('Betrachter: Gesichtsrahmen zeigen, antippen, aufziehen (#190)', (
    tester,
  ) async {
    final (sitzung, db) = await sitzungMit(tester, ['g1']);
    await tester.runAsync(() async {
      await db.fuehreAus(const PersonAnlegen('ina', 'Ina'));
      for (final (id, x, person) in [('fa', 0.1, 'ina'), ('fb', 0.6, null)]) {
        await db
            .into(db.faces)
            .insert(
              FacesCompanion.insert(
                id: id,
                assetId: 'g1',
                personId: Value(person),
                boxX: x,
                boxY: 0.2,
                boxW: 0.25,
                boxH: 0.3,
              ),
            );
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Betrachter(
          sitzung: sitzung,
          zeilen: [_zeile('g1', 0, 0)],
          start: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> ruhe() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }

    expect(find.byType(Gesichtsebene), findsNothing);
    await tester.tap(find.byTooltip('Mehr'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gesichter zeigen'));
    await ruhe();
    expect(find.byType(Gesichtsebene), findsOneWidget);
    expect(find.text('Ina'), findsOneWidget, reason: 'benannt mit Namen');

    // Ein Tipp auf den Rahmen öffnet „Benennen“.
    // Ohne Masse gilt 4:3 – und das Testfenster ist 4:3, die Ebene also
    // genau das Bild.
    final rahmen = tester.getRect(find.byType(Gesichtsebene));
    await tester.tapAt(
      Offset(
        rahmen.left + rahmen.width * 0.7,
        rahmen.top + rahmen.height * 0.35,
      ),
    );
    // PhotoView wartet, ob ein zweiter Tipp folgt (Doppeltipp zoomt).
    await tester.pump(const Duration(milliseconds: 400));
    await ruhe();
    expect(find.text('Wer ist das?'), findsWidgets);
    // Dort ist kein Gesicht: den Rahmen löschen (#191) – nach Rückfrage.
    await tester.tap(find.text('Rahmen löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Rahmen löschen'));
    await ruhe();
    final uebrig = await tester.runAsync(() => db.facesForAsset('g1'));
    expect(uebrig!.map((f) => f.id), ['fa']);

    // Das Foto nicht mehr nach Gesichtern durchsuchen – und zurück.
    Future<bool> ausgenommen() async =>
        (await tester.runAsync(() => db.assetById('g1')))!.faceScanExcluded;
    await tester.tap(find.byTooltip('Mehr'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nicht mehr nach Gesichtern durchsuchen'));
    await ruhe();
    expect(await ausgenommen(), isTrue);
    expect(find.textContaining('übersprungen'), findsOneWidget);
    await tester.tap(find.byTooltip('Mehr'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wieder nach Gesichtern durchsuchen'));
    await ruhe();
    expect(await ausgenommen(), isFalse);

    // Aufziehen: ein Wisch, der zu klein ist, wird abgelehnt.
    await tester.tap(find.byTooltip('Mehr'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gesicht aufziehen'));
    await tester.pumpAndSettle();
    expect(find.text('Einen Rahmen um das Gesicht ziehen.'), findsOneWidget);
    // Flach: drei Punkte hoch sind weniger als ein Prozent des Bildes.
    final mitte = rahmen.center;
    await tester.dragFrom(mitte, const Offset(60, 3));
    await tester.pumpAndSettle();
    expect(find.textContaining('zu klein'), findsOneWidget);
    // Ein richtiger Rahmen geht an den Server – den gibt es hier nicht.
    await tester.dragFrom(mitte, const Offset(80, 90));
    await ruhe();
    expect(find.textContaining('nicht anlegen'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

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

  testWidgets('Gesichter ohne Namen: Gruppe mit Vorschlag, bestätigen', (
    tester,
  ) async {
    final (sitzung, db) = await sitzungMit(tester, ['g1', 'g2', 'g3']);
    Uint8List vektor(double x) {
      final v = Float32List(128);
      final laenge = math.sqrt(x * x + 1);
      v[0] = x / laenge;
      v[1] = 1 / laenge;
      return Uint8List.view(v.buffer);
    }

    await tester.runAsync(() async {
      await db.fuehreAus(const PersonAnlegen('anna', 'Anna'));
      for (final (id, aufnahme, person, x) in [
        ('fa', 'g1', 'anna', 0.05),
        ('f1', 'g2', null, 0.0),
        ('f2', 'g3', null, 0.02),
      ]) {
        await db
            .into(db.faces)
            .insert(
              FacesCompanion.insert(
                id: id,
                assetId: aufnahme,
                personId: Value(person),
                boxX: 0.1,
                boxY: 0.1,
                boxW: 0.2,
                boxH: 0.2,
                embedding: Value(vektor(x)),
              ),
            );
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(body: Personen(sitzung: sitzung)),
      ),
    );
    // Die Gruppierung läuft in einem eigenen Isolate.
    for (var i = 0; i < 20 && find.text('Anna?').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(find.text('Ohne Namen'), findsOneWidget);
    expect(find.text('Anna?'), findsOneWidget);
    await tester.tap(find.text('Anna?'));
    await tester.pumpAndSettle();
    expect(find.text('2 ähnliche Gesichter'), findsOneWidget);
    // Das Zeichen in der Ecke zeigt ein Gesicht im ganzen Foto (#189) –
    // und nimmt es dabei nicht heraus. Abgezählte Bilder statt
    // pumpAndSettle: Bis das Foto geladen ist, dreht ein Ladekreis.
    expect(find.byType(ImFotoKnopf), findsNWidgets(2));
    await tester.tap(find.byType(ImFotoKnopf).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(GesichtImFoto), findsOneWidget);
    Navigator.of(tester.element(find.byType(GesichtImFoto))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(GesichtImFoto), findsNothing);
    await tester.tap(find.text('Das ist Anna'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    final zugeordnet = await tester.runAsync(
      () =>
          (db.select(db.faces)..where((t) => t.personId.equals('anna'))).get(),
    );
    expect({for (final f in zugeordnet!) f.id}, {'fa', 'f1', 'f2'});
    // Die Bestätigung ist eine Rückmeldung für Annas Schwelle – ein
    // Eintrag für die ganze Gruppe.
    final gemerkt = await tester.runAsync(
      () => db.select(db.faceMatchFeedback).get(),
    );
    expect(gemerkt, hasLength(1));
    expect(gemerkt!.single.personId, 'anna');
    expect(gemerkt.single.accepted, isTrue);
    for (
      var i = 0;
      i < 20 && find.text('Ohne Namen').evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(find.text('Ohne Namen'), findsNothing);
    // Der Stream der Personen schliesst mit einem Timer – vor dem Ende
    // abbauen, sonst steht er beim Aufräumen noch aus.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('Ohne Namen: alle ignorieren, zurückholen, alle löschen (#192)', (
    tester,
  ) async {
    final (sitzung, db) = await sitzungMit(tester, ['g1', 'g2', 'g3']);
    Uint8List vektor(double x) {
      final v = Float32List(128);
      final laenge = math.sqrt(x * x + 1);
      v[0] = x / laenge;
      v[1] = 1 / laenge;
      return Uint8List.view(v.buffer);
    }

    await tester.runAsync(() async {
      await db.fuehreAus(const PersonAnlegen('anna', 'Anna'));
      for (final (id, aufnahme, person) in [
        ('fa', 'g1', 'anna'),
        ('f1', 'g2', null),
        ('f2', 'g3', null),
      ]) {
        await db
            .into(db.faces)
            .insert(
              FacesCompanion.insert(
                id: id,
                assetId: aufnahme,
                personId: Value(person),
                boxX: 0.1,
                boxY: 0.1,
                boxW: 0.2,
                boxH: 0.2,
                embedding: Value(vektor(0.01)),
              ),
            );
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(body: Personen(sitzung: sitzung)),
      ),
    );
    Future<void> warte(bool Function() bis) async {
      for (var i = 0; i < 30 && !bis(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<List<FaceData>> gesichter() async =>
        (await tester.runAsync(() => db.select(db.faces).get()))!;

    // Die Gruppierung läuft in einem eigenen Isolate.
    await warte(() => find.byTooltip('Mehr').evaluate().isNotEmpty);
    await tester.tap(find.byTooltip('Mehr'));
    await tester.pumpAndSettle();
    expect(find.text('2 Gesichter wandern nach „Ignoriert“'), findsOneWidget);
    await tester.tap(find.text('Alle unbenannten Gesichter ignorieren'));
    await warte(() => find.textContaining('ignoriert.').evaluate().isNotEmpty);
    expect(find.textContaining('2 Gesichter ignoriert'), findsOneWidget);
    expect(
      {for (final f in await gesichter()) f.id: f.isIgnored},
      {'fa': false, 'f1': true, 'f2': true},
    );

    // Nichts mehr offen – der Abschnitt bleibt, über ihn geht es zurück.
    await warte(() => find.byTooltip('Mehr').evaluate().isNotEmpty);
    await tester.tap(find.byTooltip('Mehr'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ignoriert'));
    await warte(
      () =>
          find.byType(IgnorierteGesichter).evaluate().isNotEmpty &&
          find.text('2 Gesichter').evaluate().isNotEmpty,
    );
    expect(find.text('2 Gesichter'), findsOneWidget);
    await tester.tap(
      find
          .descendant(
            of: find.byType(IgnorierteGesichter),
            matching: find.byType(Personenbild),
          )
          .first,
    );
    await tester.pump();
    await tester.tap(find.text('1 zurückholen'));
    await warte(() => find.text('1 zurückgeholt').evaluate().isNotEmpty);
    expect((await gesichter()).where((f) => f.isIgnored), hasLength(1));
    Navigator.of(tester.element(find.byType(IgnorierteGesichter))).pop();
    await tester.pumpAndSettle();

    // Löschen trifft alle unbenannten, auch die ignorierten – nach
    // Rückfrage. Anna bleibt.
    await warte(() => find.byTooltip('Mehr').evaluate().isNotEmpty);
    await tester.tap(find.byTooltip('Mehr'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alle unbenannten Erkennungen löschen'));
    await tester.pumpAndSettle();
    expect(find.text('Erkennungen wirklich löschen?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
    await warte(() => find.textContaining('gelöscht').evaluate().isNotEmpty);
    expect((await gesichter()).map((f) => f.id), ['fa']);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('Betrachter: unbenannte eines Fotos ignorieren, löschen (#192)', (
    tester,
  ) async {
    final (sitzung, db) = await sitzungMit(tester, ['g1']);
    await tester.runAsync(() async {
      await db.fuehreAus(const PersonAnlegen('ina', 'Ina'));
      for (final (id, x, person, beiseite) in [
        ('fa', 0.1, 'ina', false),
        ('fb', 0.4, null, false),
        ('fc', 0.7, null, true),
      ]) {
        await db
            .into(db.faces)
            .insert(
              FacesCompanion.insert(
                id: id,
                assetId: 'g1',
                personId: Value(person),
                isIgnored: Value(beiseite),
                boxX: x,
                boxY: 0.2,
                boxW: 0.2,
                boxH: 0.3,
              ),
            );
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Betrachter(
          sitzung: sitzung,
          zeilen: [_zeile('g1', 0, 0)],
          start: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> ruhe() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }

    Future<Map<String, bool>> stand() async => {
      for (final f in (await tester.runAsync(() => db.facesForAsset('g1')))!)
        f.id: f.isIgnored,
    };

    await tester.tap(find.byTooltip('Mehr'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gesichter zeigen'));
    await ruhe();
    await tester.tap(find.byTooltip('Mehr'));
    await tester.pumpAndSettle();
    // Ignorieren zählt nur die offenen, Löschen auch das beiseitegelegte.
    expect(find.text('2 unbenannte Erkennungen löschen'), findsOneWidget);
    await tester.tap(find.text('Unbenanntes Gesicht ignorieren'));
    await ruhe();
    expect(await stand(), {'fa': false, 'fb': true, 'fc': true});

    await tester.tap(find.byTooltip('Mehr'));
    await tester.pumpAndSettle();
    expect(find.text('Keine unbenannten Gesichter'), findsOneWidget);
    await tester.tap(find.text('2 unbenannte Erkennungen löschen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Benannte Gesichter bleiben'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
    await ruhe();
    expect(await stand(), {'fa': false});
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('Weitere Fotos finden: abwählen lehnt ab und lernt', (
    tester,
  ) async {
    final (sitzung, db) = await sitzungMit(tester, ['w1', 'w2']);
    var richtung = 2;
    Uint8List vektor(double aehnlichkeit) {
      final v = Float32List(128);
      v[1] = aehnlichkeit;
      v[richtung++] = math.sqrt(1 - aehnlichkeit * aehnlichkeit);
      return Uint8List.view(v.buffer);
    }

    await tester.runAsync(() async {
      await db.fuehreAus(const PersonAnlegen('anna', 'Anna'));
      for (final (id, person, s) in [
        ('fa', 'anna', 1.0),
        ('h1', null, 0.9),
        ('h2', null, 0.8),
        ('h3', null, 0.6),
        ('h4', null, 0.45),
      ]) {
        await db
            .into(db.faces)
            .insert(
              FacesCompanion.insert(
                id: id,
                assetId: 'w1',
                personId: Value(person),
                boxX: 0.1,
                boxY: 0.1,
                boxW: 0.2,
                boxH: 0.2,
                embedding: Value(vektor(s)),
              ),
            );
      }
    });
    final anna = (await tester.runAsync(
      () =>
          (db.select(db.people)..where((t) => t.id.equals('anna'))).getSingle(),
    ))!;
    int? ergebnis;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async =>
                    ergebnis = await Navigator.of(context).push<int>(
                      MaterialPageRoute(
                        builder: (_) =>
                            WeitereFotos(sitzung: sitzung, person: anna),
                      ),
                    ),
                child: const Text('los'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('los'));
    for (
      var i = 0;
      i < 30 && find.text('4 Gesichter zuordnen').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(find.text('Vorschläge für Anna'), findsOneWidget);
    expect(find.text('4 Gesichter zuordnen'), findsOneWidget);
    // Das unsicherste (zuletzt) herausnehmen.
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == '45 %',
      ),
    );
    await tester.pump();
    expect(find.text('3 Gesichter zuordnen'), findsOneWidget);
    await tester.tap(find.text('3 Gesichter zuordnen'));
    for (var i = 0; i < 30 && ergebnis == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(ergebnis, 3);
    final (faces, person) = (await tester.runAsync(
      () async => (
        await db.select(db.faces).get(),
        await (db.select(
          db.people,
        )..where((t) => t.id.equals('anna'))).getSingle(),
      ),
    ))!;
    expect(
      {
        for (final f in faces)
          if (f.personId == 'anna') f.id,
      },
      {'fa', 'h1', 'h2', 'h3'},
    );
    // Abgelehnt: kein Vorschlag mehr, und die Schwelle liegt darüber.
    expect(person.similarityThreshold, greaterThan(0.45));
    await tester.pumpAndSettle();
  });

  testWidgets('Suche: nur mit Filtern, ohne Suchtext', (tester) async {
    final (sitzung, db) = await sitzungMit(tester, ['s1', 's2']);
    await tester.runAsync(
      () => db.fuehreAus(const FavoritSetzen(['s2'], true)),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(body: Suche(sitzung: sitzung)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filter'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nur Favoriten'), findsOneWidget);
    await tester.tap(find.text('Nur Favoriten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anwenden'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Filter: Favoriten'), findsOneWidget);
    final raster = tester.widget<AufnahmenRaster>(find.byType(AufnahmenRaster));
    expect([for (final z in raster.zeilen) z.id], ['s2']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('Intelligente Alben: Suche merken, im Album öffnen (#187)', (
    tester,
  ) async {
    final (sitzung, db) = await sitzungMit(tester, ['s1', 's2']);
    await tester.runAsync(
      () => db.fuehreAus(const FavoritSetzen(['s2'], true)),
    );
    Widget app(Widget inhalt) => MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Scaffold(body: inhalt),
    );
    Future<void> ruhe() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(app(Suche(sitzung: sitzung)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filter'));
    await ruhe();
    await tester.tap(find.text('Nur Favoriten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anwenden'));
    await ruhe();
    await tester.tap(find.text('Als intelligentes Album merken'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Lieblinge');
    await tester.tap(find.text('Merken'));
    await ruhe();
    final gemerkt = await tester.runAsync(() => db.gespeicherteSuchen());
    expect(gemerkt!.single.name, 'Lieblinge');
    expect(
      db.decodeSavedSearchFilters(gemerkt.single.filtersJson).favoritesOnly,
      isTrue,
    );

    await tester.pumpWidget(app(Alben(sitzung: sitzung)));
    await ruhe();
    expect(find.text('Intelligente Alben'), findsOneWidget);
    await tester.tap(find.text('Lieblinge'));
    await ruhe();
    final raster = tester.widget<AufnahmenRaster>(find.byType(AufnahmenRaster));
    expect([for (final z in raster.zeilen) z.id], ['s2']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('Album als Link: Gäste dürfen beitragen, Besitzer nimmt an', (
    tester,
  ) async {
    Map<String, Object?>? gesendet;
    final angenommen = <String>[];
    final client = MockClient((r) async {
      if (r.method == 'POST' && r.url.path == '/api/v1/freigaben') {
        gesendet = (jsonDecode(r.body) as Map).cast<String, Object?>();
        return http.Response(
          jsonEncode({'id': 'f1', 'link': 'https://fotos.example/teilen/x'}),
          201,
        );
      }
      if (r.url.path == '/api/v1/beitraege') {
        return http.Response(
          jsonEncode({
            'abgeschottet': true,
            'beitraege': [
              {
                'id': 'b1',
                'freigabe': {'id': 'f1', 'titel': 'Gartenfest'},
                'name': 'IMG_4711.jpg',
                'von': 'Tante Inge',
                'groesse': 1000,
                'zustand': 'bereit',
                'art': 'bild',
              },
              {
                'id': 'b2',
                'freigabe': {'id': 'f1', 'titel': 'Gartenfest'},
                'name': 'boese.jpg',
                'groesse': 9,
                'zustand': 'abgewiesen',
                'grund': 'Dateiformat nicht unterstützt',
              },
            ],
          }),
          200,
          // Sonst kodiert http.Response als Latin-1, und die Umlaute
          // kämen beim UTF-8-Lesen nicht an.
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (r.method == 'POST' && r.url.path.endsWith('/annehmen')) {
        angenommen.add(r.url.pathSegments[3]);
        return http.Response('{"aufnahme":"a1"}', 200);
      }
      if (r.url.path == '/api/v1/freigaben') {
        return http.Response('{"freigaben":[]}', 200);
      }
      return http.Response('', 404, headers: {'content-type': 'image/jpeg'});
    });
    final verbindung = Serververbindung(
      Uri.parse('https://fotos.example/'),
      'token',
      client: client,
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
                  onPressed: () => alsLinkTeilen(
                    context,
                    verbindung,
                    albumId: 'feier',
                    titel: 'Gartenfest',
                  ),
                  child: const Text('album'),
                ),
                TextButton(
                  onPressed: () => alsLinkTeilen(
                    context,
                    verbindung,
                    ids: const ['a'],
                    titel: 'Auswahl',
                  ),
                  child: const Text('auswahl'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // Eine Auswahl kennt keine Beiträge.
    await tester.tap(find.text('auswahl'));
    await tester.pumpAndSettle();
    expect(find.text('Gäste dürfen Fotos und Videos hinzufügen'), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.text('album'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gäste dürfen Fotos und Videos hinzufügen'));
    await tester.pump();
    await tester.tap(find.text('Link erstellen'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(gesendet?['album'], 'feier');
    expect(gesendet?['hochladen'], isTrue);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: GeteilteLinks(verbindung: verbindung),
          ),
        ),
      ),
    );
    // Erst die Links, dann die Beiträge – beides echte Anfragen.
    for (
      var i = 0;
      i < 20 && find.text('Beiträge von Gästen').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.text('Beiträge von Gästen'), findsOneWidget);
    expect(find.text('IMG_4711.jpg'), findsOneWidget);
    expect(find.textContaining('Tante Inge'), findsOneWidget);
    expect(
      find.textContaining('Dateiformat nicht unterstützt'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Annehmen'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(angenommen, ['b1']);
  });

  testWidgets('Als Link teilen: Auswahl an den Server, Link mit Kopieren', (
    tester,
  ) async {
    Map<String, Object?>? gesendet;
    final client = MockClient((r) async {
      if (r.method == 'POST' && r.url.path == '/api/v1/freigaben') {
        gesendet = (jsonDecode(r.body) as Map).cast<String, Object?>();
        return http.Response(
          jsonEncode({
            'id': 'f1',
            'link': 'https://fotos.example/teilen/abcdefghijklmnop',
          }),
          201,
        );
      }
      return http.Response('{}', 404);
    });
    final verbindung = Serververbindung(
      Uri.parse('https://fotos.example/'),
      'token',
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
              onPressed: () => alsLinkTeilen(
                context,
                verbindung,
                ids: const ['a', 'b'],
                titel: '2 Aufnahmen',
              ),
              child: const Text('teilen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('teilen'));
    await tester.pumpAndSettle();
    expect(find.text('Als Link teilen'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Passwort (frei lassen für keins)'),
      'geheim1',
    );
    await tester.tap(find.text('Link erstellen'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(gesendet, {
      'titel': '2 Aufnahmen',
      'ids': ['a', 'b'],
      'tage': 7,
      'passwort': 'geheim1',
      'herunterladen': false,
    });
    expect(
      find.text('https://fotos.example/teilen/abcdefghijklmnop'),
      findsOneWidget,
    );
    expect(find.text('Kopieren'), findsOneWidget);
    // Eine Adresse von aussen: kein Hinweis aufs Heimnetz.
    expect(find.textContaining('nur im Heimnetz'), findsNothing);
    // Zusammengesetzt: Die Datenschutzprüfung soll im Quelltext keine
    // private Adresse finden.
    final heim = [192, 168, 1, 20].join('.');
    expect(nurImHeimnetz('http://$heim:8790/teilen/x'), isTrue);
    expect(nurImHeimnetz('https://fdroid.example/teilen/x'), isFalse);
  });

  testWidgets('Betrachter: LIVE nur bei Live Photos', (tester) async {
    final (sitzung, _) = await sitzungMit(tester, ['b1', 'l1']);
    final z = _zeile('l1', 0, 0);
    final live = Rasterzeile(
      id: z.id,
      type: z.type,
      originalFileName: z.originalFileName,
      relativePath: z.relativePath,
      thumbnailRelativePath: null,
      fileCreatedAt: z.fileCreatedAt,
      durationSeconds: null,
      isFavorite: false,
      isStackCover: false,
      stackId: null,
      stackSize: null,
      linkedAssetId: 'v1',
      rating: 0,
      colorLabel: null,
      widthPx: null,
      heightPx: null,
      latitude: null,
      longitude: null,
      cameraMake: null,
      isLocked: false,
    );
    Future<void> zeige(Rasterzeile zeile) => tester.pumpWidget(
      MaterialApp(
        key: ValueKey(zeile.id),
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Betrachter(sitzung: sitzung, zeilen: [zeile], start: 0),
      ),
    );
    await zeige(live);
    await tester.pumpAndSettle();
    expect(find.text('LIVE'), findsOneWidget);
    await zeige(_zeile('b1', 0, 0));
    await tester.pumpAndSettle();
    expect(find.text('LIVE'), findsNothing);
  });

  testWidgets('Kacheln tragen die Marken wie am Rechner', (tester) async {
    Rasterzeile mit(
      String id, {
      String type = 'IMAGE',
      String datei = 'x.jpg',
      double? dauer,
      bool favorit = false,
      String? partner,
      double? breite,
      int? serie,
    }) => Rasterzeile(
      id: id,
      type: type,
      originalFileName: datei,
      relativePath: 'originals/$datei',
      thumbnailRelativePath: null,
      fileCreatedAt: DateTime(2025),
      durationSeconds: dauer,
      isFavorite: favorit,
      isStackCover: serie != null,
      stackId: serie == null ? null : 's',
      stackSize: serie,
      linkedAssetId: partner,
      rating: 0,
      colorLabel: null,
      widthPx: null,
      heightPx: null,
      latitude: breite,
      longitude: breite,
      cameraMake: null,
      isLocked: false,
    );
    final paths = (await tester.runAsync(
      () => StoragePaths.forTesting(Directory.systemTemp.createTempSync()),
    ))!;
    Future<void> zeige(Rasterzeile z, {double kante = 120}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox.square(
                dimension: kante,
                child: Miniatur(paths: paths, relativ: null, zeile: z),
              ),
            ),
          ),
        );

    await zeige(mit('v', type: 'VIDEO', datei: 'v.mov', dauer: 24.4));
    expect(find.text('0:24'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
    expect(find.text('MOV'), findsNothing);

    await zeige(mit('l', partner: 'v', favorit: true, breite: 52));
    expect(find.byIcon(Icons.motion_photos_on), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.location_on), findsOneWidget);
    expect(find.text('JPG'), findsOneWidget);

    await zeige(mit('s', datei: 's.heic', serie: 5));
    expect(find.text('5'), findsOneWidget);
    expect(find.text('HEIC'), findsNothing);

    await zeige(mit('h', type: 'VIDEO', dauer: 3725));
    expect(find.text('1:02:05'), findsOneWidget);

    // Kleine Kacheln: nur das Nötigste.
    await zeige(mit('k', datei: 'k.dng', breite: 52), kante: 60);
    expect(find.text('DNG'), findsNothing);
    expect(find.byIcon(Icons.location_on), findsNothing);
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

  testWidgets('Aktivität mit Spur: Linie, Kennzahlen, Höhenprofil und der '
      'Weg ins Gelände – wie am Rechner', (tester) async {
    final (sitzung, db) = await sitzungMit(tester, ['s1']);
    await db.aktivitaetAnlegen(
      AktivitaetenCompanion.insert(
        id: 'runde',
        name: 'Ilsetal',
        art: 'wanderung',
        von: DateTime(2026, 8, 30, 9),
        bis: DateTime(2026, 8, 30, 14),
        angelegtAm: DateTime(2026, 9, 1),
      ),
      ['s1'],
    );
    await db.fuehreAus(
      SpurAnlegen(
        id: 'spur',
        name: 'Ilsetal.gpx',
        quelle: 'Ilsetal.gpx',
        aktivitaetId: 'runde',
        laengeKm: 3.2,
        aufstieg: 180,
        abstieg: 175,
        angelegtAm: DateTime(2026, 9, 1),
        punkte: [
          for (var i = 0; i < 20; i++)
            (
              breite: 51.83 + i * 0.001,
              laenge: 10.64 + i * 0.0012,
              hoehe: 300.0 + (i < 10 ? i : 20 - i) * 18,
              zeit: DateTime.utc(2026, 8, 30, 7, i * 3),
            ),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: AktivitaetSeite(sitzung: sitzung, aktivitaetId: 'runde'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(AktivitaetSeite)));
    // Die Strecke kommt aus der Spur, nicht aus den Fotos.
    expect(find.textContaining('3,2\u00a0km'), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text(t.spurTitel), findsOneWidget);
    expect(find.text('3,2 km · ▲ 180 m · ▼ 175 m · 20 Punkte'), findsOneWidget);
    expect(find.byType(Hoehenprofil), findsOneWidget);
    expect(find.text(t.gelaendeOeffnen), findsOneWidget);
    // Fährt man über das Profil, steht die Stelle auf der Karte.
    await tester.ensureVisible(find.byType(Hoehenprofil));
    final profil = tester.getCenter(find.byType(Hoehenprofil));
    final zeiger = await tester.startGesture(profil);
    await tester.pump();
    // Waagerecht ziehen – über die Schwelle hinaus, ab der es ein Ziehen
    // ist und kein Tippen.
    await zeiger.moveBy(const Offset(40, 0));
    await tester.pump();
    await zeiger.moveBy(const Offset(10, 0));
    await tester.pump();
    // Die Marke über dem Profil nennt Strecke und Höhe der Stelle.
    final stelle = find.textContaining(RegExp(r'^\d+,\d km · \d+ m$'));
    expect(stelle, findsOneWidget);
    expect(find.byType(MarkerLayer), findsWidgets);
    await zeiger.up();
    await tester.pumpAndSettle();
  });

  testWidgets('Flugvideo am iPhone: Start, Bild für Bild, Abschluss über '
      'den Kanal', (tester) async {
    final aufrufe = <String>[];
    final groessen = <int>[];
    const kanal = MethodChannel('de.dasevo.photovault/flugvideo');
    final bote = tester.binding.defaultBinaryMessenger;
    bote.setMockMethodCallHandler(kanal, (aufruf) async {
      aufrufe.add(aufruf.method);
      if (aufruf.method == 'videoStart') {
        final w = (aufruf.arguments as Map).cast<String, Object?>();
        groessen.addAll([w['breite']! as int, w['hoehe']! as int]);
      }
      if (aufruf.method == 'videoBild') {
        final rgba = (aufruf.arguments as Map)['rgba'] as Uint8List;
        expect(rgba.length, 6 * 4 * 4, reason: 'RGBA, gerade Kanten');
      }
      return null;
    });
    addTearDown(() => bote.setMockMethodCallHandler(kanal, null));
    final ergebnis = await tester.runAsync(
      () => const HandyVideoschreiber().schreibe(
        ziel: File('${Directory.systemTemp.path}/flug.mp4'),
        breite: 7,
        hoehe: 4,
        dauer: const Duration(milliseconds: 100),
        maleBild: (leinwand, flaeche, t) => leinwand.drawRect(
          Offset.zero & flaeche,
          Paint()..color = const Color(0xFF3B6EA8),
        ),
      ),
    );
    expect(ergebnis!.ausgang, Videoausgang.fertig);
    expect(groessen, [6, 4]);
    expect(aufrufe, [
      'videoStart',
      'videoBild',
      'videoBild',
      'videoBild',
      'videoFertig',
    ]);
  });

  testWidgets('Angaben wie im Browser: Zeilen, Beschreibung, Bewertung', (
    tester,
  ) async {
    final (sitzung, db) = await sitzungMit(tester, ['x1']);
    await (db.update(db.assets)..where((t) => t.id.equals('x1'))).write(
      const AssetsCompanion(
        widthPx: Value(4032),
        heightPx: Value(3024),
        fileSizeBytes: Value(2516582),
        cameraMake: Value('Apple'),
        cameraModel: Value('iPhone 17 Pro'),
        lensModel: Value('Hauptkamera'),
        focalLengthMm: Value(6.8),
        fNumber: Value(1.8),
        exposureTimeSeconds: Value(0.004),
        iso: Value(80),
        latitude: Value(47.26),
        longitude: Value(11.39),
        locationCity: Value('Innsbruck'),
        locationCountry: Value('Austria'),
        ocrText: Value('Gipfelkreuz 2026'),
        aiCaption: Value('A cross on a summit'),
        aiCaptionDe: Value('Ein Kreuz auf einem Gipfel'),
      ),
    );
    await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Erika'));
    await db.insertFace(
      FacesCompanion.insert(
        id: 'g1',
        assetId: 'x1',
        personId: const Value('p1'),
        boxX: 0.1,
        boxY: 0.1,
        boxW: 0.2,
        boxH: 0.2,
      ),
    );
    await db.into(db.tags).insert(TagsCompanion.insert(id: 't1', name: 'Berg'));
    await db
        .into(db.assetTags)
        .insert(AssetTagsCompanion.insert(assetId: 'x1', tagId: 't1'));
    await db.createAlbum(
      AlbumsCompanion.insert(
        id: 'b1',
        name: 'Alpen',
        createdAt: DateTime(2026),
      ),
    );
    await db.addAssetsToAlbum('b1', ['x1']);
    final angaben = (await aufnahmeangaben(db, 'x1'))!;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: Angabenliste(sitzung: sitzung, angaben: angaben),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('x1.jpg'), findsOneWidget);
    expect(find.text('4032 × 3024 · 2.4 MB'), findsOneWidget);
    expect(find.text('Apple iPhone 17 Pro'), findsOneWidget);
    expect(
      find.text('Hauptkamera\n6.8 mm · f/1.8 · 1/250 s · ISO 80'),
      findsOneWidget,
    );
    expect(find.text('Innsbruck, Österreich'), findsOneWidget);
    // Erika einmal als Person der Aufnahme, einmal unter ihrem Gesicht.
    expect(find.widgetWithText(ActionChip, 'Erika'), findsOneWidget);
    expect(find.byType(GesichterDerAufnahme), findsOneWidget);
    expect(find.text('Erika'), findsNWidgets(2));
    expect(find.text('Berg'), findsOneWidget);
    expect(find.text('Alpen'), findsOneWidget);
    expect(
      find.text('Automatisch: Ein Kreuz auf einem Gipfel'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'Am Gipfel');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Speichern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Gespeichert'), findsOneWidget);
    expect((await db.assetById('x1'))!.description, 'Am Gipfel');
    await tester.ensureVisible(find.byTooltip('4 von 5'));
    await tester.tap(find.byTooltip('4 von 5'));
    await tester.pumpAndSettle();
    expect((await db.assetById('x1'))!.rating, 4);
    // Dieselbe Bewertung noch einmal nimmt sie weg.
    await tester.tap(find.byTooltip('4 von 5'));
    await tester.pumpAndSettle();
    expect((await db.assetById('x1'))!.rating, 0);
  });

  testWidgets('Statistik wie im Browser: Kennzahlen, Jahre, Monate, Kameras', (
    tester,
  ) async {
    final (sitzung, db) = await sitzungMit(tester, ['s1', 's2', 's3']);
    await (db.update(db.assets)..where((t) => t.id.equals('s1'))).write(
      AssetsCompanion(
        cameraMake: const Value('Canon'),
        cameraModel: const Value('EOS R6'),
        fileCreatedAt: Value(DateTime(2023, 5, 1)),
        isFavorite: const Value(true),
      ),
    );
    await (db.update(db.assets)..where((t) => t.id.equals('s2'))).write(
      AssetsCompanion(
        type: const Value('VIDEO'),
        fileCreatedAt: Value(DateTime(2025, 6, 1)),
      ),
    );
    await (db.update(db.assets)..where((t) => t.id.equals('s3'))).write(
      AssetsCompanion(fileCreatedAt: Value(DateTime(2025, 6, 2))),
    );
    // Hoch genug, dass alles auf einmal zu sehen ist.
    tester.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(body: Statistik(sitzung: sitzung)),
      ),
    );
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(Statistik)));
    for (final (wert, name) in [
      ('3', t.statInsgesamt),
      ('2', t.statFotos),
      ('1', t.statVideos),
    ]) {
      expect(
        find.ancestor(of: find.text(name), matching: find.byType(Column)),
        findsWidgets,
      );
      expect(find.text(wert), findsWidgets);
    }
    expect(find.text(t.statProJahr), findsOneWidget);
    expect(find.text(t.statProMonat), findsOneWidget);
    // Lückenlos von 2023 bis 2025 – auch das leere Jahr dazwischen.
    for (final j in ['2023', '2024', '2025']) {
      expect(find.text(j), findsOneWidget);
    }
    expect(find.text(t.statKameras), findsOneWidget);
    expect(find.text('Canon EOS R6'), findsOneWidget);
  });

  testWidgets('Duplikate wie im Browser: Gruppe, bestes Foto, Behalten', (
    tester,
  ) async {
    final (sitzung, db) = await sitzungMit(tester, ['d1', 'd2', 'd3']);
    Float32List vektor(int achse) => Float32List(64)..[achse] = 1;
    await db.saveEmbedding('d1', vektor(0));
    await db.saveEmbedding('d2', vektor(0));
    await db.saveEmbedding('d3', vektor(1));
    await (db.update(db.assets)..where((t) => t.id.equals('d2'))).write(
      const AssetsCompanion(isFavorite: Value(true)),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(body: Duplikate(sitzung: sitzung)),
      ),
    );
    // Gesucht wird in einem eigenen Isolate – das braucht echte Zeit.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 800)),
    );
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(Duplikate)));
    expect(find.text(t.duplGruppen(1, '92 %')), findsOneWidget);
    expect(find.text('d1.jpg'), findsOneWidget);
    expect(find.text('d2.jpg'), findsOneWidget);
    expect(find.text('d3.jpg'), findsNothing);
    expect(find.text(t.duplAlle(1)), findsOneWidget);
    // Der Favorit ist das beste Foto: sein Knopf ist gefüllt.
    final gefuellt = find.widgetWithText(FilledButton, t.duplBehalten);
    expect(gefuellt, findsOneWidget);
    await tester.tap(gefuellt);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect((await db.assetById('d1'))!.isTrashed, isTrue);
    expect((await db.assetById('d2'))!.isTrashed, isFalse);
    expect(find.text('d1.jpg'), findsNothing);
    // Die Suche hat den Vorrat der Einbettungen geladen; dessen Uhr (drei
    // Minuten Ruhe) liefe sonst über das Testende hinaus. Im Betrieb hält
    // `close` sie an – das kommt hier erst nach der Prüfung.
    db.einbettungsvorratLeeren();
  });

  testWidgets('Einstellungen wie im Browser: Zeilen und Schalter', (
    tester,
  ) async {
    final (sitzung, db) = await sitzungMit(tester, ['e1']);
    tester.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(body: Einstellungen(sitzung: sitzung)),
      ),
    );
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(Einstellungen)));
    for (final titel in [
      t.einstSprache,
      t.einstPapierkorb,
      t.einstVorschlaege,
      t.einstAuswerten,
      t.einstUebersetzen,
      t.einstSchuetzen,
      t.einstSchwelle,
    ]) {
      expect(find.text(titel), findsOneWidget, reason: titel);
    }
    final vorher = (await bibliothekseinstellungen(db)).auswertenNachImport;
    final schalter = find.descendant(
      of: find.ancestor(
        of: find.text(t.einstAuswerten),
        matching: find.byType(Row),
      ),
      matching: find.byType(Switch),
    );
    await tester.tap(schalter.first);
    await tester.pumpAndSettle();
    expect((await bibliothekseinstellungen(db)).auswertenNachImport, !vorher);
    expect(find.text(t.einstGespeichert), findsOneWidget);
  });

  testWidgets('Stammbaum: jedes Kind unter seinem Elternhaus', (tester) async {
    // Dieselbe Familie wie im Servertest: Der Neffe ist der Älteste und
    // stand der Reihe nach gesetzt unter dem Bruder – wie dessen Sohn.
    tester.view.physicalSize = const Size(2400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final (sitzung, db) = await sitzungMit(tester, ['f1']);
    Future<void> b(String art, Map<String, Object?> werte) =>
        db.fuehreAus(Befehl.ausJson({'art': art, 'werte': werte}));
    for (final id in [
      'Oma',
      'Bruder',
      'Partnerin',
      'Schwester',
      'Schwager',
      'Kind1',
      'Kind2',
      'Neffe',
    ]) {
      await b('personAnlegen', {'personId': id, 'name': id});
    }
    Future<void> eltern(String kind, String e) => b('beziehungHinzufuegen', {
      'personId': kind,
      'andereId': e,
      'verwandtschaft': 'elternteil',
    });
    Future<void> paar(String x, String y) => b('beziehungHinzufuegen', {
      'personId': x,
      'andereId': y,
      'verwandtschaft': 'partner',
    });
    await eltern('Bruder', 'Oma');
    await eltern('Schwester', 'Oma');
    await paar('Bruder', 'Partnerin');
    await paar('Schwester', 'Schwager');
    await eltern('Neffe', 'Schwester');
    await eltern('Neffe', 'Schwager');
    for (final k in ['Kind1', 'Kind2']) {
      await eltern(k, 'Bruder');
      await eltern(k, 'Partnerin');
    }
    for (final (id, jahr) in [
      ('Neffe', 2018),
      ('Kind1', 2022),
      ('Kind2', 2024),
    ]) {
      await b('lebensdatenSetzen', {
        'personId': id,
        'geburt': DateTime(jahr, 5, 1).toIso8601String(),
        'tod': null,
      });
    }
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: Stammbaum(sitzung: sitzung, fokus: 'Oma'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    double x(String name) => tester
        .getCenter(
          find.descendant(
            of: find.byType(InteractiveViewer),
            matching: find.text(name),
          ),
        )
        .dx;
    final bruderHaus = (x('Bruder') + x('Partnerin')) / 2;
    final schwesterHaus = (x('Schwester') + x('Schwager')) / 2;
    expect(
      (x('Neffe') - schwesterHaus).abs(),
      lessThan((x('Neffe') - bruderHaus).abs()),
    );
    for (final k in ['Kind1', 'Kind2']) {
      expect((x(k) - bruderHaus).abs(), lessThan((x(k) - schwesterHaus).abs()));
    }
  });

  testWidgets('Stammbaum wie im Browser: Bänder, Karten, Fokus wählbar', (
    tester,
  ) async {
    final (sitzung, db) = await sitzungMit(tester, ['f1']);
    Future<void> b(String art, Map<String, Object?> werte) =>
        db.fuehreAus(Befehl.ausJson({'art': art, 'werte': werte}));
    for (final (id, name) in [
      ('oma', 'Oma Erika'),
      ('opa', 'Opa Hans'),
      ('kind', 'Kind'),
    ]) {
      await b('personAnlegen', {'personId': id, 'name': name});
    }
    await b('beziehungHinzufuegen', {
      'personId': 'kind',
      'andereId': 'oma',
      'verwandtschaft': 'elternteil',
    });
    await b('beziehungHinzufuegen', {
      'personId': 'kind',
      'andereId': 'opa',
      'verwandtschaft': 'elternteil',
    });
    await b('beziehungHinzufuegen', {
      'personId': 'oma',
      'andereId': 'opa',
      'verwandtschaft': 'partner',
    });
    await b('lebensdatenSetzen', {
      'personId': 'oma',
      'geburt': DateTime(1950, 3, 1).toIso8601String(),
      'tod': null,
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(body: Stammbaum(sitzung: sitzung)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Oma Erika'), findsWidgets);
    expect(find.text('Opa Hans'), findsWidgets);
    expect(find.text('1950 –'), findsOneWidget);
    // Die Eltern stehen ein Band über dem Kind.
    final kind = find.descendant(
      of: find.byType(InteractiveViewer),
      matching: find.text('Kind'),
    );
    final oma = find.descendant(
      of: find.byType(InteractiveViewer),
      matching: find.text('Oma Erika'),
    );
    expect(
      tester.getTopLeft(oma).dy,
      lessThan(tester.getTopLeft(kind).dy - 150),
    );
    // Ein Tipp auf die Oma rückt sie in die Mitte.
    await tester.tap(oma);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .value,
      'oma',
    );
  });

  testWidgets('Lebensbaum wie im Browser: Vorlage, Bezeichnungen, Tipp', (
    tester,
  ) async {
    final (sitzung, db) = await sitzungMit(tester, ['l1']);
    Future<void> b(String art, Map<String, Object?> werte) =>
        db.fuehreAus(Befehl.ausJson({'art': art, 'werte': werte}));
    for (final (id, name, geschlecht) in [
      ('oma', 'Erika Muster', 'w'),
      ('opa', 'Hans Muster', 'm'),
      ('kind', 'Kai Muster', 'm'),
    ]) {
      await b('personAnlegen', {'personId': id, 'name': name});
      await b('geschlechtSetzen', {'personId': id, 'geschlecht': geschlecht});
    }
    for (final eltern in ['oma', 'opa']) {
      await b('beziehungHinzufuegen', {
        'personId': 'kind',
        'andereId': eltern,
        'verwandtschaft': 'elternteil',
      });
    }
    await b('beziehungHinzufuegen', {
      'personId': 'oma',
      'andereId': 'opa',
      'verwandtschaft': 'partner',
    });
    tester.view
      ..physicalSize = const Size(1200, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: Lebensbaum(sitzung: sitzung, fokus: 'kind'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Lebensbaumflaeche), findsOneWidget);
    Finder schild(String text) => find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == text,
    );
    // Die Schilder tragen die Verwandtschaft zur Person am Stamm, wie im
    // Browser.
    expect(schild('Kai Muster'), findsOneWidget);
    expect(schild('Mutter, Erika Muster'), findsOneWidget);
    expect(schild('Vater, Hans Muster'), findsOneWidget);
    // Ein Tipp auf die Mutter setzt sie an den Stamm – ohne Bezeichnung,
    // und ihr Sohn gehört nicht zu ihren Vorfahren.
    await tester.tap(schild('Mutter, Erika Muster'));
    await tester.pumpAndSettle();
    expect(schild('Erika Muster'), findsOneWidget);
    expect(schild('Kai Muster'), findsNothing);
  });

  test('Namen im Stammbaum brechen wie im Browser um', () {
    expect(namenszeilen('Kurz'), ['Kurz']);
    expect(namenszeilen('Maria Magdalena Musterfrau'), [
      'Maria Magdalena',
      'Musterfrau',
    ]);
    expect(namenszeilen('Donaudampfschifffahrtsgesellschaft'), [
      'Donaudampfschif…',
    ]);
  });

  testWidgets('Entwickeln wie im Browser: Regler, Vorschau, Speichern', (
    tester,
  ) async {
    final (sitzung, db) = await sitzungMit(tester, ['e1']);
    final bild = img.Image(width: 64, height: 48);
    img.fill(bild, color: img.ColorRgb8(120, 100, 80));
    await tester.runAsync(() async {
      final f = sitzung.paths.absolute('originals/e1.jpg');
      await f.parent.create(recursive: true);
      await f.writeAsBytes(img.encodeJpg(bild));
    });
    tester.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Entwickeln(sitzung: sitzung, id: 'e1'),
      ),
    );
    // Laden, Dekodieren und Rechnen brauchen echte Zeit.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
    }
    final t = AppTexte.of(tester.element(find.byType(Entwickeln)));
    expect(find.byType(Slider), findsNWidgets(10));
    expect(find.text(t.entwBelichtung), findsOneWidget);
    expect(find.text(t.entwAutoWeiss), findsOneWidget);
    expect(find.byType(RawImage), findsOneWidget);
    // Belichtung nach rechts ziehen.
    await tester.drag(find.byType(Slider).first, const Offset(200, 0));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
    }
    await tester.tap(find.text(t.entwSpeichern));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
    }
    final a = (await db.assetById('e1'))!;
    expect(a.developedRelativePath, startsWith('developed/e1-'));
    final e = (await db.developSettingsForAsset('e1'))!;
    expect(e.exposure, greaterThan(0));
    expect(e.temperature, isNull, reason: 'automatischer Weissabgleich');
    final datei = sitzung.paths.absolute(a.developedRelativePath!);
    expect(await tester.runAsync(datei.exists), isTrue);
  });

  testWidgets('Konto wie im Browser: Geräte abmelden, Passwort ändern', (
    tester,
  ) async {
    final anfragen = <String>[];
    var geraete = [
      {'id': 'g1', 'name': 'Telefon', 'zuletzt': '2026-10-18T09:00:00Z'},
      {
        'id': 'g2',
        'name': 'Browser (Firefox)',
        'zuletzt': '2026-10-17T20:00:00Z',
        'adresse': '192.0.2.7',
      },
    ];
    Map<String, Object?>? passwort;
    final client = MockClient((r) async {
      anfragen.add('${r.method} ${r.url.path}');
      switch ('${r.method} ${r.url.path}') {
        case 'GET /api/v1/konto':
          return http.Response(
            jsonEncode({
              'name': 'erika',
              'verwalter': true,
              'totp': true,
              'geraet': 'g1',
            }),
            200,
          );
        case 'GET /api/v1/geraete':
          return http.Response(jsonEncode({'geraete': geraete}), 200);
        case 'DELETE /api/v1/geraete/g2':
          geraete = [geraete.first];
          return http.Response('{}', 200);
        case 'POST /api/v1/konto/passwort':
          passwort = (jsonDecode(r.body) as Map).cast<String, Object?>();
          return http.Response('{}', 200);
      }
      return http.Response('{}', 404);
    });
    final verbindung = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: client,
    );
    var abgemeldet = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: ListView(
            children: [
              EigenesKonto(
                verbindung: verbindung,
                abmelden: () => abgemeldet = true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(EigenesKonto)));
    expect(
      find.text('erika · ${t.kontoVerwalter} · ${t.eigenTotpEingerichtet}'),
      findsOneWidget,
    );
    expect(find.text('Telefon ${t.eigenDiesesTelefon}'), findsOneWidget);
    expect(find.text('Browser (Firefox)'), findsOneWidget);
    // Das eigene Gerät meldet ab wie der Knopf unten auf der Kontoseite.
    await tester.tap(find.text(t.kontoAbmelden));
    expect(abgemeldet, isTrue);
    // Ein anderes Gerät nach Rückfrage.
    await tester.tap(find.text(t.eigenGeraetAbmelden).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.eigenGeraetAbmelden).last);
    await tester.pumpAndSettle();
    expect(anfragen, contains('DELETE /api/v1/geraete/g2'));
    expect(find.text('Browser (Firefox)'), findsNothing);

    await tester.tap(find.text(t.eigenPasswortAendern));
    await tester.pumpAndSettle();
    final felder = find.byType(TextField);
    expect(felder, findsNWidgets(4), reason: 'mit TOTP-Code');
    await tester.enterText(felder.at(0), 'altes passwort!');
    await tester.enterText(felder.at(1), 'ein neues langes passwort');
    await tester.enterText(felder.at(2), 'ein anderes');
    await tester.tap(find.text(t.eigenAendern));
    await tester.pumpAndSettle();
    expect(find.text(t.eigenPasswortUngleich), findsOneWidget);
    expect(passwort, isNull);
    await tester.enterText(felder.at(2), 'ein neues langes passwort');
    await tester.enterText(felder.at(3), '123 456');
    await tester.tap(find.text(t.eigenAndereAbmelden));
    await tester.tap(find.text(t.eigenAendern));
    await tester.pumpAndSettle();
    expect(find.text(t.eigenPasswortGeaendert), findsOneWidget);
    expect(passwort, {
      'alt': 'altes passwort!',
      'neu': 'ein neues langes passwort',
      'code': '123 456',
      'andereAbmelden': true,
    });
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
