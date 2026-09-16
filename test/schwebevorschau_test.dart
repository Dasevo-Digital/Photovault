// Die Schwebe-Vorschau: Wenn die Maus einen Augenblick über einem Video
// oder einem Live Photo stehen bleibt, läuft es an.
//
// Zwei Ebenen: die Entscheidung, welche Kachel überhaupt ein Video trägt
// (reine Rechnung), und die Kachel selbst – dass sie wartet, statt sofort
// zu starten, und dass sie beim Verlassen wieder aufhört.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/db/rasterzeile.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/schwebevorschau.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';
import 'package:photo_vault/widgets/schwebevorschau.dart';

AssetData _asset({
  String id = 'a1',
  String type = 'IMAGE',
  String? linkedAssetId,
  bool isLocked = false,
}) {
  return AssetData(
    id: id,
    originalFileName: '$id.jpg',
    relativePath: 'o/$id.jpg',
    checksum: 'c$id',
    type: type,
    fileCreatedAt: DateTime(2026, 3, 12),
    importedAt: DateTime(2026, 3, 12),
    isFavorite: false,
    isTrashed: false,
    isLocked: isLocked,
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
    linkedAssetId: linkedAssetId,
  );
}

/// Steht im Test fuer das laufende Videobild.
const _laufendesBild = Key('laufendes-bild');

/// Eine Vorschau, die nichts abspielt, sondern nur mitschreibt. Der echte
/// Abspieler wäre ein mpv-Prozess – siehe [SchwebevorschauScope].
class _Mitschrift extends Schwebevorschau {
  final gestartet = <String>[];
  final beendet = <String>[];
  String? _aktiv;

  @override
  String? get aktivesAsset => _aktiv;

  @override
  Future<void> starte(Rasterzeile asset) async {
    if (schwebeVideoId(asset) == null) return;
    gestartet.add(asset.id);
    _aktiv = asset.id;
    notifyListeners();
  }

  @override
  void beende(String assetId) {
    if (_aktiv != assetId) return;
    beendet.add(assetId);
    _aktiv = null;
    notifyListeners();
  }

  @override
  Widget? bildFuer(String assetId) =>
      _aktiv == assetId ? const SizedBox(key: _laufendesBild) : null;
}

