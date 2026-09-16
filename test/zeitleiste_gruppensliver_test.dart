/// **Was eine Monatsgruppe kostet, die man gar nicht sieht.**
///
/// Die Zeitleiste hat je Monat einen eigenen Sliver, und ein Sliver baut
/// immer sein erstes Kind – auch einer weit unterhalb des Fensters. Stand
/// die Überschrift daneben statt darin, war dieses erste Kind ein Foto
/// (Raster) beziehungsweise eine ganze Fotoreihe (bündige Reihen).
///
/// **Gezählt wird im Bildspeicher, nicht im Widget-Baum.** Diese Kinder
/// entstehen und vergehen während des ersten Auslegens; hinterher steht
/// im Baum nur, was zu sehen ist – deshalb sah der erste Anlauf dieses
/// Tests keinen Unterschied. Was bleibt, ist das dekodierte Bild, und
/// daran ist es ablesbar: An der echten Bibliothek lag vorher das
/// Erstfoto **aller 82 Monate** im Speicher, auch das des ältesten,
/// zehntausende Punkte unterhalb des Fensters. Danach eines.
///
/// Die zweite Zahl dieses Tests ist die Höhe der Überschrift. Sie steht
/// als [timelineHeaderHeight] in der Rechnung, mit der der Zeitstrahl
/// seine Sprungziele bestimmt; stimmt sie nicht, summiert sich der Fehler
/// über jede Monatsgruppe.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/db/rasterzeile.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/bilddekodierung.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';
import 'package:photo_vault/widgets/month_grouped_asset_grid.dart';
import 'package:photo_vault/widgets/timeline_grid_layout.dart';

/// Ein Bild von einem Bildpunkt – hier zählt, **ob** dekodiert wird,
/// nicht was dabei herauskommt.
final _einPunktPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==');

const double _fensterBreite = 1600;
const double _fensterHoehe = 1000;

Rasterzeile _foto(String id, DateTime wann, {int b = 3000, int h = 2000}) =>
    Rasterzeile.aus(AssetData(
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
    ));

/// Achtzig Monate à sechs Fotos: genug Gruppen, dass die meisten weit
/// ausserhalb des Fensters liegen, und wenige genug Dateien, dass der
/// Test in einem Wimpernschlag steht.
final _bestand = [
  for (var m = 0; m < 80; m++)
    for (var k = 0; k < 6; k++)
      _foto('m${m}_$k',
          DateTime(2026, 1, 1).subtract(Duration(days: m * 31 + k)),
          b: k.isEven ? 3000 : 2000, h: k.isEven ? 2000 : 3000),
];

late StoragePaths _paths;

/// Liegt das Vorschaubild dieser Aufnahme im Bildspeicher?
///
/// Steht die Kachel im Baum, liefert sie ihren Anbieter selbst – sicherer
/// als jede Nachrechnung. Für eine Kachel weit ausserhalb wird der
/// Schlüssel gebildet wie in der Kachel, über [deckendeDekodiermasse].
Future<bool> _imSpeicher(WidgetTester tester, Rasterzeile a) async {
  bool drin(Object schluessel) =>
      PaintingBinding.instance.imageCache.containsKey(schluessel);

  final treffer = find.byWidgetPredicate(
      (w) => w is AssetThumbnailTile && w.asset.id == a.id);
  if (treffer.evaluate().isNotEmpty) {
    final bild = tester.widget<Image>(
        find.descendant(of: treffer.first, matching: find.byType(Image)));
    return drin(await bild.image.obtainKey(ImageConfiguration.empty));
  }

  const gitter = _fensterBreite - 64;
  final quadrat = timelineRowHeightForWidth(gitter) - timelineGridSpacing;
  final reihe = zeitleisteReihen(
      _bestand.where((x) => x.fileCreatedAt.month == a.fileCreatedAt.month &&
          x.fileCreatedAt.year == a.fileCreatedAt.year).toList(),
      gitter).first;
  for (final (kb, kh) in [
    (quadrat, quadrat),
    (reihe.plaetze.first.breite, reihe.hoehe),
  ]) {
    final m = deckendeDekodiermasse(
        kachelBreite: kb,
        kachelHoehe: kh,
        bildBreite: a.widthPx,
        bildHoehe: a.heightPx,
        pixelverhaeltnis: 1);
    final prov = ResizeImage.resizeIfNeeded(m.breite, m.hoehe,
        FileImage(_paths.absolute(a.thumbnailRelativePath!)));
    if (drin(await prov.obtainKey(ImageConfiguration.empty))) return true;
  }
  return false;
}

