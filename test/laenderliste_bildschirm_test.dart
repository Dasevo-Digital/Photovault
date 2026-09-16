import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/laenderliste_screen.dart';
import 'package:photo_vault/services/reverse_geocoder.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// Die Länderliste: Zeigt sie jedes Land des Datensatzes, filtert sie
/// richtig, und kommt eine von Hand gesetzte Marke wirklich an?
Future<ReverseGeocoder> _geokodierer(Directory wurzel) async {
  final staedte = File(p.join(wurzel.path, 'cities1000.txt'));
  await staedte.writeAsString(
    '2950159\tBerlin\tBerlin\t\t52.52437\t13.41053\tP\tPPLC\tDE\t\t16\t\t\t\t3426354\t\t74\tEurope/Berlin\t2023\n',
  );
  final regionen = File(p.join(wurzel.path, 'admin1CodesASCII.txt'));
  await regionen.writeAsString('DE.16\tBerlin\tBerlin\t2950157\n'
      'DE.02\tBayern\tBayern\t2951839\n'
      'IT.07\tLazio\tLazio\t3174976\n');
  final laender = File(p.join(wurzel.path, 'countryInfo.txt'));
  await laender.writeAsString(
    '# Kopfzeile\n'
    'DE\tDEU\t276\tDE\tGermany\tBerlin\t357021\t82927922\tEU\t.de\tEUR\tEuro\t49\t\t\tde-DE\t2921044\t\t\n'
    'IT\tITA\t380\tIT\tItaly\tRom\t301230\t60431283\tEU\t.it\tEUR\tEuro\t39\t\t\tit-IT\t3175395\t\t\n'
    'MC\tMCO\t492\tMN\tMonaco\tMonaco\t1.95\t32965\tEU\t.mc\tEUR\tEuro\t377\t\t\tfr-MC\t2993457\t\t\n',
  );
  return ReverseGeocoder.loadFromFiles(
      citiesFile: staedte, admin1File: regionen, countryFile: laender);
}

