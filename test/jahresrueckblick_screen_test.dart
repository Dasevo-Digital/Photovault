import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/jahresrueckblick_screen.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// Der Jahresrückblick am Bildschirm: Zahlen, Personen, Jahreswechsel.
/// Die Auswahlregeln stehen in jahresrueckblick_test.dart.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUpAll(() async => initializeDateFormatting());

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_jahr_');
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

  Future<void> aufnahme(String id, DateTime wann, {String? land}) => db
      .into(db.assets)
      .insert(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'pruef-$id',
          type: 'IMAGE',
          fileCreatedAt: wann,
          importedAt: DateTime(2026),
          locationCountry: Value(land),
        ),
      );

  testWidgets('Zahlen des Jahres, Personen, und der Wechsel ins Vorjahr', (
    tester,
  ) async {
    await aufnahme('a', DateTime(2025, 3, 1), land: 'DE');
    await aufnahme('b', DateTime(2025, 3, 2), land: 'IT');
    await aufnahme('c', DateTime(2025, 9, 9), land: 'DE');
    await aufnahme('alt', DateTime(2024, 5, 5));
    await db.createPerson(PeopleCompanion.insert(id: 'anna', name: 'Anna'));
    for (final (id, asset) in [('f1', 'a'), ('f2', 'b'), ('f3', 'alt')]) {
      await db
          .into(db.faces)
          .insert(
            FacesCompanion.insert(
              id: id,
              assetId: asset,
              personId: const Value('anna'),
              boxX: 0,
              boxY: 0,
              boxW: 1,
              boxH: 1,
            ),
          );
    }

    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: JahresrueckblickScreen(library: library, jahr: 2025),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text('Dein Jahr 2025'), findsOneWidget);
    expect(find.text('Tage mit Fotos'), findsOneWidget);
    // Drei Fotos, drei Tage, zwei Länder – die 3 steht zweimal da.
    expect(find.text('3'), findsNWidgets(2));
    expect(find.text('2'), findsOneWidget);
    expect(find.text('März'), findsOneWidget);
    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('2 Aufnahmen'), findsOneWidget);

    await tester.tap(find.byTooltip('Vorjahr'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('Dein Jahr 2024'), findsOneWidget);
    expect(find.text('1 Aufnahme'), findsOneWidget);
  });

  test('bis Februar das vergangene Jahr, danach das laufende', () {
    expect(jahresrueckblickJahr(DateTime(2026, 2, 28)), 2025);
    expect(jahresrueckblickJahr(DateTime(2026, 3, 1)), 2026);
  });
}
