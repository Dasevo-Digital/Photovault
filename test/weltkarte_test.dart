import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/weltkarte_screen.dart';
import 'package:photo_vault/services/reverse_geocoder.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/screens/ortsansicht_screen.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/widgets/meldungsfenster.dart';

/// Die Weltkarte: Steht für jedes belegte Land ein Punkt, sieht man einer
/// Marke an, woher sie stammt, und lässt sich von Hand markieren?
Future<ReverseGeocoder> _geokodierer(Directory wurzel) async {
  final staedte = File(p.join(wurzel.path, 'cities1000.txt'));
  await staedte.writeAsString(
    // Berlin ist Hauptstadt und hat weniger Einwohner als Hamburg – der
    // Landpunkt muss trotzdem Berlin sein.
    '2950159\tBerlin\tBerlin\t\t52.52437\t13.41053\tP\tPPLC\tDE\t\t16\t\t\t\t100\t\t74\tEurope/Berlin\t2023\n'
    '2911298\tHamburg\tHamburg\t\t53.55073\t9.99302\tP\tPPLA\tDE\t\t04\t\t\t\t1739117\t\t6\tEurope/Berlin\t2023\n'
    '3169070\tRoma\tRoma\t\t41.89193\t12.51133\tP\tPPLC\tIT\t\t07\t\t\t\t2318895\t\t20\tEurope/Rome\t2023\n',
  );
  final regionen = File(p.join(wurzel.path, 'admin1CodesASCII.txt'));
  await regionen.writeAsString('DE.16\tBerlin\tBerlin\t2950157\n'
      'DE.04\tHamburg\tHamburg\t2911297\n'
      'IT.07\tLazio\tLazio\t3174976\n'
      'FR.11\tIle-de-France\tIle-de-France\t3012874\n');
  final laender = File(p.join(wurzel.path, 'countryInfo.txt'));
  await laender.writeAsString(
    '# Kopfzeile\n'
    'DE\tDEU\t276\tDE\tDeutschland\tBerlin\t357021\t82927922\tEU\t.de\tEUR\tEuro\t49\t\t\tde-DE\t2921044\t\t\n'
    'IT\tITA\t380\tIT\tItalien\tRom\t301230\t60431283\tEU\t.it\tEUR\tEuro\t39\t\t\tit-IT\t3175395\t\t\n'
    'FR\tFRA\t250\tFR\tFrankreich\tParis\t547030\t66987244\tEU\t.fr\tEUR\tEuro\t33\t\t\tfr-FR\t3017382\t\t\n',
  );
  return ReverseGeocoder.loadFromFiles(
      citiesFile: staedte, admin1File: regionen, countryFile: laender);
}

