import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/reverse_geocoder.dart';
import 'package:kern/services/search_filters.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/l10n/app_localizations_de.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/search_options_sheet.dart';

/// **Land, Bundesland, Stadt in den Suchoptionen.**
///
/// Die Stadt liess sich erst nach dem Bundesland wählen, und der Hinweis
/// „Noch keine Orte aufgelöst“ hing am geladenen Datensatz statt an den
/// aufgelösten Orten.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;
  final de = AppTexteDe();

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_suchorte_');
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

  Future<void> foto(String id, {String? land, String? region, String? stadt}) =>
      db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.jpg',
              relativePath: 'o/$id.jpg',
              checksum: 'c$id',
              type: 'IMAGE',
              fileCreatedAt: DateTime(2025),
              importedAt: DateTime(2025),
              locationCountry: Value(land),
              locationState: Value(region),
              locationCity: Value(stadt),
            ),
          );

  Future<void> zeige(WidgetTester tester, SearchFilters filter) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: Scaffold(
          body: SearchOptionsSheet(library: library, initialFilters: filter),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  Future<void> abbauen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  DropdownButtonFormField<String?> auswahl(WidgetTester tester, String name) =>
      tester.widget<DropdownButtonFormField<String?>>(
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String?> &&
              w.decoration.labelText == name,
        ),
      );

  testWidgets('nach der Landeswahl stehen die Städte des Landes zur Wahl', (
    tester,
  ) async {
    await foto('a', land: 'France', region: 'Nord', stadt: 'Nordstadt');
    await foto('b', land: 'France', region: 'Sued', stadt: 'Suedstadt');
    await foto('c', land: 'Italy', region: 'Ovest', stadt: 'Weststadt');
    await zeige(tester, const SearchFilters(locationCountry: 'France'));

    final stadt = auswahl(tester, de.suchoptStadt);
    expect(stadt.onChanged, isNotNull, reason: 'ohne Bundesland wählbar');
    // Geschlossen baut das Feld nur den gewählten Eintrag; die Liste
    // steht im inneren DropdownButton.
    final knopf = tester.widget<DropdownButton<String?>>(
      find.descendant(
        of: find.byWidget(stadt),
        matching: find.byType(DropdownButton<String?>),
      ),
    );
    final werte = [for (final e in knopf.items!) e.value];
    expect(werte, [null, 'Nordstadt', 'Suedstadt']);
    // Mit aufgelösten Orten und ohne Datensatz: kein Hinweis.
    expect(library.geoDataAvailable, isFalse);
    expect(find.text(de.suchoptGeoFehlt), findsNothing);
    await abbauen(tester);
  });

  testWidgets('ohne aufgelöste Orte steht der Hinweis da – auch mit '
      'geladenem Datensatz', (tester) async {
    await foto('x');
    await tester.runAsync(() async {
      final orte = File(p.join(wurzel.path, 'cities1000.txt'))
        ..writeAsStringSync(
          '1\tGoslar\tGoslar\t\t51.90425\t10.42766\tP\tPPLA3\tDE\t\t06'
          '\t\t\t\t50753\t\t255\tEurope/Berlin\t2023\n',
        );
      final admin1 = File(p.join(wurzel.path, 'admin1.txt'))
        ..writeAsStringSync('DE.06\tNiedersachsen\tNiedersachsen\t1\n');
      final laender = File(p.join(wurzel.path, 'countryInfo.txt'))
        ..writeAsStringSync(
          'DE\tDEU\t276\tDE\tDeutschland\tBerlin\t357021\t82927922\tEU'
          '\t.de\tEUR\tEuro\t49\t\t\tde-DE\t2921044\t\t\n',
        );
      library.geocoder = await ReverseGeocoder.loadFromFiles(
        citiesFile: orte,
        admin1File: admin1,
        countryFile: laender,
      );
    });
    expect(library.geoDataAvailable, isTrue);
    await zeige(tester, const SearchFilters());
    expect(find.text(de.suchoptGeoFehlt), findsOneWidget);
    await abbauen(tester);
  });
}
