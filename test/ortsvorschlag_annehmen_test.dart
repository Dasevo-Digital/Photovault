import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/beschriftungsvorschlaege.dart';
import 'package:kern/services/reverse_geocoder.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/l10n/app_localizations_de.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/asset_info_sheet.dart';
import 'package:provider/provider.dart';

/// Einen vorgeschlagenen Ort annehmen (#484): Bisher kam nur der Name als
/// Stadt zu den alten Koordinaten. Ohne GPS zeigten die Angaben danach
/// keinen Ort und die Karte auch nicht; mit GPS widersprachen Name und
/// Koordinaten, und Land und Region waren still gelöscht.
void main() {
  late Directory temp;
  late AppDatabase db;
  late ReverseGeocoder geo;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pv_ortsvorschlag_');
    db = AppDatabase(NativeDatabase.memory());
    final orte = File(p.join(temp.path, 'cities1000.txt'));
    await orte.writeAsString(
      '1\tGoslar\tGoslar\t\t51.90425\t10.42766\tP\tPPLA3\tDE\t\t06\t\t\t\t50753\t\t255\tEurope/Berlin\t2023\n'
      '2\tSpringfield\tSpringfield\t\t39.79172\t-89.64371\tP\tPPLA\tUS\t\tIL\t167\t\t\t114230\t\t180\tAmerica/Chicago\t2023\n'
      '3\tSpringfield\tSpringfield\t\t37.21533\t-93.29824\tP\tPPLA2\tUS\t\tMO\t077\t\t\t169176\t\t395\tAmerica/Chicago\t2023\n',
    );
    final admin1 = File(p.join(temp.path, 'admin1.txt'));
    await admin1.writeAsString(
      'DE.06\tNiedersachsen\tNiedersachsen\t1\nUS.IL\tIllinois\tIllinois\t2\nUS.MO\tMissouri\tMissouri\t3\n',
    );
    final laender = File(p.join(temp.path, 'countryInfo.txt'));
    await laender.writeAsString(
      'DE\tDEU\t276\tDE\tDeutschland\tBerlin\t357021\t82927922\tEU\t.de\tEUR\tEuro\t49\t\t\tde-DE\t2921044\t\t\n'
      'US\tUSA\t840\tUS\tVereinigte Staaten\tWashington\t9629091\t327167434\tNA\t.us\tUSD\tDollar\t1\t\t\ten-US\t6252001\t\t\n',
    );
    geo = await ReverseGeocoder.loadFromFiles(
      citiesFile: orte,
      admin1File: admin1,
      countryFile: laender,
    );
    await db.fuehreAus(AlbumAnlegen('familie', 'Familie', DateTime(2026)));
  });

  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  Future<void> foto(
    String id, {
    double? breite,
    double? laenge,
    String? land,
    String? region,
    String? stadt,
  }) async {
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: '$id.jpg',
            checksum: id,
            type: 'IMAGE',
            fileCreatedAt: DateTime(1985, 6, 1),
            importedAt: DateTime(2026),
            latitude: Value(breite),
            longitude: Value(laenge),
            locationCountry: Value(land),
            locationState: Value(region),
            locationCity: Value(stadt),
          ),
        );
    await db.fuehreAus(AlbumFuellen('familie', [id]));
  }

  Future<AssetData> annehmen(
    Beschriftungsdienst dienst,
    String id,
    String ort,
  ) async {
    final vorschlag = await dienst.vorschlagen(
      id: id,
      album: 'familie',
      von: 'gast',
      name: 'Gast',
      art: 'ort',
      wert: ort,
    );
    await dienst.entscheiden(
      vorschlag,
      annehmen: true,
      erwartet: await dienst.stand(id),
    );
    return (await db.assetById(id))!;
  }

  test('ohne GPS: Koordinaten, Land und Region aus dem Verzeichnis', () async {
    await foto('alt');
    final a = await annehmen(
      Beschriftungsdienst(db, ortsverzeichnis: geo),
      'alt',
      'Goslar',
    );
    expect(a.latitude, closeTo(51.904, 0.001));
    expect(a.longitude, closeTo(10.428, 0.001));
    expect(a.locationCity, 'Goslar');
    expect(a.locationState, 'Niedersachsen');
    expect(a.locationCountry, geo.lookup(51.90425, 10.42766)!.country);
    expect(a.locationCountry, isNotNull);
  });

  test('gleichnamige Orte: der nächste zum bisherigen', () async {
    await foto(
      'mo',
      breite: 37.0,
      laenge: -93.0,
      land: 'United States',
      region: 'Missouri',
      stadt: 'Nixa',
    );
    final a = await annehmen(
      Beschriftungsdienst(db, ortsverzeichnis: geo),
      'mo',
      'Springfield',
    );
    expect(a.latitude, closeTo(37.215, 0.001));
    expect(a.locationCity, 'Springfield');
    expect(a.locationState, 'Missouri');
  });

  test('unbekannter Name: Koordinaten, Land und Region bleiben', () async {
    await foto(
      'gps',
      breite: 51.9,
      laenge: 10.4,
      land: 'Germany',
      region: 'Niedersachsen',
      stadt: 'Goslar',
    );
    final a = await annehmen(
      Beschriftungsdienst(db, ortsverzeichnis: geo),
      'gps',
      'Gartenhaus am Teich',
    );
    expect((a.latitude, a.longitude), (51.9, 10.4));
    expect(a.locationCountry, 'Germany');
    expect(a.locationState, 'Niedersachsen');
    expect(a.locationCity, 'Gartenhaus am Teich');

    // Ohne Verzeichnis ebenso.
    final b = await annehmen(Beschriftungsdienst(db), 'gps', 'Goslar');
    expect((b.latitude, b.longitude), (51.9, 10.4));
    expect(b.locationCountry, 'Germany');
    expect(b.locationCity, 'Goslar');
  });

  testWidgets('das Infoblatt zeigt einen Ort ohne Koordinaten', (tester) async {
    final paths = (await tester.runAsync(
      () => StoragePaths.forTesting(Directory(p.join(temp.path, 'l'))),
    ))!;
    final library = LibraryState()
      ..db = db
      ..paths = paths;
    final de = AppTexteDe();
    await tester.runAsync(() => foto('name', stadt: 'Musterstadt'));
    final asset = (await tester.runAsync(() => db.assetById('name')))!;
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryState>.value(
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
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Musterstadt'), findsOneWidget);
    expect(find.text(de.infoOrtOhneKoordinaten), findsOneWidget);
    expect(find.byTooltip(de.infoOrtEntfernen), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
