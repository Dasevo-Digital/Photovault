import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/soziogramm_screen.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// Das Soziogramm am Bildschirm: Verbindungen aus der Datenbank, und ein
/// Tipp auf eine Person zeigt ihre.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_sozio_');
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

  Future<void> foto(String id, List<String> personen) async {
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'pruef-$id',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026),
            importedAt: DateTime(2026),
          ),
        );
    for (final (i, person) in personen.indexed) {
      await db
          .into(db.faces)
          .insert(
            FacesCompanion.insert(
              id: '$id-$i',
              assetId: id,
              personId: Value(person),
              boxX: 0,
              boxY: 0,
              boxW: 1,
              boxH: 1,
            ),
          );
    }
  }

  testWidgets('die engsten Verbindungen und die einer Person', (tester) async {
    for (final (id, name) in [('a', 'Anna'), ('b', 'Bernd'), ('c', 'Clara')]) {
      await db.createPerson(PeopleCompanion.insert(id: id, name: name));
    }
    for (var i = 0; i < 3; i++) {
      await foto('ab$i', ['a', 'b']);
    }
    for (var i = 0; i < 2; i++) {
      await foto('bc$i', ['b', 'c']);
    }
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: SoziogrammScreen(library: library),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Die engsten Verbindungen'), findsOneWidget);
    expect(find.text('Anna & Bernd'), findsOneWidget);
    expect(find.text('3 Fotos'), findsOneWidget);
    expect(find.text('Bernd & Clara'), findsOneWidget);

    await tester.tap(find.text('Clara'));
    await tester.pumpAndSettle();
    expect(find.text('Mit Clara auf Fotos'), findsOneWidget);
    expect(find.text('Anna & Bernd'), findsNothing);
    expect(find.text('2 Fotos'), findsOneWidget);
  });
}