void main() {
  late Directory wurzel;

  setUpAll(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_gruppensliver_');
    _paths = await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'l')));
    for (final a in _bestand) {
      File(p.join(_paths.root.path, a.thumbnailRelativePath!))
          .writeAsBytesSync(_einPunktPng);
    }
  });

  tearDownAll(() => wurzel.deleteSync(recursive: true));

  Future<void> zeige(WidgetTester tester, Zeitleistenform form) async {
    tester.view.physicalSize = const Size(_fensterBreite, _fensterHoehe);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: Scaffold(
        body: MonthGroupedAssetGrid(
          assets: _bestand,
          paths: _paths,
          onTap: (_) {},
          form: form,
        ),
      ),
    ));
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      await tester.pump();
    }
  }

  for (final form in Zeitleistenform.values) {
    testWidgets('${form.name}: ein Monat weit unterhalb dekodiert kein Foto',
        (tester) async {
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      await tester.runAsync(() => zeige(tester, form));

      final gruppen = monatsgruppen(_bestand);
      final nah = gruppen.gruppen[gruppen.schluessel.first]!.first;
      final fern = gruppen.gruppen[gruppen.schluessel.last]!.first;
      await tester.runAsync(() async {
        expect(await _imSpeicher(tester, nah), isTrue,
            reason: 'das erste sichtbare Foto ist nicht dekodiert - dann '
                'misst dieser Test gar nichts');
        expect(await _imSpeicher(tester, fern), isFalse,
            reason: 'ein Foto aus dem aeltesten Monat wurde dekodiert, '
                'obwohl es zehntausende Punkte unterhalb steht');
      });
    });
  }

  testWidgets('die Überschrift ist so hoch, wie die Rechnung annimmt',
      (tester) async {
    await tester.runAsync(() => zeige(tester, Zeitleistenform.quadrate));
    // Die erste Kachel beginnt unmittelbar unter der ersten Überschrift.
    expect(tester.getTopLeft(find.byType(AssetThumbnailTile).first).dy,
        closeTo(timelineHeaderHeight, 0.01));
  });

  for (final form in Zeitleistenform.values) {
    testWidgets('${form.name}: der gerechnete Sprung trifft', (tester) async {
      await tester.runAsync(() => zeige(tester, form));
      final gruppen = monatsgruppen(_bestand);
      final ziel = gruppen.gruppen[gruppen.schluessel[40]]!.first;
      final gerechnet = timelineOffsetForAsset(
          gruppen.schluessel, gruppen.gruppen, _fensterBreite - 64, ziel.id,
          form: form)!;
      final lage =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      // 300 Punkte davor anhalten: Danach muss das Foto genau 300 Punkte
      // unter dem oberen Rand stehen. Vorher waren es nach vierzig
      // Gruppen rund 480 Punkte weniger - zwölf je Überschrift.
      lage.jumpTo(gerechnet - 300);
      await tester.pump();
      final treffer = find.byWidgetPredicate(
          (w) => w is AssetThumbnailTile && w.asset.id == ziel.id);
      expect(treffer, findsOneWidget,
          reason: 'die Rechnung liegt mehr als eine halbe Fensterhöhe daneben');
      expect(tester.getTopLeft(treffer).dy, closeTo(300, 1.0));
    });
  }
}
