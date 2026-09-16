import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/db/rasterzeile.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/asset_grouping.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/services/listenspalten.dart';
import 'package:photo_vault/widgets/asset_list_view.dart';
import 'package:photo_vault/widgets/month_grouped_asset_grid.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Ein Tippen auf das Zeitleisten-Symbol soll zu den neuesten Fotos
/// zurückspringen. Geprüft wird beides: das Raster UND die Listenansicht –
/// sonst hinge das Verhalten daran, welche Darstellung gerade gewählt ist.
void main() {
  late Directory temp;
  late StoragePaths paths;
  late AppDatabase db;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pv_nachoben_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory(p.join(temp.path, 'lib')));
  });
  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  List<AssetData> fotos(int n) => [
        for (var i = 0; i < n; i++)
          AssetData(
            id: 'a$i',
            originalFileName: 'a$i.jpg',
            relativePath: 'originals/a$i.jpg',
            checksum: 'c$i',
            type: 'IMAGE',
            // Absteigend, wie die Zeitleiste sie liefert.
            fileCreatedAt: DateTime(2026, 1, 1).subtract(Duration(days: i)),
            importedAt: DateTime(2026, 1, 1),
            isFavorite: false,
            isTrashed: false,
            isLocked: false,
            faceScanExcluded: false,
            gpsGeprueft: false,
            datumGeschaetzt: false,
            datumGeprueft: false,
            ortGeerbt: false,
            videobilderGeprueft: false,
            backedUp: false,
            autoBackedUp: false,
            facesScanned: false,
            ocrScanned: false,
            aiCaptionScanned: false,
            aiTagsScanned: false,
            isStackCover: false,
            aiCaptionEdited: false,
            fileSizeBytes: 1,
            rating: 0,
          ),
      ];

  Future<void> zeige(WidgetTester tester, Widget kind) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Scaffold(body: kind),
    ));
    await tester.pump();
  }

  testWidgets('Raster: das Signal springt an den Anfang zurück', (tester) async {
    final signal = ValueNotifier<int>(0);
    addTearDown(signal.dispose);
    await zeige(tester, MonthGroupedAssetGrid(
      assets: [for (final x in fotos(400)) Rasterzeile.aus(x)], paths: paths, onTap: (_) {}, nachObenSignal: signal,
    ));

    final liste = find.byType(Scrollable).first;
    await tester.drag(liste, const Offset(0, -3000));
    await tester.pump();
    final position = tester.state<ScrollableState>(liste).position;
    expect(position.pixels, greaterThan(0), reason: 'nicht gescrollt');

    signal.value++;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(position.pixels, 0);
  });

  testWidgets('Liste: dasselbe Signal wirkt auch dort', (tester) async {
    final signal = ValueNotifier<int>(0);
    addTearDown(signal.dispose);
    await zeige(tester, AssetListView(
      assets: fotos(400), paths: paths,
      gruppierung: ListenGruppierung.monat,
      selectedIds: const {},
      onTap: (_) {}, onLongPress: (_) {},
              spalten: Listenspaltenwahl.vorgabe,
              onSpalten: (_) {},
      nachObenSignal: signal,
    ));

    // Die Liste liegt seit den Spalten in einer waagerechten Rolle - die
    // senkrechte ist damit nicht mehr die erste, die der Sucher findet.
    final liste = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down);
    await tester.drag(liste, const Offset(0, -3000));
    await tester.pump();
    final position = tester.state<ScrollableState>(liste).position;
    expect(position.pixels, greaterThan(0), reason: 'nicht gescrollt');

    signal.value++;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(position.pixels, 0);
  });

  testWidgets('ohne Signal passiert nichts', (tester) async {
    await zeige(tester, MonthGroupedAssetGrid(
      assets: [for (final x in fotos(400)) Rasterzeile.aus(x)], paths: paths, onTap: (_) {},
    ));
    final liste = find.byType(Scrollable).first;
    await tester.drag(liste, const Offset(0, -3000));
    await tester.pump();
    expect(tester.state<ScrollableState>(liste).position.pixels, greaterThan(0));
  });
}
