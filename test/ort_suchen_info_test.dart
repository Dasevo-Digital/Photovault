import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/services/reverse_geocoder.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/asset_info_sheet.dart';
import 'package:provider/provider.dart';

/// Einen Ort über seinen **Namen** eintragen.
///
/// Die Karte konnte das vorher schon – aber nur, wenn man weiss, wo der
/// Ort liegt. „Goslar" weiss man, 51,9° N / 10,4° O nicht. Betroffen ist
/// alles, was ohne GPS ankommt: eingescannte Bilder, Kameras ohne
/// Empfänger, Fotos von anderen Leuten.
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths paths;
  late LibraryState library;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pv_ortsuche_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory(p.join(temp.path, 'l')));
    library = LibraryState()
      ..db = db
      ..paths = paths;
    melde.alleSchliessen();
    melde.verlaufLeeren();
  });

  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  Future<ReverseGeocoder> verzeichnis() async {
    final orte = File(p.join(temp.path, 'cities1000.txt'));
    await orte.writeAsString(
      '1\tGoslar\tGoslar\t\t51.90425\t10.42766\tP\tPPLA3\tDE\t\t06\t\t\t\t50753\t\t255\tEurope/Berlin\t2023\n'
      '2\tSpringfield\tSpringfield\t\t39.79172\t-89.64371\tP\tPPLA\tUS\t\tIL\t167\t\t\t114230\t\t180\tAmerica/Chicago\t2023\n'
      '3\tSpringfield\tSpringfield\t\t37.21533\t-93.29824\tP\tPPLA2\tUS\t\tMO\t077\t\t\t169176\t\t395\tAmerica/Chicago\t2023\n',
    );
    final admin1 = File(p.join(temp.path, 'admin1.txt'));
    await admin1.writeAsString(
        'DE.06\tNiedersachsen\tNiedersachsen\t1\nUS.IL\tIllinois\tIllinois\t2\nUS.MO\tMissouri\tMissouri\t3\n');
    final laender = File(p.join(temp.path, 'countryInfo.txt'));
    await laender.writeAsString(
      'DE\tDEU\t276\tDE\tDeutschland\tBerlin\t357021\t82927922\tEU\t.de\tEUR\tEuro\t49\t\t\tde-DE\t2921044\t\t\n'
      'US\tUSA\t840\tUS\tVereinigte Staaten\tWashington\t9629091\t327167434\tNA\t.us\tUSD\tDollar\t1\t\t\ten-US\t6252001\t\t\n',
    );
    return ReverseGeocoder.loadFromFiles(
        citiesFile: orte, admin1File: admin1, countryFile: laender);
  }

  Future<AssetData> foto({double? breite, double? laenge}) async {
    await db.insertAsset(AssetsCompanion.insert(
      id: 'a',
      relativePath: 'originals/a.jpg',
      originalFileName: 'a.jpg',
      type: 'IMAGE',
      checksum: 'a',
      fileCreatedAt: DateTime(2026, 5, 1),
      importedAt: DateTime(2026, 5, 1),
      latitude: Value(breite),
      longitude: Value(laenge),
    ));
    return (await db.assetById('a'))!;
  }

  /// **Echtes Datei-Lesen gehoert in `runAsync`.** Ein `await` auf die
  /// Platte im Koerper von `testWidgets` laeuft in der gestellten Zeit und
  /// kehrt nie zurueck – der Test haengt wortlos bis zum Zeitlimit.
  Future<void> ladeVerzeichnis(WidgetTester tester) =>
      tester.runAsync(() async => library.geocoder = await verzeichnis());

  Future<void> zeige(WidgetTester tester, AssetData asset) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<LibraryState>.value(
      value: library,
      child: MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: AssetInfoSheet(
            asset: asset,
            db: db,
            paths: paths,
            onUpdated: (_) {},
            onClose: () {},
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> tippeOrt(WidgetTester tester, String name) async {
    final feld = find.widgetWithText(TextField, 'Ort suchen');
    expect(feld, findsOneWidget, reason: 'das Suchfeld muss dastehen');
    await tester.enterText(feld, name);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('ein Name wird zu einer Koordinate', (tester) async {
    await ladeVerzeichnis(tester);
    await zeige(tester, await foto());
    await tippeOrt(tester, 'Goslar');

    final nachher = (await db.assetById('a'))!;
    expect(nachher.latitude, closeTo(51.904, 0.001));
    expect(nachher.longitude, closeTo(10.428, 0.001));
    expect(melde.verlauf.last.text, contains('Goslar'));
    expect(melde.verlauf.last.text, contains('Deutschland'));
  });

  testWidgets('bei mehreren gleichen Namen sagt die Meldung es',
      (tester) async {
    // **Der Kern der Ehrlichkeit hier.** „Springfield" gibt es in den USA
    // über zwanzig Mal; eine Koordinate ohne diesen Hinweis sähe aus wie
    // eine Tatsache.
    await ladeVerzeichnis(tester);
    await zeige(tester, await foto());
    await tippeOrt(tester, 'Springfield');

    expect((await db.assetById('a'))!.latitude, isNotNull);
    expect(melde.verlauf.last.text, contains('1'),
        reason: 'die Zahl der uebrigen gleichen Namens gehoert in die Meldung');
  });

  testWidgets('der bisherige Ort entscheidet bei Mehrdeutigkeit',
      (tester) async {
    // Springfield/Illinois ist das KLEINERE der beiden. Es gewinnt nur,
    // weil das Foto schon in der Naehe lag – sonst gaebe die
    // Einwohnerzahl den Ausschlag.
    await ladeVerzeichnis(tester);
    await zeige(tester, await foto(breite: 39.8, laenge: -89.6));
    await tippeOrt(tester, 'Springfield');

    expect((await db.assetById('a'))!.latitude, closeTo(39.792, 0.001));
  });

  testWidgets('ein unbekannter Name aendert nichts', (tester) async {
    await ladeVerzeichnis(tester);
    await zeige(tester, await foto());
    await tippeOrt(tester, 'Gut Hohenrode');

    expect((await db.assetById('a'))!.latitude, isNull,
        reason: 'lieber kein Ort als ein geratener');
    expect(melde.verlauf.last.art, Meldungsart.warnung);
  });

  testWidgets('ohne Ortsverzeichnis sagt die App, woran es liegt',
      (tester) async {
    // Der Datensatz ist ein freiwilliger Download – ohne ihn darf nichts
    // werfen und nichts stillschweigend geschehen.
    library.geocoder = null;
    await zeige(tester, await foto());
    await tippeOrt(tester, 'Goslar');

    expect((await db.assetById('a'))!.latitude, isNull);
    expect(melde.verlauf.last.text, contains('Standortdaten'));
  });
}
