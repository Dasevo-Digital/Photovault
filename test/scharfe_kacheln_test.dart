import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/bilddekodierung.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';

/// Grosse Kacheln sehen scharf aus: Braucht eine Kachel mehr Bildpunkte als
/// die Miniatur mit 400 Punkten hat, holt sie nach kurzem Halt die
/// angezeigte Fassung dazu. Bis dahin – und in kleinen Kacheln immer –
/// bleibt es bei der Miniatur.
AssetData _foto({
  String type = 'IMAGE',
  String relativePath = 'originals/a.dng',
  String? preview = 'previews/a.jpg',
  String? developed,
  int breite = 4032,
  int hoehe = 3024,
}) => AssetData(
  id: 'a',
  originalFileName: 'a.dng',
  relativePath: relativePath,
  thumbnailRelativePath: 'thumbnails/a.jpg',
  previewRelativePath: preview,
  developedRelativePath: developed,
  widthPx: breite,
  heightPx: hoehe,
  checksum: 'ca',
  type: type,
  fileCreatedAt: DateTime(2026, 11, 7),
  importedAt: DateTime(2026, 11, 7),
  isFavorite: false,
  isArchived: false,
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
  transkriptGeprueft: false,
  isStackCover: false,
);

void main() {
  group('brauchtMehrAlsMiniatur', () {
    test('kleine Kachel: die Miniatur reicht', () {
      // 160 Punkte bei doppelter Dichte, Querformat: 320 von 400.
      final m = deckendeDekodiermasse(
        kachelBreite: 160,
        kachelHoehe: 120,
        bildBreite: 4032,
        bildHoehe: 3024,
        pixelverhaeltnis: 2,
      );
      expect(
        brauchtMehrAlsMiniatur(m, bildBreite: 4032, bildHoehe: 3024),
        isFalse,
      );
    });

    test('grosse Kachel wie in der Meldung: 270 Punkte bei Retina', () {
      final m = deckendeDekodiermasse(
        kachelBreite: 270,
        kachelHoehe: 203,
        bildBreite: 4032,
        bildHoehe: 3024,
        pixelverhaeltnis: 2,
      );
      expect(
        brauchtMehrAlsMiniatur(m, bildBreite: 4032, bildHoehe: 3024),
        isTrue,
      );
    });

    test('Hochformat in quadratischer Kachel: bindend ist die Breite', () {
      // Hochformat: Die Miniatur ist 300 breit; die Kachel braucht 384.
      final m = deckendeDekodiermasse(
        kachelBreite: 192,
        kachelHoehe: 192,
        bildBreite: 3024,
        bildHoehe: 4032,
        pixelverhaeltnis: 2,
      );
      expect(m.breite, isNotNull);
      expect(
        brauchtMehrAlsMiniatur(m, bildBreite: 3024, bildHoehe: 4032),
        isTrue,
      );
    });

    test('ohne Masse des Fotos: nichts nachladen', () {
      expect(
        brauchtMehrAlsMiniatur(
          (breite: 2000, hoehe: null),
          bildBreite: null,
          bildHoehe: null,
        ),
        isFalse,
      );
    });
  });

  group('schaerfereKachelquelle', () {
    test('die angezeigte Fassung, wenn Flutter sie liest', () {
      expect(
        schaerfereKachelquelle(
          type: 'IMAGE',
          relativePath: 'originals/a.dng',
          fassung: 'previews/a.jpg',
        ),
        'previews/a.jpg',
      );
    });
    test('ein JPEG ohne Vorschau: das Original', () {
      expect(
        schaerfereKachelquelle(
          type: 'IMAGE',
          relativePath: 'originals/a.JPG',
          fassung: null,
        ),
        'originals/a.JPG',
      );
    });
    test('RAW ohne Vorschau und Video ohne Standbild: keine', () {
      expect(
        schaerfereKachelquelle(
          type: 'IMAGE',
          relativePath: 'originals/a.dng',
          fassung: null,
        ),
        isNull,
      );
      expect(
        schaerfereKachelquelle(
          type: 'VIDEO',
          relativePath: 'originals/a.mov',
          fassung: 'trimmed/a.mp4',
        ),
        isNull,
      );
    });
  });

  group('Kachel', () {
    late Directory wurzel;
    late StoragePaths paths;

    setUpAll(() => initializeDateFormatting('de'));
    setUp(() async {
      wurzel = await Directory.systemTemp.createTemp('pv_scharf_');
      paths = await StoragePaths.forTesting(wurzel);
    });
    tearDown(() => wurzel.delete(recursive: true));

    Future<void> zeige(WidgetTester tester, AssetData a, double kante) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: kante,
                height: kante * 0.75,
                child: AssetThumbnailTile(
                  asset: Rasterzeile.aus(a),
                  paths: paths,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
    }

    Iterable<String> bildpfade(WidgetTester tester) => tester
        .widgetList<Image>(find.byType(Image))
        .map(
          (i) => switch (i.image) {
            final ResizeImage r => r.imageProvider,
            final p => p,
          },
        )
        .whereType<FileImage>()
        .map((f) => f.file.path.substring(wurzel.path.length + 1));

    testWidgets('klein: nur die Miniatur', (tester) async {
      await zeige(tester, _foto(), 150);
      await tester.pump(const Duration(seconds: 1));
      expect(bildpfade(tester), ['thumbnails/a.jpg']);
    });

    testWidgets('gross: erst die Miniatur, nach kurzem Halt die Vorschau', (
      tester,
    ) async {
      await zeige(tester, _foto(), 300);
      expect(bildpfade(tester), ['thumbnails/a.jpg']);
      await tester.pump(const Duration(milliseconds: 300));
      expect(bildpfade(tester), ['thumbnails/a.jpg', 'previews/a.jpg']);
    });

    testWidgets('gross und entwickelt: die Entwicklung', (tester) async {
      await zeige(tester, _foto(developed: 'developed/a.jpg'), 300);
      await tester.pump(const Duration(milliseconds: 300));
      expect(bildpfade(tester).last, 'developed/a.jpg');
    });

    testWidgets('weggescrollt vor dem Halt: nichts geholt', (tester) async {
      await zeige(tester, _foto(), 300);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(Image), findsNothing);
    });
  });
}
