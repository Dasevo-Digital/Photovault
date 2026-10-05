/// Die Zeitleiste nach Tagen: kleine Tage nebeneinander, grosse für sich.
///
/// Zwei Hälften. Die Rechnung ([zeitleisteTageszeilen]) wird ohne
/// Bildschirm geprüft – wer steht neben wem, wo bricht die Zeile, stimmt
/// die Reihenfolge. Das gezeichnete Raster wird an der Rechnung gemessen:
/// Ist die Tagesüberschrift so hoch wie angenommen, und trifft der
/// gerechnete Sprung das Foto? Stimmte beides nicht, landete der Zeitstrahl
/// mit jeder Tageszeile ein Stück weiter neben dem Ziel.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/db/rasterzeile.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/l10n/app_localizations_de.dart';
import 'package:photo_vault/services/asset_grouping.dart';
import 'package:photo_vault/services/rasterauswahl.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';
import 'package:photo_vault/widgets/month_grouped_asset_grid.dart';
import 'package:photo_vault/widgets/timeline_grid_layout.dart';
import 'package:photo_vault/widgets/timeline_scrubber.dart';

final _einPunktPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
  'hQGAhKmMIQAAAABJRU5ErkJggg==',
);

const double _fensterBreite = 1600;
const double _fensterHoehe = 1000;
const double _gitter = _fensterBreite - 64;

AssetData _voll(String id, DateTime wann, {int b = 3000, int h = 2000}) =>
    AssetData(
      id: id,
      relativePath: 'originals/$id.jpg',
      originalFileName: '$id.jpg',
      thumbnailRelativePath: 'thumbnails/$id.png',
      type: 'IMAGE',
      fileSizeBytes: 1000,
      checksum: id,
      fileCreatedAt: wann,
      importedAt: wann,
      widthPx: b,
      heightPx: h,
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
    );

Rasterzeile _foto(String id, DateTime wann, {int b = 3000, int h = 2000}) =>
    Rasterzeile.aus(_voll(id, wann, b: b, h: h));

/// Ein Tag mit [anzahl] Fotos, absteigend innerhalb des Tages.
List<Rasterzeile> _tag(DateTime tag, int anzahl) => [
  for (var i = 0; i < anzahl; i++)
    _foto(
      '${tag.year}${tag.month}${tag.day}_$i',
      DateTime(tag.year, tag.month, tag.day, 20 - i % 12, i % 60),
      b: i.isEven ? 3000 : 2000,
      h: i.isEven ? 2000 : 3000,
    ),
];

/// Vierzig Monate, gemischt wie die echte Bibliothek: viele Tage mit
/// einem bis drei Fotos, dazwischen ein grosser.
final _bestand = [
  for (var m = 0; m < 40; m++)
    for (final (tag, anzahl) in [(26, 1), (22, 2), (18, 3), (12, 25), (5, 1)])
      ..._tag(DateTime(2026, 1 - m, tag), anzahl),
];

