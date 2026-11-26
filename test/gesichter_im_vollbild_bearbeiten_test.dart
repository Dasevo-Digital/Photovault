import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/asset_viewer_screen.dart';
import 'package:photo_vault/screens/face_review_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/gesichtsrahmen.dart';
import 'package:provider/provider.dart';

/// Gesichter im Vollbild vollständig bearbeiten (#495).
///
/// Bisher konnte man im Vollbild ein Gesicht nur benennen und eines
/// nachtragen. Wer eine Fehlerkennung wegräumen, eine Zuordnung lösen oder
/// das Foto von der Suche ausnehmen wollte, musste über „Gesichter
/// bearbeiten“ in einen zweiten Bildschirm, dort dasselbe Foto noch einmal
/// laden und danach zurück. Jetzt steht alles im Rechtsklick-Menü des
/// Vollbilds: auf dem Rahmen für dieses Gesicht, im Untermenü für das
/// ganze Foto.
void main() {
  final de = lookupAppTexte(const Locale('de'));
  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths pfade;
  late LibraryState bibliothek;
  var ruhig = true;

  setUp(() async {
    ruhig = true;
    wurzel = Directory.systemTemp.createTempSync('pv_gesichter_vollbild_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(wurzel.path, 'lib')),
    );
    bibliothek = LibraryState()
      ..db = db
      ..paths = pfade
      ..backupService = BackupService(db, pfade);
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'f1',
            originalFileName: 'f1.jpg',
            relativePath: 'originals/f1.jpg',
            checksum: 'pruef-f1',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 6, 14),
            importedAt: DateTime(2026),
            widthPx: const Value(1000),
            heightPx: const Value(800),
          ),
        );
    await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anna'));
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> gesicht(
    String id, {
    String? personId,
    double x = 0.1,
    bool ignoriert = false,
  }) => db.insertFace(
    FacesCompanion.insert(
      id: id,
      assetId: 'f1',
      personId: Value(personId),
      boxX: x,
      boxY: 0.1,
      boxW: 0.2,
      boxH: 0.25,
      isIgnored: Value(ignoriert),
    ),
  );

  Finder rahmen(String id) =>
      find.byWidgetPredicate((w) => w is Gesichtsrahmen && w.gesicht.id == id);

  /// Öffnet das Foto und schaltet die Rahmen ein.
  Future<void> zeige(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: bibliothek,
        child: MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          theme: buildDarkTheme(),
          home: AssetViewerScreen(
            assets: [(await db.assetById('f1'))!],
            initialIndex: 0,
            paths: pfade,
            db: db,
            library: bibliothek,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip(de.viewerGesichterZeigen));
    await tester.pumpAndSettle();
  }

  /// Ohne Rahmen bleibt es beim gewöhnlichen Bildbetrachter, und dessen
  /// Ladekreisel dreht sich im Prüfstand ewig – die Datei gibt es dort
  /// nicht. Dann wird mit festen Schritten gewartet statt bis zur Ruhe.
  Future<void> warte(WidgetTester tester) async {
    if (ruhig) {
      await tester.pumpAndSettle();
      return;
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> rechtsklick(WidgetTester tester, Offset stelle) async {
    final maus = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await maus.down(stelle);
    await maus.up();
    await warte(tester);
  }

  /// Ein Rechtsklick neben die Rahmen, dann das Untermenü für das Foto.
  Future<void> untermenue(WidgetTester tester) async {
    final flaeche = tester.getRect(find.byType(PageView));
    await rechtsklick(tester, flaeche.bottomRight - const Offset(60, 60));
    await tester.tap(find.text(de.viewerGesichterBearbeiten));
    await warte(tester);
  }

  Future<void> waehle(WidgetTester tester, String eintrag) async {
    await tester.tap(find.text(eintrag));
    await warte(tester);
  }

  testWidgets('auf dem Rahmen stehen die Einträge für dieses Gesicht', (
    tester,
  ) async {
    await gesicht('g1');
    await gesicht('g2', personId: 'p1', x: 0.5);
    await zeige(tester);

    await rechtsklick(tester, tester.getCenter(rahmen('g1')));
    expect(find.text(de.gesichtBenennen), findsOneWidget);
    expect(find.text(de.gesichtIgnorieren), findsOneWidget);
    expect(find.text(de.gesichtErkennungLoeschen), findsOneWidget);
    expect(
      find.text(de.gesichtZuordnungLoesen),
      findsNothing,
      reason: 'unbenannt: nichts zu lösen',
    );
    // Das gewohnte Menü des Fotos bleibt darunter.
    expect(find.text(de.viewerAehnlicheZeigen), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await rechtsklick(tester, tester.getCenter(rahmen('g2')));
    expect(find.text(de.gesichtUmbenennen), findsOneWidget);
    expect(find.text(de.gesichtZuordnungLoesen), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // Daneben: kein Gesicht, also auch nichts zu löschen.
    final flaeche = tester.getRect(find.byType(PageView));
    await rechtsklick(tester, flaeche.bottomRight - const Offset(60, 60));
    expect(find.text(de.gesichtErkennungLoeschen), findsNothing);
    expect(find.text(de.viewerGesichterBearbeiten), findsOneWidget);
  });

  testWidgets('auch ein langer Rechtsklick auf den Rahmen trifft das Gesicht', (
    tester,
  ) async {
    // Hält man die Taste einen Augenblick, meldet sich nach dem Rahmen
    // auch die Fläche darunter – und die kennt kein Gesicht.
    await gesicht('g1');
    await zeige(tester);
    final maus = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await maus.down(tester.getCenter(rahmen('g1')));
    await tester.pump(const Duration(milliseconds: 300));
    await maus.up();
    await tester.pumpAndSettle();
    expect(find.text(de.gesichtErkennungLoeschen), findsOneWidget);
  });

  testWidgets('Ignorieren, Lösen und Löschen wirken sofort im Bild', (
    tester,
  ) async {
    await gesicht('g1');
    await gesicht('g2', personId: 'p1', x: 0.4);
    await gesicht('g3', x: 0.7);
    await zeige(tester);

    await rechtsklick(tester, tester.getCenter(rahmen('g1')));
    await waehle(tester, de.gesichtIgnorieren);
    expect(
      (await db.facesForAsset('f1')).firstWhere((f) => f.id == 'g1').isIgnored,
      isTrue,
    );
    expect(rahmen('g1'), findsNothing, reason: 'Ignorierte bleiben weg');

    await rechtsklick(tester, tester.getCenter(rahmen('g2')));
    await waehle(tester, de.gesichtZuordnungLoesen);
    final geloest = (await db.facesForAsset(
      'f1',
    )).firstWhere((f) => f.id == 'g2');
    expect(geloest.personId, isNull);
    expect(find.text('Anna'), findsNothing);

    await rechtsklick(tester, tester.getCenter(rahmen('g3')));
    await waehle(tester, de.gesichtErkennungLoeschen);
    expect((await db.facesForAsset('f1')).map((f) => f.id), ['g1', 'g2']);
    expect(rahmen('g3'), findsNothing);
    expect(find.byType(FaceReviewScreen), findsNothing);
  });

  testWidgets('Ignorierte lassen sich zeigen und mit einem Tipp zurückholen', (
    tester,
  ) async {
    await gesicht('g1', ignoriert: true);
    await gesicht('g2', x: 0.5);
    await zeige(tester);
    expect(rahmen('g1'), findsNothing);

    await untermenue(tester);
    await waehle(tester, de.viewerBeiseitegelegteZeigen(1));
    expect(rahmen('g1'), findsOneWidget);
    expect(find.text(de.gesichtIgnoriert), findsOneWidget);

    await tester.tap(rahmen('g1'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(
      (await db.facesForAsset('f1')).firstWhere((f) => f.id == 'g1').isIgnored,
      isFalse,
    );
    expect(find.text(de.gesichtIgnoriert), findsNothing);
  });

  testWidgets('das Foto von der Suche ausnehmen und zurückholen', (
    tester,
  ) async {
    await gesicht('g1');
    await zeige(tester);

    await untermenue(tester);
    await waehle(tester, de.gesichtNichtMehrDurchsuchen);
    expect((await db.assetById('f1'))!.faceScanExcluded, isTrue);
    expect(find.byType(FaceReviewScreen), findsNothing);

    // Das Menü kennt danach den neuen Stand.
    await untermenue(tester);
    await waehle(tester, de.gesichtWiederDurchsuchen);
    expect((await db.assetById('f1'))!.faceScanExcluded, isFalse);
  });

  testWidgets('die unbenannten auf einmal: ignorieren und löschen', (
    tester,
  ) async {
    await gesicht('g1');
    await gesicht('g2', x: 0.4);
    await gesicht('g3', personId: 'p1', x: 0.7);
    await zeige(tester);

    await untermenue(tester);
    await waehle(tester, de.gesichtAlleUnbenanntenIgnorieren(2));
    expect(
      [
        for (final f in await db.facesForAsset('f1'))
          if (f.isIgnored) f.id,
      ],
      ['g1', 'g2'],
    );

    // Löschen trifft auch die ignorierten, fragt aber vorher.
    await untermenue(tester);
    await waehle(tester, de.gesichtAlleUnbenanntenLoeschen(2));
    expect(find.text(de.gesichtUnbenannteLoeschenFrage(2)), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, de.allgLoeschen));
    await tester.pumpAndSettle();
    expect((await db.facesForAsset('f1')).map((f) => f.id), ['g3']);
    expect(find.text('Anna'), findsOneWidget, reason: 'benannte bleiben');
  });

  testWidgets('Nachtragen geht aus dem Untermenü, auch bei verborgenen '
      'Rahmen', (tester) async {
    await gesicht('g1');
    await zeige(tester);
    await tester.tap(find.byTooltip(de.viewerGesichterVerbergen));
    ruhig = false;
    await warte(tester);
    expect(rahmen('g1'), findsNothing);

    await untermenue(tester);
    await waehle(tester, de.viewerGesichtAufziehen);
    ruhig = true;
    await warte(tester);
    expect(rahmen('g1'), findsOneWidget, reason: 'die Rahmen sind wieder an');
    expect(find.byTooltip(de.viewerGesichtAufziehenEnde), findsOneWidget);
  });

  testWidgets('die Info-Ansicht zieht nach', (tester) async {
    await gesicht('g1', personId: 'p1');
    await gesicht('g2', x: 0.5);
    await zeige(tester);
    await tester.tap(find.byTooltip(de.viewerInfo));
    await tester.pumpAndSettle();
    expect(find.text('Anna'), findsNWidgets(2), reason: 'Rahmen und Info');

    await rechtsklick(tester, tester.getCenter(rahmen('g1')));
    await waehle(tester, de.gesichtZuordnungLoesen);
    expect(find.text('Anna'), findsNothing);
    expect(find.text(de.infoNiemandZugeordnet), findsOneWidget);
  });
}