/// **Ein Klick öffnet den Ort, ein langer Druck markiert.** Bis
/// einschliesslich 1.13.1 tat ein Klick auf ein Land das Markieren; seit
/// der Ortsansicht führt er hinein. Das Markenmenü liegt auf dem langen
/// Druck, damit man eine Liste auch weiterhin durchhaken kann, ohne
/// jedes Mal einen Bildschirm zu öffnen.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_laender_');
    db = AppDatabase(NativeDatabase.memory());
    final paths =
        await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
    library = LibraryState()
      ..db = db
      ..paths = paths
      ..geocoder = await _geokodierer(tempRoot);
  });

  tearDown(() async {
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
            latitude: const Value(52.5),
            longitude: const Value(13.4),
            locationCountry: Value(land),
            locationState: Value(region),
            locationCity: Value(ort),
          ));

  Future<void> zeige(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: LaenderlisteScreen(library: library),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('jedes Land des Datensatzes steht da, nicht nur die besuchten',
      (tester) async {
    await aufnahme('a1',
        land: 'Germany', region: 'Berlin', ort: 'Berlin');
    await zeige(tester);

    expect(find.text('Deutschland'), findsOneWidget);
    expect(find.text('Italien'), findsOneWidget);
    expect(find.text('Monaco'), findsOneWidget);
    // Eine von zwei Regionen belegt.
    expect(find.text('1/2'), findsOneWidget);
    // Und Monaco hat gar keine – das steht da, statt dass die Spalte
    // leer bleibt und wie ein Fehler aussieht.
    expect(find.textContaining('Keine Regionen verzeichnet'), findsOneWidget);
  });

  testWidgets('die Filter sieben nach dem Grad', (tester) async {
    await aufnahme('a1',
        land: 'Germany', region: 'Berlin', ort: 'Berlin');
    await zeige(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Teilweise'));
    await tester.pumpAndSettle();
    expect(find.text('Deutschland'), findsOneWidget);
    expect(find.text('Italien'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Nicht besucht'));
    await tester.pumpAndSettle();
    expect(find.text('Deutschland'), findsNothing);
    expect(find.text('Italien'), findsOneWidget);
    expect(find.text('Monaco'), findsOneWidget);
  });

  testWidgets('die Suche findet auch ueber die Hauptstadt', (tester) async {
    await zeige(tester);
    await tester.enterText(find.byType(TextField), 'Rom');
    await tester.pumpAndSettle();
    expect(find.text('Italien'), findsOneWidget);
    expect(find.text('Deutschland'), findsNothing);
  });

  testWidgets('eine von Hand gesetzte Marke landet in der Datenbank',
      (tester) async {
    await zeige(tester);
    await tester.longPress(find.text('Italien'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Als besucht markieren'));
    await tester.pumpAndSettle();

    final marke = (await db.alleOrtsmarken()).single;
    expect(marke.art, 'land');
    expect(marke.schluessel, 'IT');
    expect(marke.status, 'besucht');
    // Und sie wirkt sofort, ohne dass jemand neu laedt.
    expect(find.textContaining('von Hand'), findsOneWidget);
  });

  testWidgets('„geplant" faerbt die Zeile, zaehlt aber nicht als besucht',
      (tester) async {
    await zeige(tester);
    await tester.longPress(find.text('Italien'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Als geplant markieren'));
    await tester.pumpAndSettle();

    // Kopfzeile: drei Laender, null besucht.
    expect(find.text('3 Länder · 0 besucht · 0 teilweise'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Nicht besucht'));
    await tester.pumpAndSettle();
    expect(find.text('Italien'), findsOneWidget);
  });

  testWidgets('eine Marke laesst sich wieder zuruecknehmen', (tester) async {
    await zeige(tester);
    await tester.longPress(find.text('Monaco'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Als besucht markieren'));
    await tester.pumpAndSettle();
    expect(await db.alleOrtsmarken(), hasLength(1));

    await tester.longPress(find.text('Monaco'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marke entfernen'));
    await tester.pumpAndSettle();
    expect(await db.alleOrtsmarken(), isEmpty);
  });

  testWidgets('ohne Datensatz sagt der Bildschirm, was fehlt', (tester) async {
    library.geocoder = null;
    await zeige(tester);
    expect(find.textContaining('GeoNames'), findsOneWidget);
  });

  /// **Der Datensatz ist englisch, die Oberfläche nicht.**
  ///
  /// Die Zeilen oben tragen aus historischen Gründen schon deutsche
  /// Namen; `countryInfo.txt` von GeoNames tut das nicht. Hier steht der
  /// echte Datensatz – und damit der Fund: In der Länderliste stand
  /// „Germany", „Poland", „Switzerland".
  group('Der englische Datensatz in der deutschen Oberflaeche', () {
    setUp(() async {
      final laender = File(p.join(tempRoot.path, 'countryInfo.txt'));
      await laender.writeAsString(
        '# Kopfzeile\n'
        'DE\tDEU\t276\tDE\tGermany\tBerlin\t357021\t82927922\tEU\t.de\tEUR\tEuro\t49\t\t\tde-DE\t2921044\t\t\n'
        'CH\tCHE\t756\tSZ\tSwitzerland\tBern\t41290\t8516543\tEU\t.ch\tCHF\tFranc\t41\t\t\tde-CH\t2658434\t\t\n'
        'PL\tPOL\t616\tPL\tPoland\tWarsaw\t312685\t37978548\tEU\t.pl\tPLN\tZloty\t48\t\t\tpl\t798544\t\t\n',
      );
      final staedte = File(p.join(tempRoot.path, 'cities1000.txt'));
      final regionen = File(p.join(tempRoot.path, 'admin1CodesASCII.txt'));
      library.geocoder = await ReverseGeocoder.loadFromFiles(
          citiesFile: staedte, admin1File: regionen, countryFile: laender);
    });

    testWidgets('die Namen stehen auf Deutsch da', (tester) async {
      await aufnahme('a1', land: 'Germany', region: 'Berlin', ort: 'Berlin');
      await zeige(tester);

      expect(find.text('Deutschland'), findsOneWidget);
      expect(find.text('Polen'), findsOneWidget);
      expect(find.text('Schweiz'), findsOneWidget);
      expect(find.text('Germany'), findsNothing);
    });

    testWidgets('sortiert wird nach dem deutschen Namen', (tester) async {
      // Englisch käme Germany, Poland, Switzerland – auf Deutsch
      // Deutschland, Polen, Schweiz. Nur bei zwei der drei fällt das
      // zusammen, und genau deshalb ist die Reihenfolge zu prüfen.
      await zeige(tester);
      final zeilen = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((k) => (k.title as Text?)?.data)
          .whereType<String>()
          .toList();
      expect(zeilen, ['Deutschland', 'Polen', 'Schweiz']);
    });

    testWidgets('gesucht wird in beiden Namen', (tester) async {
      // Wer „Germany" eintippt, weil er den Namen aus seinen Aufnahmen
      // kennt, soll Deutschland finden.
      await zeige(tester);
      await tester.enterText(find.byType(TextField), 'Deutsch');
      await tester.pumpAndSettle();
      expect(find.text('Deutschland'), findsOneWidget);
      expect(find.text('Polen'), findsNothing);

      await tester.enterText(find.byType(TextField), 'Germany');
      await tester.pumpAndSettle();
      expect(find.text('Deutschland'), findsOneWidget);
    });

    testWidgets('in der Datenbank steht der englische Name', (tester) async {
      // Die Marke soll nicht davon abhängen, in welcher Sprache sie
      // gesetzt wurde.
      await zeige(tester);
      await tester.longPress(find.text('Deutschland'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Als besucht markieren'));
      await tester.pumpAndSettle();

      final marke = (await db.alleOrtsmarken()).single;
      expect(marke.schluessel, 'DE');
      expect(marke.name, 'Germany');
    });
  });
  group('Die Legende sagt, worauf ein Haken beruht', () {
    /// **Die eigentliche Frage einer Laenderliste** – zaehlt dieses Land,
    /// weil ich dort fotografiert habe, oder weil ich es abgehakt habe –
    /// stand nirgends. Vier Zustaende als Kringel, Halbkreis, Haken und
    /// Faehnchen hatten je einen Kurzhinweis, den nur sieht, wer mit dem
    /// Zeiger daraufbleibt.
    testWidgets('sie steht ueber der Liste', (tester) async {
      await zeige(tester);
      expect(find.text('Legende'), findsOneWidget);
      expect(find.text('Durch Fotos belegt'), findsOneWidget);
      expect(find.text('Von Hand ausgewählt'), findsOneWidget);
    });

    testWidgets('ein Land mit Aufnahmen traegt die Kamera', (tester) async {
      await aufnahme('a1',
          land: 'Germany', region: 'Berlin', ort: 'Berlin');
      await zeige(tester);
      final zeile = find.ancestor(
          of: find.text('Deutschland'), matching: find.byType(ListTile));
      expect(
          find.descendant(
              of: zeile, matching: find.byIcon(Icons.photo_camera_outlined)),
          findsOneWidget);
      expect(
          find.descendant(
              of: zeile, matching: find.byIcon(Icons.back_hand_outlined)),
          findsNothing);
    });

    testWidgets('ein von Hand abgehaktes Land traegt die Hand',
        (tester) async {
      await db.setzeOrtsmarke(OrtsmarkenCompanion.insert(
        art: 'land',
        schluessel: 'IT',
        name: 'Italy',
        status: 'besucht',
        angelegtAm: DateTime(2026),
      ));
      await zeige(tester);
      final zeile = find.ancestor(
          of: find.text('Italien'), matching: find.byType(ListTile));
      expect(
          find.descendant(
              of: zeile, matching: find.byIcon(Icons.back_hand_outlined)),
          findsOneWidget);
      expect(find.descendant(of: zeile, matching: find.textContaining('von Hand')),
          findsOneWidget);
    });

    testWidgets('ein Land ohne alles traegt keines von beiden',
        (tester) async {
      await zeige(tester);
      final zeile = find.ancestor(
          of: find.text('Italien'), matching: find.byType(ListTile));
      expect(
          find.descendant(
              of: zeile, matching: find.byIcon(Icons.back_hand_outlined)),
          findsNothing);
      expect(
          find.descendant(
              of: zeile, matching: find.byIcon(Icons.photo_camera_outlined)),
          findsNothing);
    });

    testWidgets('eine Marke an einem belegten Land sagt nicht mehr von Hand',
        (tester) async {
      // Vorher stand „von Hand" an jedem Land mit einer Marke – auch an
      // denen, die laengst durch Aufnahmen belegt waren.
      await aufnahme('a1',
          land: 'Germany', region: 'Berlin', ort: 'Berlin');
      await db.setzeOrtsmarke(OrtsmarkenCompanion.insert(
        art: 'land',
        schluessel: 'DE',
        name: 'Germany',
        status: 'besucht',
        angelegtAm: DateTime(2026),
      ));
      await zeige(tester);
      final zeile = find.ancestor(
          of: find.text('Deutschland'), matching: find.byType(ListTile));
      expect(find.descendant(of: zeile, matching: find.textContaining('von Hand')),
          findsNothing);
    });
  });

}
