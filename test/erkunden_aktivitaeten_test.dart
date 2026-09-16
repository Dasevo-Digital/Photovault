import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/aktivitaet_detail_screen.dart';
import 'package:photo_vault/screens/explore_screen.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// **Aktivitäten stehen im Erkunden unter den Reisen.**
///
/// Sie sind dieselbe Frage eine Ebene kleiner: Eine Reise ist der
/// Urlaub, eine Aktivität der Tag darin. Bis dahin gab es sie im
/// Erkunden gar nicht – man musste wissen, dass es sie gibt, um sie zu
/// finden.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_erk_akt_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths =
          await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')));
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> aktivitaet(String id, String name, String art,
          DateTime wann) =>
      db.aktivitaetAnlegen(
        AktivitaetenCompanion.insert(
          id: id,
          name: name,
          art: art,
          von: wann,
          bis: wann.add(const Duration(hours: 3)),
          angelegtAm: DateTime(2026, 9),
        ),
        const [],
      );

  Future<void> zeige(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: Scaffold(body: ExploreScreen(library: library)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Der Bildschirm baut Karten und Bilder auf, die hier weder da noch
  /// nötig sind – abbauen, damit keine Zeitgeber offen bleiben.
  Future<void> abbauen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('der Abschnitt steht da und trägt die Aktivitäten',
      (tester) async {
    await aktivitaet('a1', 'Wanderung Feldberg', 'wanderung',
        DateTime(2026, 7, 12, 9));
    await aktivitaet('a2', 'Radtour am See', 'radtour', DateTime(2026, 6, 3, 8));
    await zeige(tester);

    expect(find.text('Aktivitäten'), findsOneWidget);
    expect(find.text('Wanderung Feldberg'), findsOneWidget);
    expect(find.text('Radtour am See'), findsOneWidget);
    await abbauen(tester);
  });

  testWidgets('er steht UNTER den Reisen', (tester) async {
    // Die Reihenfolge ist die Aussage: vom Groben zum Feinen. Damit die
    // Reisen ueberhaupt dastehen, muss es eine geben – ein leerer
    // Abschnitt wird seit der Aufraeumrunde ausgeblendet.
    await db.reiseAnlegen(
      ReisenCompanion.insert(
        id: 'r1',
        name: 'Lissabon',
        von: DateTime(2026, 6, 1),
        bis: DateTime(2026, 6, 8),
        angelegtAm: DateTime(2026, 9),
      ),
      const [],
    );
    await aktivitaet('a1', 'Wanderung', 'wanderung', DateTime(2026, 7, 12, 9));
    await zeige(tester);

    final reisen = tester.getRect(find.text('Reisen'));
    final akt = tester.getRect(find.text('Aktivitäten'));
    expect(akt.top, greaterThan(reisen.top));
    await abbauen(tester);
  });

  testWidgets('ohne Aktivität steht der Abschnitt gar nicht da',
      (tester) async {
    // **Die Regel hat sich geaendert.** Vorher stand unter der
    // Ueberschrift ein Satz („Noch keine Aktivität") und daneben ein
    // Knopf „Alle anzeigen", der in eine leere Liste fuehrte. Fuenf
    // solche Abschnitte untereinander sind eine Seite, die von sich
    // selbst handelt.
    await zeige(tester);
    expect(find.text('Aktivitäten'), findsNothing);
    expect(find.textContaining('Noch keine Aktivität'), findsNothing);
    await abbauen(tester);
  });

  testWidgets('eine Kachel führt in die Aktivität', (tester) async {
    await aktivitaet('a1', 'Wanderung Feldberg', 'wanderung',
        DateTime(2026, 7, 12, 9));
    await zeige(tester);

    await tester.tap(find.text('Wanderung Feldberg'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AktivitaetDetailScreen), findsOneWidget);
    await abbauen(tester);
  });

  testWidgets('die jüngste steht vorn', (tester) async {
    await aktivitaet('alt', 'Alte Tour', 'wanderung', DateTime(2024, 1, 5, 9));
    await aktivitaet('neu', 'Neue Tour', 'radtour', DateTime(2026, 8, 1, 9));
    await zeige(tester);

    expect(tester.getRect(find.text('Neue Tour')).left,
        lessThan(tester.getRect(find.text('Alte Tour')).left));
    await abbauen(tester);
  });
}
