import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/l10n/app_localizations_de.dart';
import 'package:photo_vault/screens/asset_viewer_screen.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/asset_info_sheet.dart';
import 'package:photo_vault/widgets/color_label_picker.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';
import 'package:photo_vault/widgets/star_rating.dart';
import 'package:provider/provider.dart';

/// Ein Foto im gesperrten Ordner lässt sich ansehen, aber nicht bearbeiten
/// (#492): Jede Eingabe stünde sonst im Klartext in der Datenbank, und beim
/// Herausnehmen überschriebe das verschlüsselte Paket sie wieder.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths pfade;
  late LibraryState bibliothek;
  late AssetData gesperrt;
  late List<int> paketVorher;
  final de = AppTexteDe();

  File paket() => pfade.absolute(pfade.vaultMetadataRelativePath(gesperrt.id));

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_gesperrtes_infoblatt_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(wurzel.path, 'lib')),
    );
    bibliothek = LibraryState()
      ..db = db
      ..paths = pfade
      ..klartextOrdnerFuerTests = Directory(p.join(wurzel.path, 'klartext'));
    final eingang = Directory(p.join(wurzel.path, 'eingang'))
      ..createSync(recursive: true);
    final datei = File(p.join(eingang.path, 'see.jpg'))
      ..writeAsBytesSync([3, 1, 4, 1, 5, 9, 2, 6]);
    final ergebnis = await ImportService(db, pfade).importFile(datei.path);
    final id = ergebnis.assetId!;
    await db.fuehreAus(BeschreibungSetzen([id], 'Am See'));
    await db.fuehreAus(BewertungSetzen([id], 4));
    await db.fuehreAus(FarbmarkeSetzen([id], 'red'));
    await db.fuehreAus(OrtSetzen([id], 52.5, 13.4));
    await db.fuehreAus(SchlagwortAnheften([id], 'Urlaub'));
    await bibliothek.setupVaultPin('1234');
    await bibliothek.lockAsset((await db.assetById(id))!);
    gesperrt = (await db.assetById(id))!;
    expect(gesperrt.isLocked, isTrue);
    expect(gesperrt.description, isNull);
    paketVorher = paket().readAsBytesSync();
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> warte(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  /// Bis das Blatt das Paket gelesen hat (echte Dateizugriffe und
  /// Entschlüsselung, die Zeit dafür schwankt).
  Future<void> warteAufPaket(WidgetTester tester) async {
    for (var i = 0; i < 100 && find.text('see.jpg').evaluate().isEmpty; i++) {
      await warte(tester);
    }
  }

  Widget app(Widget home) => ChangeNotifierProvider.value(
    value: bibliothek,
    child: MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: home,
    ),
  );

  Future<void> erwarteUnveraendert(WidgetTester tester) async {
    final zeile = (await tester.runAsync(() => db.assetById(gesperrt.id)))!;
    expect(zeile.description, isNull);
    expect(zeile.rating, 0);
    expect(zeile.colorLabel, isNull);
    expect(zeile.latitude, isNull);
    expect(zeile.isFavorite, isFalse);
    expect(await tester.runAsync(() => db.tagsForAsset(gesperrt.id)), isEmpty);
    expect(paket().readAsBytesSync(), paketVorher);
  }

  testWidgets('das Infoblatt zeigt die Angaben aus dem Paket, nur lesend', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var gemeldet = 0;
    await tester.pumpWidget(
      app(
        Scaffold(
          body: SizedBox(
            width: 340,
            child: AssetInfoSheet(
              asset: gesperrt,
              db: db,
              paths: pfade,
              onUpdated: (_) => gemeldet++,
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await warteAufPaket(tester);

    expect(find.text(de.infoGesperrtNurLesen), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is SelectableText && w.data == 'Am See'),
      findsOneWidget,
    );
    expect(find.text('see.jpg'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Urlaub'), findsOneWidget);
    final sterne = tester.widget<StarRating>(find.byType(StarRating));
    expect(sterne.value, 4);
    expect(sterne.onChanged, isNull);
    final marke = tester.widget<ColorLabelPicker>(
      find.byType(ColorLabelPicker),
    );
    expect(marke.value, 'red');
    expect(marke.onChanged, isNull);

    // Nichts, womit sich etwas ändern liesse – und keine Karte, deren
    // Kacheln den Ort an einen fremden Dienst verrieten.
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(InputChip), findsNothing);
    expect(find.byType(MiniLocationMap), findsNothing);
    expect(find.text(de.datierungTitel), findsNothing);
    expect(find.byTooltip(de.personZuordnenTitel), findsNothing);
    expect(find.byTooltip(de.allgBearbeiten), findsNothing);
    expect(find.byTooltip(de.infoOrtEntfernen), findsNothing);

    await tester.tap(find.byType(StarRating));
    await warte(tester);
    expect(gemeldet, 0);
    await erwarteUnveraendert(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('die Einzelansicht ändert ein gesperrtes Foto nicht', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // So, wie der gesperrte Ordner die Ansicht öffnet.
    await tester.pumpWidget(
      app(
        AssetViewerScreen(
          assets: [gesperrt],
          initialIndex: 0,
          paths: pfade,
          db: db,
          library: bibliothek,
          onDelete: (a) => db.fuehreAus(InDenPapierkorb([a.id])),
        ),
      ),
    );
    await warte(tester);
    expect(find.byTooltip(de.viewerFavoritSetzen), findsNothing);

    for (final taste in [
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.keyF,
    ]) {
      await tester.sendKeyEvent(taste);
      await warte(tester);
    }

    // Kein Rechtsklick-Menü: Jeder Punkt darin ändert die Aufnahme oder
    // sucht sie dort, wo eine gesperrte nicht steht.
    final mitte = tester.getCenter(find.byType(PageView));
    await tester.tapAt(mitte, buttons: kSecondaryMouseButton);
    await warte(tester);
    expect(find.byType(MenuItemButton), findsNothing);

    await tester.tap(find.byTooltip(de.viewerInfo));
    await warteAufPaket(tester);
    expect(find.text(de.infoGesperrtNurLesen), findsOneWidget);
    expect(find.text('see.jpg'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await erwarteUnveraendert(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
