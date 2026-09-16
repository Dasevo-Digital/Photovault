import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/lebenslauf_screen.dart';
import 'package:photo_vault/screens/person_detail_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// Die Wege, die von einer Person wegführen.
///
/// **Der Fund der 18. Prüfrunde.** Den Lebenslauf einer Person gab es nur
/// an einer Stelle: im Menü ihres Schildes im Stammbaum. Wer eine Person
/// aufschlug, um etwas über sie zu erfahren, fand ihn dort nicht – und
/// auf die Idee, ihn im Stammbaum zu suchen, kommt man erst, wenn man
/// weiss, dass es ihn gibt. Dieselbe Krankheit wie beim Papierkorb ohne
/// Eingang und bei der Gesichts-Bearbeitung im Rechtsklick-Menü.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState bib;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_tueren_');
    db = AppDatabase(NativeDatabase.memory());
    final pfade =
        await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')));
    bib = LibraryState()
      ..db = db
      ..paths = pfade
      ..backupService = BackupService(db, pfade);
    await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anna'));
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> zeige(WidgetTester tester) async {
    final person =
        await (db.select(db.people)..where((t) => t.id.equals('p1'))).getSingle();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: PersonDetailScreen(library: bib, person: person),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Baut den Baum ab und lässt den Strom auslaufen – ein drift-Strom im
  /// Widget hinterlässt sonst einen Zeitgeber, und flutter_test meldet
  /// einen hängenden Timer.
  Future<void> raeumeAb(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('von der Person führt ein Weg zum Lebenslauf', (tester) async {
    await zeige(tester);
    final knopf = find.byTooltip('Lebenslauf: Anna');
    expect(knopf, findsOneWidget,
        reason: 'ein sichtbarer Knopf, kein verborgenes Menü');

    await tester.tap(knopf);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(LebenslaufScreen), findsOneWidget);
    await raeumeAb(tester);
  });

  testWidgets('und einer in den Stammbaum', (tester) async {
    // Der war schon da; er steht hier, damit ein Umbau der Leiste nicht
    // aus Versehen den einen gegen den anderen tauscht.
    await zeige(tester);
    expect(find.byIcon(Icons.account_tree_outlined), findsOneWidget);
    await raeumeAb(tester);
  });
}
