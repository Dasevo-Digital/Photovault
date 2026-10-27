import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/search_filters.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/search_screen.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/rasterbedienung.dart';

/// Gelöschte Fotos verschwinden aus den Treffern (#235).
///
/// Die Suche selbst lässt den Papierkorb aus – aber die Trefferliste war
/// eine gehaltene Liste: Wer ein gefundenes Foto löschte, sah es weiter,
/// bis er neu suchte. Gemeldet als „wird der Papierkorb mit durchsucht?".
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_suche_geloescht_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'lib')),
      );
    for (final (id, tag) in [('u1', 1), ('u2', 2), ('u3', 3)]) {
      await db.insertAsset(
        AssetsCompanion.insert(
          id: id,
          relativePath: 'originals/$id.jpg',
          originalFileName: 'urlaub_$id.jpg',
          type: 'IMAGE',
          checksum: id,
          fileCreatedAt: DateTime(2024, 7, tag),
          importedAt: DateTime(2024, 7, 10),
        ),
      );
    }
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  test(
    'nochSuchbar lässt Papierkorb und Gesperrtes weg, in Reihenfolge',
    () async {
      await db.fuehreAus(const InDenPapierkorb(['u2']));
      await (db.update(db.assets)..where((t) => t.id.equals('u1'))).write(
        const AssetsCompanion(isLocked: Value(true)),
      );
      expect(await db.nochSuchbar(['u3', 'u2', 'u1', 'gibtsnicht']), ['u3']);
      expect(await db.nochSuchbar(const []), isEmpty);
    },
  );

  testWidgets('ein gelöschter Treffer fällt aus der Liste', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: SearchScreen(
            library: library,
            startFilter: const SearchFilters(
              query: 'urlaub',
              textMode: SearchTextMode.filename,
            ),
          ),
        ),
      ),
    );
    // Kein pumpAndSettle: Der Bildschirm hängt an drift-Strömen, die nie
    // zur Ruhe kommen (siehe suchsatz_test.dart).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    List<String> treffer() => [
      for (final a
          in (tester.state(find.byType(SearchScreen))
                  as Rasterbedienung<SearchScreen, AssetData>)
              .rasterAssets)
        a.id,
    ];
    expect(treffer(), ['u3', 'u2', 'u1']);

    // Gelöscht wie aus dem Betrachter oder von einem anderen Gerät.
    await tester.runAsync(() => db.fuehreAus(const InDenPapierkorb(['u2'])));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 100));
    expect(treffer(), ['u3', 'u1']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
