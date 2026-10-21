import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/aufnahmedaten_screen.dart';
import 'package:photo_vault/state/library_state.dart';

/// „Aufnahmedaten aus dem Dateinamen“ am Rechner (#203): dieselbe Liste wie
/// im Browser und auf dem Telefon, wählen und übernehmen.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_aufnahmedaten_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'lib')),
      );
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> aufnahme(String id, String name, {bool geschaetzt = true}) => db
      .into(db.assets)
      .insert(
        AssetsCompanion.insert(
          id: id,
          originalFileName: name,
          relativePath: 'originals/$id.jpg',
          checksum: 'pruef-$id',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2025, 8, 1, 9, 0, 20),
          importedAt: DateTime(2025, 8, 21),
          datumGeschaetzt: Value(geschaetzt),
          datumGeprueft: const Value(true),
        ),
      );

  testWidgets('wählen und übernehmen', (tester) async {
    await tester.runAsync(() async {
      await aufnahme('mit', '22-06-18 16-20-30 c3d4.jpg');
      await aufnahme('tag', 'IMG-20180517-WA0003.jpg');
      await aufnahme('ohne', 'IMG_0042.JPG');
      // Nicht geschätzt, aber die Datei fehlt: kein Vorschlag, kein Fehler.
      await aufnahme('fehlt', '25-02-03 11-22-33 2002.MOV', geschaetzt: false);
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: AufnahmedatenScreen(library: library),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(AufnahmedatenScreen)));
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    expect(find.textContaining(t.aufnahmedatenNurTag), findsOneWidget);

    // Den Tag abwählen (er steht als älterer unten), den anderen übernehmen.
    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.aufnahmedatenUebernehmen(1)));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    final mit = await tester.runAsync(() => db.assetById('mit'));
    expect(mit!.fileCreatedAt, DateTime(2022, 6, 18, 16, 20, 30));
    expect(mit.datumGeschaetzt, isFalse);
    final tag = await tester.runAsync(() => db.assetById('tag'));
    expect(tag!.fileCreatedAt, DateTime(2025, 8, 1, 9, 0, 20));
    expect(find.byType(CheckboxListTile), findsOneWidget);
  });
}