void main() {
  setUpAll(initializeDateFormatting);

  group('Welche Kachel überhaupt ein Video trägt', () {
    test('ein Video: es selbst', () {
      expect(schwebeVideoId(Rasterzeile.aus(_asset(id: 'v1', type: 'VIDEO'))), 'v1');
    });

    test('ein Live Photo: die verknüpfte Hälfte', () {
      expect(schwebeVideoId(Rasterzeile.aus(_asset(id: 'p1', linkedAssetId: 'v9'))), 'v9');
    });

    test('ein gewöhnliches Foto: nichts', () {
      expect(schwebeVideoId(Rasterzeile.aus(_asset())), isNull);
    });

    test('eine gesperrte Aufnahme bleibt still', () {
      // Sie abzuspielen hiesse, sie nebenbei zu entschlüsseln – und der
      // Klartext bliebe liegen, weil niemand ihn angefordert hat.
      expect(schwebeVideoId(Rasterzeile.aus(_asset(id: 'v1', type: 'VIDEO', isLocked: true))),
          isNull);
      expect(
          schwebeVideoId(Rasterzeile.aus(_asset(id: 'p1', linkedAssetId: 'v9', isLocked: true))),
          isNull);
    });
  });

  group('Die Kachel', () {
    late Directory wurzel;
    late StoragePaths paths;

    setUp(() async {
      wurzel = Directory.systemTemp.createTempSync('pv_schwebe_');
      // ignore: invalid_use_of_visible_for_testing_member
      paths = await StoragePaths.forTesting(wurzel);
    });

    tearDown(() => wurzel.deleteSync(recursive: true));

    Future<_Mitschrift> baue(WidgetTester tester, AssetData asset) async {
      final mitschrift = _Mitschrift();
      addTearDown(mitschrift.dispose);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: SchwebevorschauScope(
            vorschau: mitschrift,
            child: Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: AssetThumbnailTile(
                    asset: Rasterzeile.aus(asset), paths: paths, onTap: () {}),
              ),
            ),
          ),
        ),
      ));
      return mitschrift;
    }

    /// Führt den Zeiger auf die Kachel und lässt ihn dort stehen.
    Future<TestGesture> zeigeAuf(WidgetTester tester) async {
      final geste = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await geste.addPointer(location: Offset.zero);
      addTearDown(geste.removePointer);
      await tester.pump();
      await geste.moveTo(tester.getCenter(find.byType(AssetThumbnailTile)));
      await tester.pump();
      return geste;
    }

    testWidgets('startet erst, wenn der Zeiger lange genug steht',
        (tester) async {
      final mitschrift = await baue(tester, _asset(id: 'v1', type: 'VIDEO'));
      await zeigeAuf(tester);

      // Kurz davor passiert noch nichts – sonst zöge ein Zeiger, der quer
      // über die Wand fährt, eine Spur anlaufender Videos hinter sich her.
      await tester.pump(schwebeVerzoegerung - const Duration(milliseconds: 50));
      expect(mitschrift.gestartet, isEmpty);

      await tester.pump(const Duration(milliseconds: 100));
      expect(mitschrift.gestartet, ['v1']);
    });

    testWidgets('ein Live Photo läuft genauso an', (tester) async {
      final mitschrift =
          await baue(tester, _asset(id: 'p1', linkedAssetId: 'v9'));
      await zeigeAuf(tester);
      await tester.pump(schwebeVerzoegerung);
      expect(mitschrift.gestartet, ['p1']);
    });

    testWidgets('ein gewöhnliches Foto läuft nie an', (tester) async {
      final mitschrift = await baue(tester, _asset());
      await zeigeAuf(tester);
      await tester.pump(schwebeVerzoegerung * 3);
      expect(mitschrift.gestartet, isEmpty);
    });

    testWidgets('wer vorher weiterzieht, löst nichts aus', (tester) async {
      final mitschrift = await baue(tester, _asset(id: 'v1', type: 'VIDEO'));
      final geste = await zeigeAuf(tester);
      await tester.pump(schwebeVerzoegerung - const Duration(milliseconds: 50));
      await geste.moveTo(const Offset(5, 5));
      await tester.pump(schwebeVerzoegerung * 3);
      expect(mitschrift.gestartet, isEmpty);
    });

    testWidgets('das Verlassen hält es wieder an', (tester) async {
      final mitschrift = await baue(tester, _asset(id: 'v1', type: 'VIDEO'));
      final geste = await zeigeAuf(tester);
      await tester.pump(schwebeVerzoegerung);
      expect(mitschrift.aktivesAsset, 'v1');

      await geste.moveTo(const Offset(5, 5));
      await tester.pump();
      expect(mitschrift.beendet, ['v1']);
      expect(mitschrift.aktivesAsset, isNull);
    });

    testWidgets('das laufende Bild liegt über der Kachel', (tester) async {
      final mitschrift = await baue(tester, _asset(id: 'v1', type: 'VIDEO'));
      expect(find.byKey(_laufendesBild), findsNothing);
      await zeigeAuf(tester);
      await tester.pump(schwebeVerzoegerung);
      await tester.pump();
      expect(find.byKey(_laufendesBild), findsOneWidget);
      expect(mitschrift.aktivesAsset, 'v1');
    });

    testWidgets('aus dem Bild gescrollt heisst angehalten', (tester) async {
      final mitschrift = await baue(tester, _asset(id: 'v1', type: 'VIDEO'));
      await zeigeAuf(tester);
      await tester.pump(schwebeVerzoegerung);
      expect(mitschrift.aktivesAsset, 'v1');

      // Die Kachel verschwindet - genau das tut sie beim Scrollen.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      expect(mitschrift.beendet, ['v1']);
    });

    testWidgets('ohne Bereich darüber verhält sich die Kachel wie zuvor',
        (tester) async {
      // Alle zwanzig anderen Aufrufer der Kachel gehen diesen Weg, wenn
      // sie ausserhalb der App gebaut werden - etwa in einem Test.
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 200,
            child: AssetThumbnailTile(
                asset: Rasterzeile.aus(_asset(id: 'v1', type: 'VIDEO')),
                paths: paths,
                onTap: () {}),
          ),
        ),
      ));
      final geste = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await geste.addPointer(location: Offset.zero);
      addTearDown(geste.removePointer);
      await geste.moveTo(tester.getCenter(find.byType(AssetThumbnailTile)));
      await tester.pump(schwebeVerzoegerung * 3);
      expect(tester.takeException(), isNull);
    });
  });
}
