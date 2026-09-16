import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/people_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// Der Rechtsklick im Gesichts-Raster.
///
/// Zwei Dinge sind hier leicht falsch zu machen und im Quelltext nicht zu
/// sehen: ob der Rechtsklick überhaupt ankommt (das Raster liegt in einem
/// TabBarView über einer GridView, beide fangen Gesten), und ob die
/// Rückfrage vor dem Löschen wirklich erscheint. Ein Menüeintrag, der
/// ungefragt löscht, wäre der schlimmste Fehler dieser Funktion.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_kontext_');
    db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
    library = LibraryState()
      ..db = db
      ..paths = paths
      ..backupService = BackupService(db, paths);

    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: 'a1',
          originalFileName: 'a1.jpg',
          relativePath: 'originals/a1.jpg',
          checksum: 'c1',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2026, 1, 1),
          importedAt: DateTime(2026, 1, 1),
        ));
    for (var i = 0; i < 3; i++) {
      await db.insertFace(FacesCompanion.insert(
        id: 'f$i',
        assetId: 'a1',
        boxX: 0.1 * i,
        boxY: 0.1,
        boxW: 0.2,
        boxH: 0.2,
        cropRelativePath: Value('faces/f$i.jpg'),
      ));
    }
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  /// Der Reiter mit dieser Beschriftung.
  ///
  /// Nicht über `find.text`: An der Beschriftung hängt inzwischen die
  /// Anzahl in Klammern, und derselbe Wortlaut steht ausserdem im
  /// Hinweistext des leeren Personen-Reiters.
  Finder reiter(String beschriftung) => find.descendant(
        of: find.byType(Tab),
        matching: find.textContaining(beschriftung),
      );

  Future<void> zeige(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: Scaffold(body: PeopleScreen(library: library)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(reiter('Unbenannte Gesichter'));
    await tester.pumpAndSettle();
  }

  Future<void> rechtsklick(WidgetTester tester, Finder ziel) async {
    final stelle = tester.getCenter(ziel);
    final maus = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await maus.down(stelle);
    await maus.up();
    await tester.pumpAndSettle();
  }

  testWidgets('der Rechtsklick öffnet das Menü mit beiden Einträgen',
      (tester) async {
    await zeige(tester);
    await rechtsklick(tester, find.byType(GridView).first);

    expect(find.text('Alle unbenannten Gesichter ignorieren'), findsOneWidget);
    expect(find.text('Alle unbenannten Erkennungen löschen'), findsOneWidget);
    expect(find.textContaining('3 Gesichter wandern'), findsOneWidget,
        reason: 'der Eintrag muss sagen, wie viele es trifft');
  });

  testWidgets('„Alle ignorieren" räumt das Raster und füllt den Reiter',
      (tester) async {
    await zeige(tester);
    await rechtsklick(tester, find.byType(GridView).first);
    await tester.tap(find.text('Alle unbenannten Gesichter ignorieren'));
    await tester.pumpAndSettle();

    expect(await db.unassignedFaces(), isEmpty);
    expect(await db.ignoredFacesCount(), 3);
    expect(find.text('Ignoriert (3)'), findsOneWidget);
    // Umgekehrt muss die Zahl am geräumten Reiter verschwinden – nicht
    // „(0)" stehen bleiben.
    expect(reiter('Unbenannte Gesichter'), findsOneWidget);
    expect(find.text('Unbenannte Gesichter'), findsOneWidget,
        reason: 'ohne Zahl, sobald keine mehr da sind');
  });

  testWidgets('die Reiter tragen die Anzahl in Klammern', (tester) async {
    await zeige(tester);
    expect(find.text('Unbenannte Gesichter (3)'), findsOneWidget);
    // „Personen" und „Ignoriert" sind hier beide leer und stehen deshalb
    // ohne Zahl da.
    expect(find.text('Personen'), findsOneWidget);
    expect(find.text('Ignoriert'), findsOneWidget);
  });

  testWidgets('Löschen fragt vorher nach und tut ohne Zustimmung nichts',
      (tester) async {
    await zeige(tester);
    await rechtsklick(tester, find.byType(GridView).first);
    await tester.tap(find.text('Alle unbenannten Erkennungen löschen'));
    await tester.pumpAndSettle();

    expect(find.text('Erkennungen wirklich löschen?'), findsOneWidget);
    // Die Rückfrage muss sagen, dass Löschen NICHT dauerhaft ist – sonst
    // wählt man die schlechtere der beiden Möglichkeiten.
    expect(find.textContaining('nächste Gesichts-Scan findet dieselben Stellen'),
        findsOneWidget);

    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(await db.facesForAsset('a1'), hasLength(3),
        reason: 'Abbrechen darf nichts löschen');
  });

  testWidgets('nach der Zustimmung sind die Erkennungen weg', (tester) async {
    await zeige(tester);
    await rechtsklick(tester, find.byType(GridView).first);
    await tester.tap(find.text('Alle unbenannten Erkennungen löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();

    expect(await db.facesForAsset('a1'), isEmpty);
  });
}
