import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
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

/// Hält jede Abfrage an, deren Argumente eines der Wörter enthalten, bis
/// dessen Sperre gelöst ist – so wird eine Suche gezielt langsam.
class _Bremse extends QueryInterceptor {
  final sperren = <String, Completer<void>>{};

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    for (final MapEntry(key: wort, value: sperre) in sperren.entries) {
      if (args.any((a) => '$a'.contains(wort))) await sperre.future;
    }
    return executor.runSelect(statement, args);
  }
}

/// #433: Eine neue Suche konnte beginnen, während die vorige noch lief
/// (Enter, gespeicherte Suche, Optionen-Fenster). Wer zuletzt fertig
/// wurde, schrieb seine Treffer – auch der überholte Lauf.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;
  late _Bremse bremse;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_suchlauf_');
    bremse = _Bremse();
    db = AppDatabase(NativeDatabase.memory().interceptWith(bremse));
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'lib')),
      );
    for (final (id, name) in [
      ('l1', 'langsam_1.jpg'),
      ('s1', 'schnell_1.jpg'),
      ('z1', 'zaeh_1.jpg'),
    ]) {
      await db.insertAsset(
        AssetsCompanion.insert(
          id: id,
          relativePath: 'originals/$name',
          originalFileName: name,
          type: 'IMAGE',
          checksum: id,
          fileCreatedAt: DateTime(2024, 7, 1),
          importedAt: DateTime(2024, 7, 10),
        ),
      );
    }
  });

  tearDown(() async {
    for (final sperre in bremse.sperren.values) {
      if (!sperre.isCompleted) sperre.complete();
    }
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> zeige(WidgetTester tester) async {
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
              query: 'langsam',
              textMode: SearchTextMode.filename,
            ),
          ),
        ),
      ),
    );
    // Kein pumpAndSettle: Der Bildschirm hängt an drift-Strömen.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  List<String> treffer(WidgetTester tester) => [
    for (final a
        in (tester.state(find.byType(SearchScreen))
                as Rasterbedienung<SearchScreen, AssetData>)
            .rasterAssets)
      a.id,
  ];

  /// Eine zweite Suche über Enter, während die erste noch läuft.
  Future<void> sucheMitEnter(WidgetTester tester, String wort) async {
    await tester.enterText(find.byType(TextField).first, wort);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> ende(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('ein überholter langsamer Lauf überschreibt die Treffer nicht', (
    tester,
  ) async {
    final langsam = bremse.sperren['langsam'] = Completer<void>();
    await zeige(tester);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await sucheMitEnter(tester, 'schnell');
    expect(treffer(tester), ['s1']);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    langsam.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(treffer(tester), ['s1'], reason: 'die jüngere Suche gilt');
    await ende(tester);
  });

  testWidgets('endet der überholte Lauf zuerst, bleibt die Ladeanzeige', (
    tester,
  ) async {
    final langsam = bremse.sperren['langsam'] = Completer<void>();
    final zaeh = bremse.sperren['zaeh'] = Completer<void>();
    await zeige(tester);
    await sucheMitEnter(tester, 'zaeh');

    langsam.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(treffer(tester), isNot(contains('l1')));
    expect(
      find.byType(LinearProgressIndicator),
      findsOneWidget,
      reason: 'die jüngere Suche läuft noch',
    );

    zaeh.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(treffer(tester), ['z1']);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await ende(tester);
  });

  testWidgets('das Aussortieren gelöschter Treffer überschreibt keine neue '
      'Suche', (tester) async {
    await zeige(tester);
    await sucheMitEnter(tester, 'schnell');
    expect(treffer(tester), ['s1']);

    // Gelöscht wie von einem anderen Gerät; das Aussortieren hängt.
    await tester.runAsync(() => db.fuehreAus(InDenPapierkorb(['s1'])));
    final aussortieren = bremse.sperren['s1'] = Completer<void>();
    await tester.pump(const Duration(milliseconds: 500));

    await sucheMitEnter(tester, 'zaeh');
    expect(treffer(tester), ['z1']);
    aussortieren.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(treffer(tester), ['z1']);
    await ende(tester);
  });
}
