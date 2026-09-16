import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/ortsansicht_screen.dart';
import 'package:photo_vault/services/ortsuebersicht.dart';
import 'package:photo_vault/services/reverse_geocoder.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// Die Ortsansicht: ein Bildschirm für Land, Region und Ort.
///
/// Geprüft wird vor allem der **Weg nach unten** – von Deutschland zu
/// Niedersachsen zu Hannover – und dass jede Ebene nur ihre eigenen
/// Aufnahmen zählt.
Future<ReverseGeocoder> _geokodierer(Directory wurzel) async {
  final staedte = File(p.join(wurzel.path, 'cities1000.txt'));
  await staedte.writeAsString(
    '2950159\tBerlin\tBerlin\t\t52.52437\t13.41053\tP\tPPLC\tDE\t\t16\t\t\t\t3600000\t\t74\tEurope/Berlin\t2023\n'
    '2910831\tHannover\tHannover\t\t52.37052\t9.73322\tP\tPPLA\tDE\t\t06\t\t\t\t515140\t\t55\tEurope/Berlin\t2023\n'
    '2857458\tOldenburg\tOldenburg\t\t53.14118\t8.21467\tP\tPPLA3\tDE\t\t06\t\t\t\t159218\t\t7\tEurope/Berlin\t2023\n'
    '2862026\tCelle\tCelle\t\t52.62264\t10.08047\tP\tPPLA3\tDE\t\t06\t\t\t\t71010\t\t40\tEurope/Berlin\t2023\n',
  );
  final regionen = File(p.join(wurzel.path, 'admin1CodesASCII.txt'));
  await regionen.writeAsString('DE.16\tState of Berlin\tState of Berlin\t2950157\n'
      'DE.06\tLower Saxony\tLower Saxony\t2862926\n'
      'DE.02\tBavaria\tBavaria\t2951839\n');
  final laender = File(p.join(wurzel.path, 'countryInfo.txt'));
  await laender.writeAsString('# Kopfzeile\n'
      'DE\tDEU\t276\tDE\tGermany\tBerlin\t357021\t82927922\tEU\t.de\tEUR\tEuro\t49\t\t\tde-DE\t2921044\t\t\n');
  return ReverseGeocoder.loadFromFiles(
      citiesFile: staedte, admin1File: regionen, countryFile: laender);
}

void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_ort_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths =
          await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')))
      ..geocoder = await _geokodierer(wurzel);
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
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
            latitude: const Value(52.37),
            longitude: const Value(9.73),
            locationCountry: Value(land),
            locationState: Value(region),
            locationCity: Value(ort),
          ));

  Future<void> zeige(
    WidgetTester tester, {
    Ortsebene ebene = Ortsebene.land,
    String schluessel = 'DE',
    String name = 'Germany',
  }) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: OrtsansichtScreen(
        library: library,
        ebene: ebene,
        schluessel: schluessel,
        name: name,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('ein Land zeigt seine Regionen, auch die leeren',
      (tester) async {
    await aufnahme('a1',
        land: 'Germany', region: 'Lower Saxony', ort: 'Hannover');
    await zeige(tester);

    expect(find.text('Germany'), findsWidgets);
    // Alle drei Regionen des Datensatzes, nicht nur die mit Fotos: Erst
    // damit ist die Liste eine Landkarte und kein Spiegel der Fotos.
    expect(find.text('Lower Saxony'), findsOneWidget);
    expect(find.text('Bavaria'), findsOneWidget);
    expect(find.text('State of Berlin'), findsOneWidget);
    expect(find.text('Regionen · 1 von 3'), findsOneWidget);
  });

  testWidgets('die Hauptstadt steht im Kopf', (tester) async {
    await zeige(tester);
    expect(find.textContaining('Berlin'), findsWidgets);
  });

  testWidgets('der Weg fuehrt von Land ueber Region zu Ort', (tester) async {
    await aufnahme('a1',
        land: 'Germany', region: 'Lower Saxony', ort: 'Hannover');
    await aufnahme('a2',
        land: 'Germany', region: 'Lower Saxony', ort: 'Oldenburg');
    await aufnahme('a3',
        land: 'Germany', region: 'State of Berlin', ort: 'Berlin');
    await zeige(tester);
    expect(find.text('3 Fotos'), findsOneWidget);

    await tester.tap(find.text('Lower Saxony'));
    await tester.pumpAndSettle();

    // Die Region zaehlt nur ihre eigenen zwei – Berlin bleibt draussen.
    expect(find.text('2 Fotos'), findsOneWidget);
    expect(find.text('Hannover'), findsWidgets);
    expect(find.text('Oldenburg'), findsWidgets);
    // Und Celle steht als bekannter, aber unbesuchter Ort dabei.
    expect(find.text('Celle'), findsOneWidget);

    await tester.tap(find.text('Hannover').last);
    await tester.pumpAndSettle();
    expect(find.text('Ein Foto'), findsOneWidget);
    // Unter einem Ort kommt nichts mehr.
    expect(find.textContaining('Orte ·'), findsNothing);
  });

  testWidgets('markieren wirkt auf den Fortschritt darueber', (tester) async {
    await zeige(tester);
    expect(find.text('Regionen · 0 von 3'), findsOneWidget);

    await tester.tap(find.text('Bavaria'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Besucht'));
    await tester.pumpAndSettle();
    expect((await db.alleOrtsmarken()).single.schluessel, 'DE.02');

    // Zurueck – und der Balken des Landes hat es mitbekommen.
    Navigator.of(tester.element(find.text('Bavaria').first)).pop();
    await tester.pumpAndSettle();
    expect(find.text('Regionen · 1 von 3'), findsOneWidget);
  });

  testWidgets('ein zweites Antippen nimmt die Marke zurueck', (tester) async {
    await zeige(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Geplant'));
    await tester.pumpAndSettle();
    expect((await db.alleOrtsmarken()).single.status, 'geplant');

    await tester.tap(find.widgetWithText(ChoiceChip, 'Geplant'));
    await tester.pumpAndSettle();
    expect(await db.alleOrtsmarken(), isEmpty);
  });

  testWidgets('ohne Fotos und ohne Unterebene steht ein Satz da',
      (tester) async {
    await zeige(tester,
        ebene: Ortsebene.ort,
        schluessel: 'Germany|Lower Saxony|Celle',
        name: 'Celle');
    expect(find.textContaining('Von hier gibt es noch nichts'), findsOneWidget);
  });

  testWidgets('ohne Datensatz bleibt die Ansicht leer statt zu werfen',
      (tester) async {
    library.geocoder = null;
    await zeige(tester);
    expect(find.byType(OrtsansichtScreen), findsOneWidget);
    expect(find.textContaining('Von hier gibt es noch nichts'), findsOneWidget);
  });
}
