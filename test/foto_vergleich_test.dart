import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/photo_compare_screen.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// Zwei frei gewählte Fotos nebeneinander.
///
/// Der Kern ist die Kopplung: Beide Seiten teilen sich einen
/// [TransformationController]. Zwei getrennte Regler mit einem Abgleich
/// dazwischen wären fehleranfällig und immer einen Frame hinterher – und
/// genau daran merkt man beim Vergleichen zweier fast gleicher Aufnahmen,
/// dass etwas nicht stimmt.
void main() {
  late Directory tempRoot;
  late StoragePaths paths;

  AssetData asset(String id) => AssetData(
        id: id,
        relativePath: 'originals/$id.png',
        originalFileName: '$id.png',
        type: 'IMAGE',
        fileSizeBytes: 100,
        checksum: id,
        fileCreatedAt: DateTime(2026, 1, 1),
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
        aiCaptionEdited: false,
        aiTagsScanned: false,
        isStackCover: false,
        rating: 0,
      );

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_vergleich_');
    paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
    for (final id in ['a', 'b']) {
      final datei = paths.absolute('originals/$id.png');
      datei.parent.createSync(recursive: true);
      final bild = img.Image(width: 20, height: 20);
      img.fill(bild, color: img.ColorRgb8(id == 'a' ? 200 : 40, 80, 80));
      datei.writeAsBytesSync(Uint8List.fromList(img.encodePng(bild)));
    }
  });

  tearDown(() => tempRoot.deleteSync(recursive: true));

  Future<void> zeige(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: PhotoCompareScreen(links: asset('a'), rechts: asset('b'), paths: paths),
    ));
    await tester.pumpAndSettle();
  }

  List<TransformationController> regler(WidgetTester tester) => tester
      .widgetList<InteractiveViewer>(find.byType(InteractiveViewer))
      .map((v) => v.transformationController!)
      .toList();

  /// Genau das, was macOS bei einer Wischgeste auf einer Tastflaeche
  /// schickt: eine Pan-Zoom-Folge, kein Radschritt.
  Future<void> wischen(WidgetTester tester, Offset stelle,
      {required double wegY}) async {
    final geste = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await geste.panZoomStart(stelle);
    for (var i = 1; i <= 5; i++) {
      await geste.panZoomUpdate(stelle, pan: Offset(0, wegY * i / 5));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await geste.panZoomEnd();
    await tester.pumpAndSettle();
  }

  testWidgets('Wischen zoomt, statt nur zu verschieben', (tester) async {
    // Eine Magic Mouse hat kein Rad, sondern eine Tastflaeche; macOS
    // meldet ein Wischen darauf wie ein Trackpad. Flutters Vorgabe fuer
    // solche Eingaben ist VERSCHIEBEN - ohne
    // `trackpadScrollCausesScale: true` liesse sich hier also mit einer
    // solchen Maus ueberhaupt nicht zoomen.
    await zeige(tester);
    final stelle = tester.getCenter(find.byType(InteractiveViewer).first);
    final vorher = regler(tester).first.value.getMaxScaleOnAxis();

    await wischen(tester, stelle, wegY: -120);

    final nachher = regler(tester).first.value.getMaxScaleOnAxis();
    expect(nachher, greaterThan(vorher),
        reason: 'nach oben wischen muss vergroessern');
  });

  testWidgets('nach unten wischen zoomt wieder heraus', (tester) async {
    await zeige(tester);
    final stelle = tester.getCenter(find.byType(InteractiveViewer).first);
    await wischen(tester, stelle, wegY: -200);
    final vergroessert = regler(tester).first.value.getMaxScaleOnAxis();
    await wischen(tester, stelle, wegY: 120);
    expect(regler(tester).first.value.getMaxScaleOnAxis(),
        lessThan(vergroessert));
  });

  testWidgets('beide Fotos stehen mit ihrem Namen da', (tester) async {
    await zeige(tester);
    expect(find.text('a.png'), findsOneWidget);
    expect(find.text('b.png'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsNWidgets(2));
  });

  testWidgets('gekoppelt teilen sich beide Seiten denselben Regler',
      (tester) async {
    await zeige(tester);
    final r = regler(tester);
    expect(identical(r[0], r[1]), isTrue,
        reason: 'ein Regler für beide – das IST die Kopplung');
  });

  testWidgets('was links gezoomt wird, gilt rechts genauso', (tester) async {
    await zeige(tester);
    final r = regler(tester);
    r[0].value = Matrix4.identity()..scaleByDouble(3.0, 3.0, 3.0, 1.0);
    await tester.pump();

    final wieder = regler(tester);
    expect(wieder[1].value.getMaxScaleOnAxis(), closeTo(3.0, 1e-9));
  });

  testWidgets('entkoppelt laufen die Seiten getrennt', (tester) async {
    await zeige(tester);
    await tester.tap(find.byTooltip('Ansichten entkoppeln'));
    await tester.pumpAndSettle();

    final r = regler(tester);
    expect(identical(r[0], r[1]), isFalse);
    r[0].value = Matrix4.identity()..scaleByDouble(4.0, 4.0, 4.0, 1.0);
    await tester.pump();
    expect(regler(tester)[1].value.getMaxScaleOnAxis(), closeTo(1.0, 1e-9));
  });

  testWidgets('beim erneuten Koppeln übernimmt die linke Sicht',
      (tester) async {
    // Sonst spränge die rechte Seite auf einen alten Ausschnitt zurück,
    // und man müsste sie von Hand nachziehen – genau das, was die
    // Kopplung ersparen soll.
    await zeige(tester);
    await tester.tap(find.byTooltip('Ansichten entkoppeln'));
    await tester.pumpAndSettle();
    regler(tester)[0].value = Matrix4.identity()..scaleByDouble(2.5, 2.5, 2.5, 1.0);
    await tester.pump();

    await tester.tap(find.byTooltip('Ansichten koppeln'));
    await tester.pumpAndSettle();
    expect(regler(tester)[1].value.getMaxScaleOnAxis(), closeTo(2.5, 1e-9));
  });

  testWidgets('Zurücksetzen bringt beide auf Anfang', (tester) async {
    await zeige(tester);
    regler(tester)[0].value = Matrix4.identity()..scaleByDouble(5.0, 5.0, 5.0, 1.0);
    await tester.pump();

    await tester.tap(find.byTooltip('Zoom zurücksetzen'));
    await tester.pumpAndSettle();
    expect(regler(tester)[0].value.getMaxScaleOnAxis(), closeTo(1.0, 1e-9));
  });

  testWidgets('übereinander statt nebeneinander', (tester) async {
    // Bei Hochformaten die bessere Aufteilung – nebeneinander blieben zwei
    // schmale Streifen.
    await zeige(tester);
    final nebenLinks = tester.getCenter(find.text('a.png'));
    final nebenRechts = tester.getCenter(find.text('b.png'));
    expect(nebenRechts.dx, greaterThan(nebenLinks.dx));

    await tester.tap(find.byTooltip('Übereinander'));
    await tester.pumpAndSettle();
    final obenA = tester.getCenter(find.text('a.png'));
    final untenB = tester.getCenter(find.text('b.png'));
    expect(untenB.dy, greaterThan(obenA.dy));
    expect((untenB.dx - obenA.dx).abs(), lessThan(1));
  });
}
