// **Bündige Reihen in der Zeitleiste.**
//
// Die Quadrate zeigen von jedem Foto denselben quadratischen Ausschnitt.
// Die zweite Form zeigt jedes Foto so, wie es aufgenommen wurde - und ein
// Hochformat sieht dann auch aus wie eines.
//
// Geprüft werden drei Dinge, die am Bildschirm auffielen: dass der
// Zeitstrahl auf die Stelle zeigt, an der der Monat wirklich steht; dass
// die Pfeiltasten nach unten in die Reihe darunter gehen und nicht
// irgendwohin; und dass der Schalter die Form wechselt und sie sich merkt.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/db/rasterzeile.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/timeline_screen.dart';
import 'package:photo_vault/services/rasterauswahl.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';
import 'package:photo_vault/widgets/month_grouped_asset_grid.dart';
import 'package:photo_vault/widgets/timeline_grid_layout.dart';

/// Eine Aufnahme mit Massen - mehr sieht die Anordnung nicht an.
Rasterzeile _foto(String id, DateTime wann, {int? breite, int? hoehe}) =>
    Rasterzeile.aus(AssetData(
      id: id,
      relativePath: 'originals/$id.jpg',
      originalFileName: '$id.jpg',
      type: 'IMAGE',
      fileSizeBytes: 1000,
      checksum: id,
      fileCreatedAt: wann,
      importedAt: wann,
      widthPx: breite,
      heightPx: hoehe,
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
    ));

