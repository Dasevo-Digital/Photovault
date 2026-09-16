import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/db/rasterzeile.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';
import 'package:photo_vault/widgets/color_label_picker.dart';
import 'package:photo_vault/widgets/star_rating.dart';

/// Prüft, dass die im Zuge des Barrierefreiheits-Durchgangs ergänzten
/// Semantics-Labels tatsächlich ankommen (nicht nur Codelesen) – siehe
/// AssetThumbnailTile, StarRating, ColorLabelPicker.
void main() {
  setUpAll(() async {
    // Ohne Argument, weil die Labels seit dem Sprach-Durchgang über die
    // aktive Locale formatiert werden und nicht mehr über ein festes 'de_DE'.
    await initializeDateFormatting();
  });

  group('AssetThumbnailTile Semantics', () {
    late Directory tempRoot;
    late StoragePaths paths;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('photo_vault_thumb_semantics_test_');
      paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
    });

    tearDown(() {
      tempRoot.deleteSync(recursive: true);
    });

    AssetData buildAsset({
      required String type,
      bool isFavorite = false,
      int rating = 0,
      double? durationSeconds,
    }) {
      return AssetData(
        id: 'a1',
        originalFileName: 'IMG_0001.jpg',
        relativePath: 'originals/2025/03/a1.jpg',
        checksum: 'chk1',
        type: type,
        fileCreatedAt: DateTime(2025, 3, 12),
        importedAt: DateTime(2025, 3, 12),
        isFavorite: isFavorite,
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
        rating: rating,
        ocrScanned: false,
        aiCaptionScanned: false,
        aiCaptionEdited: false,
        aiTagsScanned: false,
        isStackCover: false,
        durationSeconds: durationSeconds,
      );
    }

    testWidgets('Label nennt Typ, Dateiname und Datum', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: AssetThumbnailTile(asset: Rasterzeile.aus(buildAsset(type: 'IMAGE')), paths: paths, onTap: () {}),
        ),
      ));

      expect(find.bySemanticsLabel('Foto IMG_0001.jpg, 12. März 2025'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('Favorit und Bewertung fließen ins Label ein', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: AssetThumbnailTile(
            asset: Rasterzeile.aus(buildAsset(type: 'IMAGE', isFavorite: true, rating: 4)),
            paths: paths,
            onTap: () {},
          ),
        ),
      ));

      expect(
        find.bySemanticsLabel(
          'Foto IMG_0001.jpg, 12. März 2025, favorisiert, Bewertung 4 von 5 Sternen',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('Video-Typ und Dauer fließen ins Label ein', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: AssetThumbnailTile(
            asset: Rasterzeile.aus(buildAsset(type: 'VIDEO', durationSeconds: 95)),
            paths: paths,
            onTap: () {},
          ),
        ),
      ));

      expect(find.bySemanticsLabel('Video IMG_0001.jpg, 12. März 2025, 1:35'), findsOneWidget);
      handle.dispose();
    });
  });

  group('StarRating Semantics', () {
    testWidgets('antippbar: jeder Stern trägt ein Setzen-Label', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(body: StarRating(value: 3, onChanged: (_) {})),
      ));

      for (var i = 1; i <= 5; i++) {
        expect(find.bySemanticsLabel('Bewertung: $i von 5 Sternen setzen'), findsOneWidget);
      }
      handle.dispose();
    });

    testWidgets('rein anzeigend: Label nennt Füllstatus statt Aktion', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(const MaterialApp(
        locale: Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(body: StarRating(value: 2)),
      ));

      expect(find.bySemanticsLabel('Stern 1 von 5, ausgefüllt'), findsOneWidget);
      expect(find.bySemanticsLabel('Stern 2 von 5, ausgefüllt'), findsOneWidget);
      expect(find.bySemanticsLabel('Stern 3 von 5'), findsOneWidget);
      handle.dispose();
    });
  });

  group('ColorLabelPicker Semantics', () {
    testWidgets('jede Farbe trägt ein deutsches Label, Auswahl ist erkennbar', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(body: ColorLabelPicker(value: 'green', onChanged: (_) {})),
      ));

      expect(find.bySemanticsLabel('Grün, ausgewählt'), findsOneWidget);
      expect(find.bySemanticsLabel('Farbmarkierung Rot setzen'), findsOneWidget);
      expect(find.bySemanticsLabel('Farbmarkierung Gelb setzen'), findsOneWidget);
      expect(find.bySemanticsLabel('Farbmarkierung Blau setzen'), findsOneWidget);
      expect(find.bySemanticsLabel('Farbmarkierung Violett setzen'), findsOneWidget);
      handle.dispose();
    });
  });
}