void main() {
  group('Rechnung', () {
    final monat = [
      ..._tag(DateTime(2026, 9, 28), 1),
      ..._tag(DateTime(2026, 9, 27), 2),
      ..._tag(DateTime(2026, 9, 20), 3),
      ..._tag(DateTime(2026, 9, 12), 30),
      ..._tag(DateTime(2026, 9, 2), 1),
    ];

    for (final form in Zeitleistenform.values) {
      test('${form.name}: kleine Tage nebeneinander, der grosse für sich', () {
        final zeilen = zeitleisteTageszeilen(monat, _gitter, form: form);
        expect(zeilen.first, isA<TagesblockZeile>());
        final erste = zeilen.first as TagesblockZeile;
        expect(
          [for (final b in erste.bloecke) b.anzahl],
          [1, 2, 3],
          reason: 'drei kleine Tage passen in 1536 Punkte',
        );
        expect(zeilen[1], isA<TageskopfZeile>());
        expect(zeilen.whereType<TagesbildZeile>().length, greaterThan(1));
        expect(zeilen.last, isA<TagesblockZeile>());
        expect((zeilen.last as TagesblockZeile).bloecke.single.anzahl, 1);
      });

      test('${form.name}: Reihenfolge und Anzahl bleiben erhalten', () {
        final zeilen = zeitleisteTageszeilen(monat, _gitter, form: form);
        final indizes = <int>[
          for (final z in zeilen)
            ...switch (z) {
              TagesblockZeile(:final bloecke) => [
                for (final b in bloecke)
                  for (final p in b.reihe.plaetze) p.index,
              ],
              TagesbildZeile(:final reihe) => [
                for (final p in reihe.plaetze) p.index,
              ],
              TageskopfZeile() => const <int>[],
            },
        ];
        expect(indizes, [for (var i = 0; i < monat.length; i++) i]);
        expect(
          tageszeilenLaengen(zeilen).fold<int>(0, (a, b) => a + b),
          monat.length,
        );
      });

      test('${form.name}: keine Zeile ist breiter als das Raster', () {
        for (final breite in [400.0, 700.0, _gitter]) {
          for (final z in zeitleisteTageszeilen(monat, breite, form: form)) {
            if (z is! TagesblockZeile) continue;
            final belegt =
                z.bloecke.fold<double>(0, (a, b) => a + b.breite) +
                timelineTagesabstand * (z.bloecke.length - 1);
            expect(
              belegt,
              lessThanOrEqualTo(breite - timelineGridHorizontalPadding + 0.5),
            );
          }
        }
      });
    }

    test('schmal bricht die Zeile um, statt zu quetschen', () {
      final zeilen = zeitleisteTageszeilen(monat, 400);
      final kleine = zeilen.whereType<TagesblockZeile>().toList();
      expect(kleine.length, greaterThan(2));
    });

    test('Monatshöhe = Überschrift + Zeilen', () {
      final zeilen = zeitleisteTageszeilen(monat, _gitter);
      expect(
        timelineMonthGroupHeight(monat, _gitter, mitTagen: true),
        closeTo(timelineHeaderHeight + tageszeilenHoehe(zeilen), 0.001),
      );
    });

    test('Pfeil nach unten läuft über die Tagesgrenze hinweg', () {
      final zeilen = zeitleisteTageszeilen(monat, _gitter);
      final laengen = tageszeilenLaengen(zeilen);
      final ids = [for (final a in monat) a.id];
      // Vom dritten Foto der ersten Zeile (zweiter Tag) nach unten: in die
      // erste Reihe des grossen Tages, an dieselbe Stelle.
      final ziel = nachbarkachel(
        gruppen: [ids],
        von: ids[2],
        richtung: Rasterrichtung.runter,
        spalten: 1,
        reihenlaengen: [laengen],
      );
      expect(ziel, ids[laengen.first + 2]);
    });
  });

  group('Beschriftung', () {
    final t = AppTexteDe();
    setUpAll(() => initializeDateFormatting('de'));
    final heute = DateTime(2026, 3, 30, 9);

    test('heute und gestern beim Namen', () {
      expect(
        tagesbeschriftung(DateTime(2026, 3, 30, 23), t, 'de', heute: heute),
        'Heute',
      );
      // Am 29. März 2026 wird auf Sommerzeit umgestellt – der Tag hat 23
      // Stunden, „gestern" muss trotzdem stimmen.
      expect(
        tagesbeschriftung(DateTime(2026, 3, 29, 1), t, 'de', heute: heute),
        'Gestern',
      );
    });

    test('sonst Wochentag und Datum, knapp ohne Wochentag', () {
      final lang = tagesbeschriftung(
        DateTime(2026, 3, 2),
        t,
        'de',
        heute: heute,
      );
      final knapp = tagesbeschriftung(
        DateTime(2026, 3, 2),
        t,
        'de',
        heute: heute,
        knapp: true,
      );
      expect(lang, contains('Mo'));
      expect(lang, contains('2.'));
      expect(knapp, isNot(contains('Mo')));
      expect(
        lang,
        isNot(contains('2026')),
        reason: 'das Jahr steht schon in der Monatsüberschrift',
      );
    });
  });

  test('Liste nach Tagen', () {
    final a = [
      _voll('a', DateTime(2026, 9, 3, 10)),
      _voll('b', DateTime(2026, 9, 3, 8)),
      _voll('c', DateTime(2026, 9, 1, 8)),
    ];
    final g = gruppiereAssets(a, ListenGruppierung.tag);
    expect([for (final x in g) x.schluessel], ['20260903', '20260901']);
    expect(g.first.assets.length, 2);
  });

  test('die Wahl wird gemerkt', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(await db.zeitleisteMitTagenWert(), isFalse);
    await db.setzeZeitleisteMitTagen(true);
    expect(await db.zeitleisteMitTagenWert(), isTrue);
  });

  group('Raster', () {
    late Directory wurzel;
    late StoragePaths paths;

    setUpAll(() async {
      wurzel = Directory.systemTemp.createTempSync('pv_tage_');
      paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'l')),
      );
      for (final a in _bestand) {
        File(p.join(paths.root.path, a.thumbnailRelativePath!))
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(_einPunktPng);
      }
    });

    tearDownAll(() => wurzel.deleteSync(recursive: true));

    Future<void> zeige(
      WidgetTester tester,
      Zeitleistenform form, {
      List<Rasterzeile>? assets,
      bool nachTag = false,
    }) async {
      tester.view.physicalSize = const Size(_fensterBreite, _fensterHoehe);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          theme: buildDarkTheme(),
          home: Scaffold(
            body: MonthGroupedAssetGrid(
              assets: assets ?? _bestand,
              paths: paths,
              onTap: (_) {},
              onHeaderTap: (_) {},
              form: form,
              mitTagen: !nachTag,
              nachTag: nachTag,
            ),
          ),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
        await tester.pump();
      }
    }

    testWidgets('die Tagesüberschrift ist so hoch, wie die Rechnung annimmt', (
      tester,
    ) async {
      await tester.runAsync(() => zeige(tester, Zeitleistenform.quadrate));
      // Erster Tag ist klein: Monatsüberschrift, Tagesüberschrift, Foto.
      expect(
        tester.getTopLeft(find.byType(AssetThumbnailTile).first).dy,
        closeTo(timelineHeaderHeight + timelineTagesKopfHoehe, 0.01),
      );
    });

    for (final form in Zeitleistenform.values) {
      testWidgets('${form.name}: der gerechnete Sprung trifft', (tester) async {
        await tester.runAsync(() => zeige(tester, form));
        final gruppen = monatsgruppen(_bestand);
        // Mitten im grossen Tag eines späten Monats – dort summieren sich
        // Tagesüberschriften und Zeilen von zwanzig Monaten davor.
        final ziel = gruppen.gruppen[gruppen.schluessel[20]]![15];
        final gerechnet = timelineOffsetForAsset(
          gruppen.schluessel,
          gruppen.gruppen,
          _gitter,
          ziel.id,
          form: form,
          mitTagen: true,
        )!;
        final lage = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        lage.jumpTo(gerechnet - 300);
        await tester.pump();
        final treffer = find.byWidgetPredicate(
          (w) => w is AssetThumbnailTile && w.asset.id == ziel.id,
        );
        expect(treffer, findsOneWidget);
        expect(tester.getTopLeft(treffer).dy, closeTo(300, 1.0));
      });

      testWidgets('${form.name}: ein kleiner Tag springt mit Überschrift', (
        tester,
      ) async {
        await tester.runAsync(() => zeige(tester, form));
        final gruppen = monatsgruppen(_bestand);
        // Das zweite Foto des Zwei-Foto-Tages: Die Rechnung zielt auf den
        // Beginn der Zeile, also auf die Tagesüberschrift darüber.
        final ziel = gruppen.gruppen[gruppen.schluessel[10]]![2];
        final gerechnet = timelineOffsetForAsset(
          gruppen.schluessel,
          gruppen.gruppen,
          _gitter,
          ziel.id,
          form: form,
          mitTagen: true,
        )!;
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(gerechnet - 300);
        await tester.pump();
        final treffer = find.byWidgetPredicate(
          (w) => w is AssetThumbnailTile && w.asset.id == ziel.id,
        );
        expect(
          tester.getTopLeft(treffer).dy,
          closeTo(300 + timelineTagesKopfHoehe, 1.0),
        );
      });
    }

    testWidgets('Tagesüberschrift wählt den Tag', (tester) async {
      List<Rasterzeile>? gewaehlt;
      tester.view.physicalSize = const Size(_fensterBreite, _fensterHoehe);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('de'),
            localizationsDelegates: AppTexte.localizationsDelegates,
            supportedLocales: AppTexte.supportedLocales,
            home: Scaffold(
              body: MonthGroupedAssetGrid(
                assets: _bestand,
                paths: paths,
                onTap: (_) {},
                onHeaderTap: (g) => gewaehlt = g,
                mitTagen: true,
              ),
            ),
          ),
        );
        await tester.pump();
      });
      final zweiterTag = _bestand.where(
        (a) =>
            a.fileCreatedAt.year == 2026 &&
            a.fileCreatedAt.month == 1 &&
            a.fileCreatedAt.day == 22,
      );
      final label = tagesbeschriftung(
        zweiterTag.first.fileCreatedAt,
        AppTexteDe(),
        'de',
        // Zwei Kacheln sind breiter als die Grenze für die knappe Form.
        heute: DateTime.now(),
      );
      await tester.tap(find.text(label).first);
      expect(gewaehlt?.map((a) => a.id), zweiterTag.map((a) => a.id));
    });

    testWidgets('Zeitstrahl über Tage beschriftet Tage, nicht „202609"', (
      tester,
    ) async {
      final september = [
        for (final d in [28, 21, 14, 7]) ..._tag(DateTime(2026, 9, d), 30),
      ];
      await tester.runAsync(
        () => zeige(
          tester,
          Zeitleistenform.quadrate,
          assets: september,
          nachTag: true,
        ),
      );
      expect(find.byType(TimelineScrubber), findsOneWidget);
      final texte = find
          .descendant(
            of: find.byType(TimelineScrubber),
            matching: find.byType(Text),
          )
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .toList();
      expect(texte, isNot(contains('202609')));
      expect(texte, contains('7'));
    });
  });
}
