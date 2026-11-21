import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/search_filters.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/l10n/app_localizations_de.dart';
import 'package:photo_vault/screens/search_screen.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/search_options_sheet.dart';

/// **„Deutung zurücknehmen“ stellt den Satz wieder her.**
///
/// Zurück ins Feld kamen nur die erkannten Teile („2023 5 Sternen“), der
/// unerkannte Rest fehlte, und ein vorher von Hand gesetzter Filter ging
/// mit verloren.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;
  final de = AppTexteDe();

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_satz_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'l')),
      );
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> warte(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('der ganze Satz kommt zurück, der Favoritenfilter bleibt', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: Scaffold(
          body: SearchScreen(
            library: library,
            startFilter: const SearchFilters(favoritesOnly: true),
          ),
        ),
      ),
    );
    await warte(tester);

    const satz = 'Strand 2023 mit 5 Sternen';
    final feld = find.byType(TextField).first;
    await tester.enterText(feld, satz);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await warte(tester);
    expect(find.byTooltip(de.sucheSatzVerwerfen), findsOneWidget);

    await tester.tap(find.byTooltip(de.sucheSatzVerwerfen));
    await warte(tester);
    expect(find.byTooltip(de.sucheSatzVerwerfen), findsNothing);
    expect(tester.widget<TextField>(feld).controller!.text, satz);

    // Der Filter steht noch – zu sehen im Optionen-Blatt.
    await tester.tap(find.byTooltip(de.sucheOptionen).first);
    await warte(tester);
    final blatt = tester.widget<SearchOptionsSheet>(
      find.byType(SearchOptionsSheet),
    );
    expect(blatt.initialFilters.favoritesOnly, isTrue);
    expect(blatt.initialFilters.query, satz);
    expect(blatt.initialFilters.minRating, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });
}
