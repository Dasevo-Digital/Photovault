import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/reverse_geocoder.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:flutter/material.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/selection_action_bar.dart';
import 'package:provider/provider.dart';

/// **Wer den Ort korrigiert, wurde den alten Namen nicht los.**
///
/// Der Anlass ist ein Phantomland: 31 Aufnahmen einer Olympus TG-810 von
/// 2013 stehen in der Bibliothek unter „Baghlān, Afghanistan". Die
/// Koordinaten sind kein Lesefehler – mit exiftool gegengelesen steht
/// wirklich 36,098° N / 68,656° O in der Datei, samt „GPS Status: A". Die
/// Kamera hat sich verortet, und zwar falsch.
///
/// Dagegen kann die App nichts. Wogegen sie etwas kann: dass sich das
/// **korrigieren** lässt. `setLocation` schrieb nur die Koordinaten; die
/// ausgeschriebenen Namen blieben stehen. Und weil der Nachtrag
/// ([AppDatabase.assetsForLocationNameBackfill]) nur dort einträgt, wo
/// noch gar kein Land steht, blieben sie für immer: Ein Foto, dessen Ort
/// man nach Niedersachsen zieht, hiess weiter „Baghlān, Afghanistan" – im
/// Infoblatt, in den Ortsgruppen der Übersicht, im Suchfilter.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_ort_');
    db = AppDatabase(NativeDatabase.memory());
    final staedte = File(p.join(wurzel.path, 'cities1000.txt'));
    await staedte.writeAsString(
      '2910831\tHannover\tHannover\t\t52.37052\t9.73322\tP\tPPLA\tDE\t\t06\t\t\t\t515140\t\t55\tEurope/Berlin\t2023\n',
    );
    final regionen = File(p.join(wurzel.path, 'admin1CodesASCII.txt'));
    await regionen.writeAsString('DE.06\tLower Saxony\tLower Saxony\t2862926\n');
    final laender = File(p.join(wurzel.path, 'countryInfo.txt'));
    await laender.writeAsString(
      '# Kopf\n'
      'DE\tDEU\t276\tDE\tGermany\tBerlin\t357021\t82927922\tEU\t.de\tEUR\tEuro\t49\t\t\tde-DE\t2921044\t\t\n',
    );
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')))
      ..geocoder = await ReverseGeocoder.loadFromFiles(
          citiesFile: staedte, admin1File: regionen, countryFile: laender);
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  /// Eine Aufnahme, wie die TG-810 sie hinterlassen hat.
  Future<void> phantom(String id) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.JPG',
            relativePath: 'originals/$id.jpg',
            checksum: 'pruef-$id',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2013, 6, 3),
            importedAt: DateTime(2026),
            latitude: const Value(36.098),
            longitude: const Value(68.656),
            locationCountry: const Value('Afghanistan'),
            locationState: const Value('Baghlan'),
            locationCity: const Value('Baghlān'),
          ));

  Future<AssetData> zeile(String id) async => (await db.assetById(id))!;

  test('ein korrigierter Ort bekommt die richtigen Namen', () async {
    await phantom('a');
    await library.setzeOrtVonHand(['a'], 52.37052, 9.73322);

    final a = await zeile('a');
    expect(a.locationCity, 'Hannover');
    expect(a.locationState, 'Lower Saxony');
    expect(a.locationCountry, 'Germany',
        reason: 'sonst zaehlte die Aufnahme weiter fuer Afghanistan');
  });

  test('ein entfernter Ort laesst auch keinen Namen zurueck', () async {
    await phantom('a');
    await library.setzeOrtVonHand(['a'], null, null);

    final a = await zeile('a');
    expect(a.latitude, isNull);
    expect(a.locationCountry, isNull);
    expect(a.locationCity, isNull);
  });

  test('eine ganze Auswahl auf einmal', () async {
    // Eine Kamera mit verrutschtem Empfaenger vergibt den falschen Ort
    // nicht einmal, sondern an alles aus dieser Woche.
    for (var i = 0; i < 5; i++) {
      await phantom('a$i');
    }
    await library.setzeOrtVonHand(
        [for (var i = 0; i < 5; i++) 'a$i'], null, null);
    for (var i = 0; i < 5; i++) {
      expect((await zeile('a$i')).locationCountry, isNull);
    }
    expect(await db.besuchteOrte(), isEmpty);
  });

  test('ohne Datensatz bleibt es bei der Koordinate', () async {
    // Die Gegenprobe: Der Nachtrag darf nicht der einzige Weg sein, sonst
    // haenge die Korrektur an einer Datei, die vielleicht gar nicht da ist.
    library.geocoder = null;
    await phantom('a');
    await library.setzeOrtVonHand(['a'], 52.37052, 9.73322);

    final a = await zeile('a');
    expect(a.latitude, closeTo(52.37052, 1e-6));
    expect(a.locationCountry, isNull,
        reason: 'lieber gar kein Name als der alte, falsche');
  });

  test('der Nachtrag findet die geleerte Zeile wieder', () async {
    // Ohne das Leeren waere sie fuer den Nachtrag unsichtbar: Er sucht
    // Zeilen mit Koordinate und OHNE Land.
    await phantom('a');
    expect(await db.countLocationNameBackfill(), 0);

    await db.setLocation('a', 52.37052, 9.73322);
    expect(await db.countLocationNameBackfill(), 1);
  });

  testWidgets('der Knopf dafuer ist auch erreichbar', (tester) async {
    // Ein Weg, den niemand oeffnen kann, ist kein Weg: Die Sammel-
    // bearbeitung konnte einen Ort SETZEN, aber nicht wegnehmen – und
    // einzeln 31 Aufnahmen durchzugehen ist keine Antwort.
    await phantom('a');
    await phantom('b');
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      locale: const Locale('de'),
      home: ChangeNotifierProvider<LibraryState>.value(
        value: library,
        child: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  runBatchEditMetadataDialog(context, library, ['a', 'b']),
              child: const Text('auf'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('auf'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final haken = find.byType(CheckboxListTile);
    await tester.ensureVisible(haken);
    await tester.pump();
    expect(find.text('Ort entfernen'), findsOneWidget);
    await tester.tap(haken);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect((await zeile('a')).latitude, isNull);
    expect((await zeile('a')).locationCountry, isNull);
    expect((await zeile('b')).locationCountry, isNull);
  });

  test('die Namen gehen in EINER Anweisung an alle', () async {
    // Kein Verhaltenswechsel, sondern ein Preis- und ein
    // Unteilbarkeitswechsel: Vorher lief je Aufnahme ein eigenes UPDATE.
    // Bei 500 Fotos an einer Datei gemessen 163 ms gegen 2 ms – und eine
    // Schleife, die in der Mitte scheitert, laesst die eine Haelfte am
    // neuen Ort und die andere am alten stehen.
    await phantom('a1');
    await phantom('a2');
    await phantom('fremd');
    await db.setLocationNamesBulk(['a1', 'a2'],
        country: 'Germany', state: 'Lower Saxony', city: 'Goslar');
    for (final id in ['a1', 'a2']) {
      final a = await db.assetById(id);
      expect(a!.locationCountry, 'Germany');
      expect(a.locationState, 'Lower Saxony');
      expect(a.locationCity, 'Goslar');
    }
    // Und nur die genannten: Ein `IN` ohne Bedingung traefe die ganze
    // Bibliothek.
    expect((await db.assetById('fremd'))!.locationCountry, 'Afghanistan');
  });
}