void main() {
  group('Das Seitenverhältnis kommt aus der Datenbank', () {
    test('aus Breite und Höhe', () {
      expect(
          seitenverhaeltnisVon(
              _foto('a', DateTime(2026), breite: 3000, hoehe: 2000)),
          closeTo(1.5, 0.0001));
      expect(
          seitenverhaeltnisVon(
              _foto('b', DateTime(2026), breite: 2000, hoehe: 3000)),
          closeTo(2 / 3, 0.0001));
    });

    test('fehlen sie, gilt das Kleinbildformat', () {
      // 2 von 8098 Aufnahmen der echten Bibliothek haben keine Masse.
      expect(seitenverhaeltnisVon(_foto('c', DateTime(2026))),
          seitenverhaeltnisVorgabe);
      expect(
          seitenverhaeltnisVon(
              _foto('d', DateTime(2026), breite: 0, hoehe: 100)),
          seitenverhaeltnisVorgabe);
    });
  });

  group('Der Zeitstrahl rechnet, statt zu schätzen', () {
    final gruppe = [
      for (var i = 0; i < 25; i++)
        _foto('f$i', DateTime(2026, 3, 1),
            breite: i.isEven ? 3000 : 2000, hoehe: i.isEven ? 2000 : 3000)
    ];
    final gruppen = {202603: gruppe};
    const keys = [202603];

    test('die Gruppenhöhe ist die Summe der Reihen', () {
      final reihen = zeitleisteReihen(gruppe, 1200);
      expect(
        timelineMonthGroupHeight(gruppe, 1200, form: Zeitleistenform.reihen),
        closeTo(timelineHeaderHeight +
            reihenGesamthoehe(reihen, timelineGridSpacing), 0.0001),
      );
    });

    test('der Sprung landet genau am Anfang der richtigen Reihe', () {
      // Der eigentliche Gewinn: Beim Quadratraster ist das eine Schätzung,
      // hier dieselbe Rechnung, die auch zeichnet.
      final reihen = zeitleisteReihen(gruppe, 1200);
      var oben = 0.0;
      for (final r in reihen) {
        for (final platz in r.plaetze) {
          final erwartet = timelineHeaderHeight + oben;
          expect(
            timelineOffsetForAsset(keys, gruppen, 1200, 'f${platz.index}',
                form: Zeitleistenform.reihen),
            closeTo(erwartet, 0.0001),
            reason: 'f${platz.index} steht in der Reihe ab ${r.ersterIndex}',
          );
        }
        oben += r.hoehe + timelineGridSpacing;
      }
    });

    test('ein unbekanntes Foto ergibt null statt einer geratenen Stelle', () {
      expect(
          timelineOffsetForAsset(keys, gruppen, 1200, 'gibtsnicht',
              form: Zeitleistenform.reihen),
          isNull);
    });

    test('die Quadrate rechnen unverändert weiter', () {
      // Zwei Formen sind zwei Pflegefaelle; das ist der Test, der die
      // vergessene faengt.
      final spalten = timelineColumnsForWidth(1200);
      final zeilen = (gruppe.length / spalten).ceil();
      expect(
        timelineMonthGroupHeight(gruppe, 1200),
        // Die Zeilenhöhe trägt den Abstand unter sich; hinter der letzten
        // Zeile gibt es keinen. Vorher stand hier die Summe ohne diesen
        // Abzug – vier Punkte je Monatsgruppe, die sich über die
        // Bibliothek auf 164 summierten.
        closeTo(
            timelineHeaderHeight +
                zeilen * timelineRowHeightForWidth(1200) -
                timelineGridSpacing,
            0.0001),
      );
    });
  });

  group('Pfeiltasten ohne feste Spaltenzahl', () {
    // Zwei Gruppen: die erste in Reihen von 3, 2 und 4 Fotos, die zweite
    // in einer Reihe von 3.
    final gruppen = [
      ['a1', 'a2', 'a3', 'a4', 'a5', 'a6', 'a7', 'a8', 'a9'],
      ['b1', 'b2', 'b3'],
    ];
    final laengen = [
      [3, 2, 4],
      [3],
    ];

    String? geh(String von, Rasterrichtung richtung) => nachbarkachel(
          gruppen: gruppen,
          von: von,
          richtung: richtung,
          spalten: 3,
          reihenlaengen: laengen,
        );

    test('runter geht in die Reihe darunter, an dieselbe Stelle', () {
      // a1 ist Stelle 0 der ersten Reihe; darunter beginnt die zweite mit a4.
      expect(geh('a1', Rasterrichtung.runter), 'a4');
      expect(geh('a2', Rasterrichtung.runter), 'a5');
    });

    test('ist die Stelle in der Reihe darunter nicht besetzt, rueckt es auf', () {
      // a3 ist Stelle 2; die zweite Reihe hat nur zwei Fotos.
      expect(geh('a3', Rasterrichtung.runter), 'a5');
    });

    test('hoch geht zurueck, ebenfalls stellengetreu', () {
      expect(geh('a6', Rasterrichtung.hoch), 'a4');
      expect(geh('a4', Rasterrichtung.hoch), 'a1');
    });

    test('aus der letzten Reihe geht es in die naechste Gruppe', () {
      // Die dritte Reihe ist a6..a9; a8 steht dort an Stelle 2, und unter
      // ihr endet die Gruppe.
      expect(geh('a8', Rasterrichtung.runter), 'b3');
      expect(geh('a6', Rasterrichtung.runter), 'b1');
    });

    test('links und rechts laufen wie immer ueber Gruppengrenzen', () {
      expect(geh('a9', Rasterrichtung.rechts), 'b1');
      expect(geh('b1', Rasterrichtung.links), 'a9');
    });
  });

  group('Der Schalter', () {
    late Directory wurzel;
    late AppDatabase db;
    late LibraryState library;

    setUp(() async {
      wurzel = Directory.systemTemp.createTempSync('pv_reihen_');
      db = AppDatabase(NativeDatabase.memory());
      library = LibraryState()
        ..db = db
        ..paths = await StoragePaths.forTesting(
            Directory(p.join(wurzel.path, 'l')));
      for (var monat = 1; monat <= 3; monat++) {
        for (var k = 0; k < 6; k++) {
          final id = 'm${monat}_$k';
          await db.into(db.assets).insert(AssetsCompanion.insert(
                id: id,
                originalFileName: '$id.jpg',
                relativePath: 'o/$id.jpg',
                checksum: 'c$id',
                type: 'IMAGE',
                fileCreatedAt: DateTime(2026, monat, 5 + k),
                importedAt: DateTime(2026),
                thumbnailRelativePath: Value('t/$id.jpg'),
                widthPx: Value(k.isEven ? 3000 : 2000),
                heightPx: Value(k.isEven ? 2000 : 3000),
              ));
        }
      }
    });

    tearDown(() async {
      await db.close();
      wurzel.deleteSync(recursive: true);
    });

    Future<void> zeige(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: Scaffold(body: TimelineScreen(library: library)),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    Future<void> abbauen(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    Zeitleistenform form(WidgetTester tester) => tester
        .widget<MonthGroupedAssetGrid>(find.byType(MonthGroupedAssetGrid))
        .form;

    testWidgets('die Vorgabe ist das bisherige Quadratraster', (tester) async {
      // Wer nichts umstellt, sieht genau das Bisherige.
      await zeige(tester);
      expect(form(tester), Zeitleistenform.quadrate);
      // Die Kacheln stehen quadratisch und in Spalten - geprüft an dem,
      // was zu sehen ist, und nicht mehr am Namen des Slivers. Beide
      // Formen sind heute eine `SliverList`, weil ein `SliverGrid` die
      // Monatsüberschrift nicht als erstes Kind aufnehmen kann (siehe
      // MonthGroupedAssetGrid).
      final kacheln = tester
          .widgetList<AssetThumbnailTile>(find.byType(AssetThumbnailTile))
          .toList();
      expect(kacheln, isNotEmpty);
      final erste = tester.getRect(find.byType(AssetThumbnailTile).first);
      expect(erste.width, closeTo(erste.height, 0.01),
          reason: 'im Quadratraster ist jede Kachel quadratisch');
      await abbauen(tester);
    });

    testWidgets('der Knopf wechselt auf Reihen und zurueck', (tester) async {
      await zeige(tester);
      await tester.tap(find.byIcon(Icons.view_stream_outlined));
      await tester.pump(const Duration(milliseconds: 100));
      expect(form(tester), Zeitleistenform.reihen);
      // In den Reihen trägt jedes Foto sein eigenes Verhältnis; wären
      // hier wieder Quadrate, stimmte die Form nur dem Namen nach.
      final masse = [
        for (final r in tester
            .widgetList<AssetThumbnailTile>(find.byType(AssetThumbnailTile)))
          tester.getRect(find.byWidget(r))
      ];
      expect(masse.any((r) => (r.width - r.height).abs() > 1), isTrue);

      await tester.tap(find.byIcon(Icons.grid_view_outlined));
      await tester.pump(const Duration(milliseconds: 100));
      expect(form(tester), Zeitleistenform.quadrate);
      await abbauen(tester);
    });

    testWidgets('die Form ueberdauert den Bildschirm', (tester) async {
      await zeige(tester);
      await tester.tap(find.byIcon(Icons.view_stream_outlined));
      await tester.pump(const Duration(milliseconds: 100));
      await abbauen(tester);

      expect(await db.zeitleisteFormWert(), Zeitleistenform.reihen);
      await zeige(tester);
      expect(form(tester), Zeitleistenform.reihen);
      await abbauen(tester);
    });

    testWidgets('im Listenmodus steht der Knopf nicht', (tester) async {
      // Ein Knopf, der nichts bewirkt, waere irrefuehrend - dieselbe Regel
      // wie bei den Zoomknoepfen daneben.
      await zeige(tester);
      await tester.tap(find.byIcon(Icons.view_list_outlined));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.view_stream_outlined), findsNothing);
      await abbauen(tester);
    });
  });
}
