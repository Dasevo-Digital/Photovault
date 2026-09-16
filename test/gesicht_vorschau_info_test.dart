import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/face_review_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:provider/provider.dart';

/// Info-Ansicht und Foto löschen in der Gesichts-Vollbildansicht.
///
/// Beides fehlte dort. Wer aus „Personen" ein Foto öffnete, sah die
/// Gesichter, aber weder Aufnahmedatum noch Kamera noch Ort – und ein
/// Foto, das offensichtlich nichts taugt, liess sich von dort nicht
/// wegräumen, sondern nur in der Zeitleiste wiederfinden.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late LibraryState library;
  late List<AssetData> assets;

  /// Ein winziges, gültiges PNG – ohne echte Datei meldet `Image.file`
  /// einen Ladefehler, und der zählt im Test als Ausnahme.
  final einPixel = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_vorschau_info_');
    db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
    library = LibraryState()
      ..db = db
      ..paths = paths
      ..backupService = BackupService(db, paths);

    for (final id in ['a1', 'a2']) {
      final datei = paths.absolute('originals/$id.jpg');
      datei.parent.createSync(recursive: true);
      datei.writeAsBytesSync(einPixel);
      await db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'c_$id',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 3, 4),
            importedAt: DateTime(2026, 3, 4),
            // Gesetzt, damit das Seitenverhältnis nicht aus der Datei
            // gelesen werden muss.
            widthPx: const Value(1000),
            heightPx: const Value(800),
          ));
    }
    await db.insertFace(FacesCompanion.insert(
      id: 'f1',
      assetId: 'a1',
      boxX: 0.1,
      boxY: 0.1,
      boxW: 0.3,
      boxH: 0.3,
      cropRelativePath: const Value('faces/f1.jpg'),
    ));
    assets = await db.assetsByIds(['a1', 'a2']);
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<void> zeige(WidgetTester tester) async {
    await tester.pumpWidget(ChangeNotifierProvider<LibraryState>.value(
      value: library,
      child: MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: FaceReviewScreen(library: library, assets: assets),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Wartet, bis [pruefung] zutrifft – für Schritte mit echtem Datei-I/O.
  /// `pumpAndSettle` pumpt Bilder, keine Dateisystem-Aufrufe.
  Future<void> bisDann(WidgetTester tester, bool Function() pruefung) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && !pruefung(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
  }

  testWidgets('die Info-Ansicht lässt sich öffnen und zeigt die Metadaten',
      (tester) async {
    await zeige(tester);
    expect(find.text('Info'), findsNothing, reason: 'anfangs zugeklappt');

    await tester.tap(find.byTooltip('Info'));
    await tester.pumpAndSettle();

    expect(find.text('Info'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    // Der Dateiname steht in den Details – der Beleg, dass die Ansicht das
    // richtige Foto zeigt und nicht ein leeres Gerüst.
    expect(find.text('a1.jpg'), findsWidgets);
  });

  testWidgets('die Info-Ansicht folgt beim Weiterblättern', (tester) async {
    await zeige(tester);
    await tester.tap(find.byTooltip('Info'));
    await tester.pumpAndSettle();
    expect(find.text('a1.jpg'), findsWidgets);

    await tester.tap(find.byTooltip('Nächstes Foto (Pfeil rechts)'));
    await tester.pumpAndSettle();

    expect(find.text('a2.jpg'), findsWidgets);
    expect(find.text('a1.jpg'), findsNothing);
  });

  testWidgets('Foto löschen fragt vorher nach und tut ohne Zustimmung nichts',
      (tester) async {
    await zeige(tester);
    await tester.tap(find.byTooltip('Foto löschen'));
    await tester.pumpAndSettle();

    expect(find.text('Foto löschen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    expect((await db.assetById('a1'))!.isTrashed, isFalse);
  });

  testWidgets('nach der Zustimmung wandert das Foto in den Papierkorb und '
      'die Reihe blättert weiter', (tester) async {
    await zeige(tester);
    expect(find.text('a1.jpg'), findsOneWidget, reason: 'im Titel');

    await tester.tap(find.byTooltip('Foto löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();
    await bisDann(tester, () => true);
    await tester.pumpAndSettle();

    expect((await db.assetById('a1'))!.isTrashed, isTrue);
    // Nicht geschlossen, sondern weitergeblättert: Wer aussortiert, will
    // an derselben Stelle weitermachen.
    expect(find.byType(FaceReviewScreen), findsOneWidget);
    expect(find.text('a2.jpg'), findsOneWidget);
  });
}