void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late LibraryState library;
  late ReverseGeocoder geo;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_welt_');
    db = AppDatabase(NativeDatabase.memory());
    geo = await _geokodierer(tempRoot);
    library = LibraryState()
      ..db = db
      ..paths =
          await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')))
      ..geocoder = geo;
  });

  tearDown(() async {
    // Der Meldungsdienst ist ein Einzelstueck – was hier stehen bleibt,
    // steht im naechsten Test noch da.
    melde.verlaufLeeren();
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<void> aufnahme(String id,
          {String? land, String? region, String? ort}) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'pruef-$id',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2024, 6, 3),
            importedAt: DateTime(2024),
            latitude: const Value(53.55),
            longitude: const Value(9.99),
            locationCountry: Value(land),
            locationState: Value(region),
            locationCity: Value(ort),
          ));

  Future<void> zeige(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      builder: (context, kind) => mitMeldungen(kind),
      home: WeltkarteScreen(library: library),
    ));
    await tester.pumpAndSettle();
  }

  group('die Punkte des Datensatzes', () {
    test('der Landpunkt ist die Hauptstadt, nicht die groesste Stadt', () {
      // Hamburg hat in diesem Auszug 17-mal so viele Einwohner wie Berlin.
      // Ein Punkt nach Einwohnerzahl saesse also falsch.
      final punkt = geo.landpunkt('DE')!;
      expect(punkt.breite, closeTo(52.524, 0.001));
      expect(punkt.laenge, closeTo(13.410, 0.001));
    });

    test('Kleinschreibung findet dasselbe Land', () {
      expect(geo.landpunkt('de'), geo.landpunkt('DE'));
    });

    test('die Region bekommt ihren groessten bekannten Ort', () {
      final punkt = geo.regionspunkt('DE.04')!;
      expect(punkt.breite, closeTo(53.550, 0.001));
    });

    test('ein Ort liegt auf seiner eigenen Koordinate', () {
      final punkt = geo.ortspunkt('IT', 'Roma')!;
      expect(punkt.breite, closeTo(41.891, 0.001));
    });

    test('was der Datensatz nicht kennt, gibt null statt einer Vermutung', () {
      expect(geo.landpunkt('FR'), isNull);
      expect(geo.regionspunkt('DE.99'), isNull);
      expect(geo.ortspunkt('DE', 'Atlantis'), isNull);
    });
  });

  testWidgets('fuer jedes belegte Land, jede Region und jeden Ort ein Punkt',
      (tester) async {
    await aufnahme('a1',
        land: 'Deutschland', region: 'Hamburg', ort: 'Hamburg');
    await zeige(tester);
    // Land, Region und Ort – drei Ebenen, drei Marken. „Hamburg" zweimal,
    // weil die Stadt zugleich ihre Region ist.
    expect(find.byTooltip('Deutschland'), findsOneWidget);
    expect(find.byTooltip('Hamburg'), findsNWidgets(2));
  });

  testWidgets('die Ebenen lassen sich einzeln abschalten', (tester) async {
    await aufnahme('a1',
        land: 'Deutschland', region: 'Hamburg', ort: 'Hamburg');
    await zeige(tester);
    expect(find.byTooltip('Deutschland'), findsOneWidget);

    // Die Ebenen stehen im Menü in der Titelleiste. Auf der Karte selbst
    // liegt nur noch die Markierleiste unten – eine Karte über dem Bild
    // verdeckte genau das Land, das man anklicken will.
    await tester.tap(find.byTooltip('Ebenen'));
    await tester.pumpAndSettle();
    // Der letzte Treffer ist der im Menü: Die Überlagerung liegt im Baum
    // hinter der Markierleiste, die dasselbe Wort trägt.
    await tester.tap(find.text('Länder').last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Deutschland'), findsNothing);
    // Die anderen bleiben.
    expect(find.byTooltip('Hamburg'), findsNWidgets(2));
  });

  // -------------------------------------------------------------------
  // Der Klick auf die Karte
  // -------------------------------------------------------------------

  /// Der Bildpunkt, an dem eine Koordinate auf dem Schirm liegt.
  ///
  /// Die Karte startet auf 30°N/10°O bei Stufe 2. Umgerechnet wird nach
  /// Mercator, so wie flutter_map es selbst tut; die Probe darauf ist der
  /// erste Test unten, der ein bestimmtes Land erwartet und es trifft.
  Offset stelle(WidgetTester tester, double breite, double laenge) {
    const stufe = 2.0;
    final welt = 256 * math.pow(2, stufe).toDouble();
    double y(double b) {
      final r = b * math.pi / 180;
      return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * welt;
    }

    final mitte = tester.getCenter(find.byType(FlutterMap));
    return Offset(
      mitte.dx + (laenge - 10) * welt / 360,
      mitte.dy + (y(breite) - y(30)),
    );
  }

  /// Ein Klick auf die Karte.
  ///
  /// **Das Warten ist nicht willkürlich.** flutter_map hält einen
  /// einzelnen Klick zurück, bis feststeht, dass kein Doppelklick daraus
  /// wird – über einen Strom mit Zeitgrenze. `pumpAndSettle` treibt keine
  /// Uhr, die kein Bild anfordert; ohne das ausdrückliche `pump` mit
  /// Dauer kommt `onTap` nie an.
  /// Der Wortlaut der zuletzt gemeldeten Rückmeldung.
  ///
  /// **Nicht auf dem Schirm nachsehen.** `klicke` endet mit
  /// `pumpAndSettle`, und das läuft, bis keine Bilder mehr anstehen – der
  /// ablaufende Balken der Meldung ist so ein Bild. Die Karte ist danach
  /// planmässig verblasst; im Verlauf steht sie noch.
  String letzteMeldung() => melde.verlauf.first.text;

  Future<void> klicke(WidgetTester tester, double breite, double laenge) async {
    await tester.tapAt(stelle(tester, breite, laenge));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  testWidgets('ein Klick markiert das Land unter dem Zeiger', (tester) async {
    await zeige(tester);
    // Kassel, mitten in Deutschland. Der Umriss entscheidet – der
    // Testdatensatz kennt als Städte nur Berlin, Hamburg und Rom, und
    // keine davon liegt hier.
    await klicke(tester, 51.3, 9.5);

    final marken = await db.alleOrtsmarken();
    expect(marken, hasLength(1));
    expect(marken.single.art, 'land');
    expect(marken.single.schluessel, 'DE');
    expect(marken.single.status, 'besucht');
    expect(find.byTooltip('Deutschland'), findsOneWidget);
  });

  testWidgets('derselbe Klick nimmt die Marke wieder weg', (tester) async {
    // Die Marke steht schon; geprüft wird der Weg zurück.
    //
    // **Warum nicht zweimal hintereinander geklickt wird:** flutter_map
    // trennt Einzel- von Doppelklick über einen Abstand von 48
    // Bildpunkten und eine Zeitgrenze von 250 ms. Unter der Testuhr
    // greift nur der Abstand – bei Stufe 2 ist ganz Deutschland keine 30
    // Bildpunkte hoch, zwei Klicks hinein wären also immer ein
    // Doppelklick, gleichgültig wie lange dazwischen gewartet wird.
    await db.setzeOrtsmarke(OrtsmarkenCompanion.insert(
      art: 'land',
      schluessel: 'DE',
      name: 'Deutschland',
      status: 'besucht',
      angelegtAm: DateTime(2024),
    ));
    await zeige(tester);
    expect(await db.alleOrtsmarken(), hasLength(1));

    // München und nicht Kassel: Der Landpunkt sitzt auf Berlin, und seine
    // Marke ist 26 Bildpunkte breit – bei Stufe 2 deckt sie Kassel mit ab.
    await klicke(tester, 48.1, 11.6);
    expect(await db.alleOrtsmarken(), isEmpty);
    expect(letzteMeldung(), '„Deutschland“ ist nicht mehr markiert.');
  });

  testWidgets('auf offener See wird nichts markiert', (tester) async {
    await zeige(tester);
    // Mitten im Atlantik. Die Suche über die nächstgelegene Stadt würde
    // hier noch ein Land liefern; der Umriss sagt „keines".
    await klicke(tester, 30.0, -40.0);
    expect(await db.alleOrtsmarken(), isEmpty);
    expect(letzteMeldung(), 'An dieser Stelle kennt der Datensatz keinen Ort.');
  });

  testWidgets('auf der Stufe Region trifft derselbe Klick das Bundesland',
      (tester) async {
    await zeige(tester);
    await tester.tap(find.text('Regionen'));
    await tester.pumpAndSettle();
    await klicke(tester, 53.55, 9.99); // Hamburg

    final marken = await db.alleOrtsmarken();
    expect(marken.single.art, 'region');
    expect(marken.single.schluessel, 'DE.04');
  });

  testWidgets('mit „Geplant" wird geplant und nicht besucht', (tester) async {
    await zeige(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Geplant'));
    await tester.pumpAndSettle();
    await klicke(tester, 51.3, 9.5);

    expect((await db.alleOrtsmarken()).single.status, 'geplant');
  });

  testWidgets('was die Fotos belegen, bekommt keinen Haken von Hand',
      (tester) async {
    await aufnahme('a1', land: 'Deutschland');
    await zeige(tester);
    // München und nicht Kassel: Der Landpunkt sitzt auf Berlin, und
    // dessen Marke ist 26 Bildpunkte breit – bei Stufe 2 deckt sie Kassel
    // mit ab. Ein Klick darauf öffnet das Blatt, statt zu markieren.
    await klicke(tester, 48.1, 11.6);

    // Kein Eintrag – sonst liesse sich hinterher nicht mehr sagen, ob der
    // Haken auf einem Bild beruht oder auf einer Erinnerung.
    expect(await db.alleOrtsmarken(), isEmpty);
    expect(letzteMeldung(), '„Deutschland“ belegen deine Fotos bereits.');
  });

  testWidgets('ein Klick auf eine Marke fuehrt in den Ort', (tester) async {
    // **Was hier war** ist die naheliegendere Frage an einen Punkt auf
    // einer Fotokarte als „welchen Haken setze ich". Das Blatt mit den
    // Markierknöpfen ist deshalb entfallen; die Ortsansicht trägt sie
    // ohnehin, und ein zweiter Weg zum Markieren wäre einer zu viel.
    await db.setzeOrtsmarke(OrtsmarkenCompanion.insert(
      art: 'land',
      schluessel: 'IT',
      name: 'Italien',
      status: 'besucht',
      angelegtAm: DateTime(2024),
    ));
    await zeige(tester);
    expect(find.byTooltip('Italien'), findsOneWidget);

    await tester.tap(find.byTooltip('Italien'));
    await tester.pumpAndSettle();
    expect(find.byType(OrtsansichtScreen), findsOneWidget);
    // Und dort steht der Haken, den die Karte zeigt.
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Besucht'))
            .selected,
        isTrue);
  });

  testWidgets('und die Marke laesst sich dort zuruecknehmen', (tester) async {
    await db.setzeOrtsmarke(OrtsmarkenCompanion.insert(
      art: 'land',
      schluessel: 'IT',
      name: 'Italien',
      status: 'besucht',
      angelegtAm: DateTime(2024),
    ));
    await zeige(tester);
    await tester.tap(find.byTooltip('Italien'));
    await tester.pumpAndSettle();

    // Ein zweites Antippen des Hakens nimmt ihn zurueck.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Besucht'));
    await tester.pumpAndSettle();
    expect(await db.alleOrtsmarken(), isEmpty);

    // Und zurueck auf der Karte ist der Punkt weg. `pageBack` sucht
    // einen Cupertino-Zurueckknopf und findet in einer Material-App
    // keinen – der Weg geht ueber den Navigator selbst.
    Navigator.of(tester.element(find.byType(OrtsansichtScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Italien'), findsNothing);
  });

  testWidgets('ohne Datensatz bleibt die Karte leer statt zu werfen',
      (tester) async {
    library.geocoder = null;
    await zeige(tester);
    expect(find.byType(FlutterMap), findsOneWidget);
  });
}
