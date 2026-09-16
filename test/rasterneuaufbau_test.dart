// Was das Raster bei einem Neuaufbau NICHT noch einmal tut.
//
// Neuaufbauten löst hier schon jeder Pfeiltastendruck aus (siehe
// Rasterbedienung) und jeder Klick in der Mehrfachauswahl. An der
// gewachsenen Bibliothek kostete das Aufteilen in Monatsgruppen 0,94 ms
// je Neuaufbau, dazu rund achtzig frische Listen – für ein Ergebnis, das
// sich nicht geändert hatte.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/db/rasterzeile.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/widgets/month_grouped_asset_grid.dart';

import 'dart:io';

Rasterzeile _asset(String id, DateTime wann) => Rasterzeile.aus(AssetData(
      id: id,
      originalFileName: '$id.jpg',
      relativePath: 'o/$id.jpg',
      checksum: 'c$id',
      type: 'IMAGE',
      fileCreatedAt: wann,
      importedAt: wann,
      isFavorite: false,
      isTrashed: false,
      isLocked: false,
      faceScanExcluded: false,
      gpsGeprueft: false,
      datumGeschaetzt: false,
      datumGeprueft: false,
      ortGeerbt: false,
      videobilderGeprueft: false,
      fileSizeBytes: 100,
      backedUp: false,
      autoBackedUp: false,
      facesScanned: false,
      rating: 0,
      ocrScanned: false,
      aiCaptionScanned: false,
      aiCaptionEdited: false,
      aiTagsScanned: false,
      isStackCover: false,
    ));

void main() {
  setUpAll(initializeDateFormatting);

  late Directory wurzel;
  late StoragePaths paths;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_raster_');
    // ignore: invalid_use_of_visible_for_testing_member
    paths = await StoragePaths.forTesting(wurzel);
  });
  tearDown(() => wurzel.deleteSync(recursive: true));

  /// Drei Monate mit je zwei Aufnahmen.
  List<Rasterzeile> daten() => [
        for (var m = 3; m >= 1; m--)
          for (var t = 2; t >= 1; t--)
            _asset('a$m$t', DateTime(2026, m, t * 10)),
      ];

  testWidgets('dieselbe Liste wird nicht zweimal gruppiert', (tester) async {
    final liste = daten();
    var aufbauten = 0;

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setzen) {
            aufbauten++;
            return Column(
              children: [
                ElevatedButton(
                    onPressed: () => setzen(() {}),
                    child: const Text('neu')),
                Expanded(
                  child: MonthGroupedAssetGrid(
                      assets: liste, paths: paths, onTap: (_) {}),
                ),
              ],
            );
          },
        ),
      ),
    ));

    final zustand = tester.state(find.byType(MonthGroupedAssetGrid));
    final ersteGruppen = (zustand as dynamic).lastGroupsFuerTest;
    expect(ersteGruppen, isNotNull);

    // Ein Neuaufbau ohne neue Liste – wie ihn ein Pfeiltastendruck auslöst.
    await tester.tap(find.text('neu'));
    await tester.pump();
    expect(aufbauten, greaterThan(1), reason: 'es wurde gar nicht neu gebaut');

    expect(identical((zustand as dynamic).lastGroupsFuerTest, ersteGruppen),
        isTrue,
        reason: 'die Gruppierung lief ein zweites Mal, obwohl sich an der '
            'Liste nichts geändert hat');
  });

  testWidgets('eine neue Liste wird sehr wohl neu gruppiert', (tester) async {
    var liste = daten();

    late StateSetter setzen;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, s) {
            setzen = s;
            return MonthGroupedAssetGrid(
                assets: liste, paths: paths, onTap: (_) {});
          },
        ),
      ),
    ));

    final zustand = tester.state(find.byType(MonthGroupedAssetGrid));
    final vorher = (zustand as dynamic).lastGroupsFuerTest;

    // Eine echte Änderung: eine Aufnahme weniger, neue Liste.
    setzen(() => liste = daten()..removeLast());
    await tester.pump();

    final nachher = (zustand as dynamic).lastGroupsFuerTest;
    expect(identical(nachher, vorher), isFalse,
        reason: 'eine geänderte Liste muss neu gruppiert werden');
    expect(nachher.length, isNot(0));
  });
}
