import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/services/listenspalten.dart';
import 'package:photo_vault/widgets/asset_list_view.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/asset_grouping.dart';

/// Die Gliederung der Listenansicht.
///
/// Die Reihenfolge der Gruppen ist die eigentliche Entscheidung – und die
/// sieht man einer Liste erst an, wenn man sie benutzt.
AssetData _foto(String id, DateTime wann, {String? marke, String? modell}) => AssetData(
      id: id,
      relativePath: 'originals/$id.jpg',
      originalFileName: '$id.jpg',
      type: 'IMAGE',
      fileSizeBytes: 100,
      checksum: id,
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
      backedUp: false,
      autoBackedUp: false,
      facesScanned: false,
      ocrScanned: false,
      aiCaptionScanned: false,
      aiCaptionEdited: false,
      aiTagsScanned: false,
      isStackCover: false,
      rating: 0,
      cameraMake: marke,
      cameraModel: modell,
    );

void main() {
  group('Kamerabezeichnung', () {
    test('Hersteller und Modell werden nicht doppelt geschrieben', () {
      // Canon steht in beiden EXIF-Feldern.
      expect(
          kamerabezeichnung(_foto('a', DateTime(2026), marke: 'Canon', modell: 'Canon EOS R10')),
          'Canon EOS R10');
    });

    test('nur eines von beiden reicht', () {
      expect(kamerabezeichnung(_foto('a', DateTime(2026), marke: 'SONY')), 'SONY');
      expect(kamerabezeichnung(_foto('a', DateTime(2026), modell: 'X100V')), 'X100V');
    });

    test('beides zusammen, wenn sie verschieden sind', () {
      expect(
          kamerabezeichnung(_foto('a', DateTime(2026), marke: 'SONY', modell: 'ILCE-6300')),
          'SONY ILCE-6300');
    });

    test('ohne Angabe kommt null', () {
      expect(kamerabezeichnung(_foto('a', DateTime(2026))), isNull);
      expect(kamerabezeichnung(_foto('a', DateTime(2026), marke: '  ')), isNull);
    });
  });

  group('Gliederung nach Monat', () {
    test('neueste Gruppe zuerst, wie im Raster', () {
      final gruppen = gruppiereAssets([
        _foto('a', DateTime(2026, 3, 5)),
        _foto('b', DateTime(2026, 1, 9)),
        _foto('c', DateTime(2026, 3, 1)),
      ], ListenGruppierung.monat);

      expect(gruppen.map((g) => g.schluessel), ['202603', '202601']);
      expect(gruppen.first.assets.map((a) => a.id), ['a', 'c']);
    });

    test('die Reihenfolge innerhalb einer Gruppe bleibt erhalten', () {
      // Die Liste kommt nach Datum sortiert an; daran wird nicht gerüttelt.
      final gruppen = gruppiereAssets([
        _foto('neu', DateTime(2026, 3, 20)),
        _foto('mittel', DateTime(2026, 3, 10)),
        _foto('alt', DateTime(2026, 3, 1)),
      ], ListenGruppierung.monat);
      expect(gruppen.single.assets.map((a) => a.id), ['neu', 'mittel', 'alt']);
    });
  });

  group('Gliederung nach Kamera', () {
    test('alphabetisch, Fotos ohne Kamera zuletzt', () {
      // Nach Häufigkeit zu sortieren wäre verlockend, ist aber unbrauchbar:
      // Die Reihenfolge änderte sich bei jedem Import.
      final gruppen = gruppiereAssets([
        _foto('a', DateTime(2026, 3, 5), modell: 'Nikon Z6'),
        _foto('b', DateTime(2026, 3, 4)),
        _foto('c', DateTime(2026, 3, 3), modell: 'Canon EOS R10'),
        _foto('d', DateTime(2026, 3, 2), modell: 'Canon EOS R10'),
        _foto('e', DateTime(2026, 3, 1)),
      ], ListenGruppierung.kamera);

      expect(gruppen.map((g) => g.schluessel), ['Canon EOS R10', 'Nikon Z6', '']);
      expect(gruppen.last.assets.map((a) => a.id), ['b', 'e'],
          reason: 'ohne Kamera, in der Reihenfolge der Liste');
    });

    test('Gross- und Kleinschreibung entscheidet die Reihenfolge nicht', () {
      final gruppen = gruppiereAssets([
        _foto('a', DateTime(2026, 3, 2), modell: 'apsC Kamera'),
        _foto('b', DateTime(2026, 3, 1), modell: 'ZEISS'),
        _foto('c', DateTime(2026, 3, 3), modell: 'Bxx'),
      ], ListenGruppierung.kamera);
      expect(gruppen.map((g) => g.schluessel), ['apsC Kamera', 'Bxx', 'ZEISS']);
    });

    test('die Datumsreihenfolge bleibt innerhalb der Kamera erhalten', () {
      final gruppen = gruppiereAssets([
        _foto('neu', DateTime(2026, 5, 1), modell: 'X'),
        _foto('alt', DateTime(2024, 1, 1), modell: 'X'),
      ], ListenGruppierung.kamera);
      expect(gruppen.single.assets.map((a) => a.id), ['neu', 'alt']);
    });
  });

  group('Ohne Gliederung', () {
    test('alles in einer Gruppe, unverändert', () {
      final assets = [
        _foto('a', DateTime(2026, 3, 5)),
        _foto('b', DateTime(2024, 1, 9)),
      ];
      final gruppen = gruppiereAssets(assets, ListenGruppierung.keine);
      expect(gruppen, hasLength(1));
      expect(gruppen.single.assets.map((a) => a.id), ['a', 'b']);
    });

    test('leer bleibt leer, statt eine leere Gruppe zu erfinden', () {
      expect(gruppiereAssets(const [], ListenGruppierung.keine), isEmpty);
      expect(gruppiereAssets(const [], ListenGruppierung.monat), isEmpty);
      expect(gruppiereAssets(const [], ListenGruppierung.kamera), isEmpty);
    });
  });

  test('kein Foto geht beim Gruppieren verloren', () {
    // Der Fehler, der am leichtesten passiert und am spätesten auffällt.
    final assets = [
      for (var i = 0; i < 40; i++)
        _foto('f$i', DateTime(2020 + i % 5, 1 + i % 12, 1 + i % 28),
            modell: i % 3 == 0 ? null : 'Kamera ${i % 4}'),
    ];
    for (final art in ListenGruppierung.values) {
      final summe =
          gruppiereAssets(assets, art).fold<int>(0, (a, g) => a + g.assets.length);
      expect(summe, assets.length, reason: '$art');
    }
  });

  group('Die Ansicht', () {
    late Directory tempRoot;
    late StoragePaths paths;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('pv_liste_');
      paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
    });
    tearDown(() => tempRoot.deleteSync(recursive: true));

    final assets = [
      _foto('urlaub', DateTime(2026, 3, 5), marke: 'SONY', modell: 'ILCE-6300'),
      _foto('winter', DateTime(2026, 1, 9), modell: 'Canon EOS R10'),
    ];

    Future<void> zeige(WidgetTester tester, double breite,
        {ListenGruppierung art = ListenGruppierung.monat}) async {
      tester.view.physicalSize = Size(breite, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: Scaffold(
          body: AssetListView(
            assets: assets,
            paths: paths,
            gruppierung: art,
            selectedIds: const {},
            onTap: (_) {},
            onLongPress: (_) {},
              spalten: Listenspaltenwahl.vorgabe,
              onSpalten: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('im breiten Fenster stehen alle Spalten da', (tester) async {
      await zeige(tester, 1200);
      expect(find.text('urlaub.jpg'), findsOneWidget);
      expect(find.text('SONY ILCE-6300'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('im schmalen Fenster verschwindet nichts, es rollt zur Seite',
        (tester) async {
      // **Die Regel hat sich geändert.** Vorher fielen Spalten still weg,
      // sobald das Fenster unter 620, 860 bzw. 1040 Punkte kam – wer die
      // Kamera brauchte, musste das Fenster breiter ziehen und wusste
      // nicht, warum. Jetzt bleiben die Spalten, die man gewählt hat, und
      // die Liste rollt waagerecht; was man nicht braucht, schaltet man
      // ab.
      await zeige(tester, 500);
      expect(find.text('urlaub.jpg'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('die Monatsüberschriften sind ausgeschrieben', (tester) async {
      await zeige(tester, 1200);
      expect(find.text('März 2026'), findsOneWidget);
      expect(find.text('Januar 2026'), findsOneWidget);
    });

    testWidgets('nach Kamera gegliedert steht die Bezeichnung als Überschrift',
        (tester) async {
      await zeige(tester, 1200, art: ListenGruppierung.kamera);
      expect(find.text('Canon EOS R10'), findsWidgets);
      expect(find.text('März 2026'), findsNothing);
    });

    testWidgets('ohne Gliederung gibt es keine Überschriften', (tester) async {
      await zeige(tester, 1200, art: ListenGruppierung.keine);
      expect(find.text('März 2026'), findsNothing);
      expect(find.text('urlaub.jpg'), findsOneWidget);
    });
  });
}
