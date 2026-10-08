import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/stammbaum.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/familientage_abschnitt.dart';

/// Der Abschnitt „Familientage" in Entdecken – die Verdrahtung mit der
/// Datenbank. Die Regeln stehen in familientage_test.dart.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;
  final heute = DateTime(2026, 10, 8);

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_familientage_');
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

  Future<void> person(
    String id,
    String name, {
    DateTime? geburt,
    DateTime? tod,
  }) => db.createPerson(
    PeopleCompanion.insert(
      id: id,
      name: name,
      geburtsdatum: Value(geburt),
      sterbedatum: Value(tod),
    ),
  );

  Future<void> zeige(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: FamilientageAbschnitt(library: library, heute: heute),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Geburtstag, Gedenktag und Hochzeitstag stehen da', (
    tester,
  ) async {
    await person('anna', 'Anna', geburt: DateTime(1990, 10, 8));
    await person(
      'oma',
      'Oma Rosa',
      geburt: DateTime(1926, 10, 10),
      tod: DateTime(2010, 3, 1),
    );
    await person('paul', 'Paul');
    await person('klara', 'Klara');
    await db.fuegeBeziehungHinzu('paul', 'klara', Verwandtschaft.partner);
    await db.fuegeEreignisHinzu(
      LebensereignisseCompanion.insert(
        id: 'h1',
        personId: 'paul',
        art: 'hochzeit',
        datum: Value(DateTime(2001, 10, 12)),
      ),
    );
    await zeige(tester);

    expect(find.text('Familientage'), findsOneWidget);
    expect(find.text('Heute · Anna wird 36'), findsOneWidget);
    expect(
      find.text('In 2 Tagen · Oma Rosa wäre 100 geworden'),
      findsOneWidget,
    );
    expect(
      find.text('In 4 Tagen · 25. Hochzeitstag von Paul & Klara'),
      findsOneWidget,
    );
  });

  testWidgets('ohne Familientag bleibt der Abschnitt ganz weg', (tester) async {
    await person('anna', 'Anna', geburt: DateTime(1990, 5, 1));
    await zeige(tester);
    expect(find.text('Familientage'), findsNothing);
  });
}
