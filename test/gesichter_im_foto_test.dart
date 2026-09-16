import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/asset_viewer_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/gesichtsrahmen.dart';
import 'package:provider/provider.dart';

/// Wer ist auf diesem Foto?
///
/// **Die Frage hatte bisher keine Antwort im Bild.** Die Info-Ansicht
/// zählt die benannten Personen als Reihe von Köpfen auf – sie sagt aber
/// nicht, welcher Kopf im Bild welcher ist, und die unbenannten Gesichter
/// verschweigt sie ganz. Die Rahmen gab es nur in der
/// Gesichts-Bearbeitung, und die erreichte man ausschliesslich über ein
/// Rechtsklick-Menü in der Vollbildansicht.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths pfade;
  late LibraryState bibliothek;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_gesichter_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')));
    bibliothek = LibraryState()
      ..db = db
      ..paths = pfade
      ..backupService = BackupService(db, pfade);
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<AssetData> foto({bool masse = true}) async {
    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: 'f1',
          originalFileName: 'f1.jpg',
          relativePath: 'originals/f1.jpg',
          checksum: 'pruef-f1',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2026, 6, 14),
          importedAt: DateTime(2026),
          widthPx: masse ? const Value(1000) : const Value.absent(),
          heightPx: masse ? const Value(800) : const Value.absent(),
        ));
    return (await db.assetById('f1'))!;
  }

  Future<void> gesicht(String id,
      {String? personId, double x = 0.1, bool ignoriert = false}) async {
    await db.insertFace(FacesCompanion.insert(
      id: id,
      assetId: 'f1',
      personId: Value(personId),
      boxX: x,
      boxY: 0.1,
      boxW: 0.2,
      boxH: 0.25,
      isIgnored: Value(ignoriert),
    ));
  }

  Future<void> zeige(WidgetTester tester, AssetData asset) async {
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: bibliothek,
      child: MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: AssetViewerScreen(
          assets: [asset],
          initialIndex: 0,
          paths: pfade,
          db: db,
          library: bibliothek,
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('der Knopf steht in der Leiste, nicht im Rechtsklick-Menü',
      (tester) async {
    // Dieselbe Krankheit wie beim Papierkorb ohne Tür: Was nur über eine
    // verborgene Geste erreichbar ist, findet niemand.
    await zeige(tester, await foto());
    expect(find.byTooltip('Gesichter zeigen'), findsOneWidget);
  });

  testWidgets('eingeschaltet stehen die Namen im Bild', (tester) async {
    await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anna'));
    final a = await foto();
    await gesicht('g1', personId: 'p1');
    await gesicht('g2', x: 0.5);
    await zeige(tester, a);

    // Gegenprobe: ausgeschaltet ist nichts zu sehen.
    expect(find.byType(Gesichtsrahmen), findsNothing);

    await tester.tap(find.byTooltip('Gesichter zeigen'));
    await tester.pumpAndSettle();

    expect(find.byType(Gesichtsrahmen), findsNWidgets(2));
    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('Unbenannt'), findsOneWidget,
        reason: 'auch das unbenannte Gesicht gehört ins Bild');
  });

  testWidgets('die Rahmen liegen auf dem Foto, nicht auf dem Fenster',
      (tester) async {
    // Der Kasten steht als Anteil in der Datenbank, und zwar als Anteil
    // des FOTOS. Das Foto ist 1000 zu 800, das Fenster 800 zu 600 – wer
    // die Anteile auf das Fenster rechnet, bekommt andere Zahlen heraus
    // und legt jeden Rahmen daneben.
    final a = await foto();
    await gesicht('links', x: 0.0);
    await gesicht('rechts', x: 0.6);
    await zeige(tester, a);
    await tester.tap(find.byTooltip('Gesichter zeigen'));
    await tester.pumpAndSettle();

    // Die angezeigte Fläche des Fotos selbst.
    final bild = tester.getRect(find.byType(Image));
    expect(bild.width / bild.height, closeTo(1000 / 800, 0.01),
        reason: 'die Fläche muss das Seitenverhältnis des Fotos haben');

    final kaesten = {
      for (final r
          in tester.widgetList<Gesichtsrahmen>(find.byType(Gesichtsrahmen)))
        r.gesicht.id: tester.getRect(find.byWidget(r)),
    };
    for (final (id, anteil) in [('links', 0.0), ('rechts', 0.6)]) {
      expect((kaesten[id]!.left - bild.left) / bild.width,
          closeTo(anteil, 0.01),
          reason: id);
      expect(kaesten[id]!.width / bild.width, closeTo(0.2, 0.01), reason: id);
      expect(kaesten[id]!.height / bild.height, closeTo(0.25, 0.01),
          reason: id);
    }
  });

  testWidgets('ein beiseitegelegtes Gesicht bleibt weg', (tester) async {
    // Wer ein Plakatgesicht weggelegt hat, will es nicht bei jedem
    // Ansehen des Fotos wiedersehen.
    final a = await foto();
    await gesicht('g1', ignoriert: true);
    await zeige(tester, a);
    await tester.tap(find.byTooltip('Gesichter zeigen'));
    await tester.pumpAndSettle();
    expect(find.byType(Gesichtsrahmen), findsNothing);
  });

  testWidgets('ohne Gesicht sagt die Ansicht das auch', (tester) async {
    // Sonst sähe der Knopf bei einer Landschaftsaufnahme kaputt aus.
    await zeige(tester, await foto());
    await tester.tap(find.byTooltip('Gesichter zeigen'));
    // Nicht pumpAndSettle: Ohne Rahmen bleibt es beim gewöhnlichen
    // Bildbetrachter, und dessen Ladekreisel dreht sich im Prüfstand
    // ewig – die Datei gibt es dort nicht.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('kein Gesicht erkannt'), findsOneWidget);
  });

  testWidgets('ein Tipp auf ein unbenanntes Gesicht fragt nach dem Namen',
      (tester) async {
    // Der eigentliche Mangel: Benennen ging nur über „das erste
    // unbenannte Gesicht dieses Fotos" in der Info-Ansicht. Bei einer
    // Gruppenaufnahme benannte man damit blind irgendwen.
    final a = await foto();
    await gesicht('g1');
    await zeige(tester, a);
    await tester.tap(find.byTooltip('Gesichter zeigen'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Gesichtsrahmen));
    await tester.pumpAndSettle();
    expect(find.text('Gesicht benennen'), findsOneWidget);
  });
}
