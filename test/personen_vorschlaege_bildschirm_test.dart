import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/person_suggestions_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// Die Bestätigungsansicht für Vorschläge.
///
/// Der leicht zu übersehende Teil ist nicht das Zuordnen, sondern das
/// Lernen: Abgewählte Vorschläge müssen als Ablehnung festgehalten werden.
/// Ohne sie bliebe die persönliche Schwelle stehen und derselbe Fehlgriff
/// käme beim nächsten Lauf wieder.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_vorschlag_');
    db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
    library = LibraryState()
      ..db = db
      ..paths = paths
      ..backupService = BackupService(db, paths);

    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: 'a1',
          originalFileName: 'a1.jpg',
          relativePath: 'originals/a1.jpg',
          checksum: 'c1',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2026, 1, 1),
          importedAt: DateTime(2026, 1, 1),
        ));
    await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anna'));
    for (var i = 0; i < 3; i++) {
      await db.insertFace(FacesCompanion.insert(
        id: 'f$i',
        assetId: 'a1',
        boxX: 0.1 * i,
        boxY: 0.1,
        boxW: 0.2,
        boxH: 0.2,
        cropRelativePath: Value('faces/f$i.jpg'),
      ));
    }
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<PersonData> person() =>
      (db.select(db.people)..where((t) => t.id.equals('p1'))).getSingle();

  Future<void> zeige(WidgetTester tester) async {
    final faces = await db.facesForAsset('a1');
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: PersonSuggestionsScreen(
        library: library,
        person: await person(),
        vorschlaege: [
          (gesicht: faces[0], aehnlichkeit: 0.91),
          (gesicht: faces[1], aehnlichkeit: 0.75),
          (gesicht: faces[2], aehnlichkeit: 0.62),
        ],
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('alles ist vorausgewählt und der Knopf nennt die Zahl',
      (tester) async {
    await zeige(tester);
    expect(find.text('3 Gesichter zuordnen'), findsOneWidget);
  });

  testWidgets('die Ähnlichkeit steht an jeder Kachel', (tester) async {
    // Bei einem knappen Wert lohnt das genaue Hinsehen, bei einem hohen
    // genügt der Blick.
    await zeige(tester);
    expect(find.text('0.91'), findsOneWidget);
    expect(find.text('0.62'), findsOneWidget);
  });

  testWidgets('nur Ausgewähltes wird zugeordnet', (tester) async {
    await zeige(tester);
    // Auf die Ähnlichkeitszahl tippen – nach Position, nicht nach Widget:
    // Die Zahl reicht den Klick bewusst an die Kachel darunter durch, und
    // genau das wird hier mitgeprüft.
    await tester.tapAt(tester.getCenter(find.text('0.62')));
    await tester.pumpAndSettle();
    expect(find.text('2 Gesichter zuordnen'), findsOneWidget);

    await tester.tap(find.text('2 Gesichter zuordnen'));
    await tester.pumpAndSettle();

    final zugeordnet = (await db.facesForPerson('p1')).map((f) => f.id).toSet();
    expect(zugeordnet, {'f0', 'f1'});
  });

  testWidgets('auch die Ablehnung wird festgehalten und verschiebt die Schwelle',
      (tester) async {
    // Der eigentliche Punkt. Ohne den abgelehnten Eintrag bliebe die
    // Schwelle stehen und der Fehlgriff käme wieder.
    expect((await person()).similarityThreshold, isNull);

    await zeige(tester);
    await tester.tapAt(tester.getCenter(find.text('0.62')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 Gesichter zuordnen'));
    await tester.pumpAndSettle();

    final rueckmeldungen = await db.gesichtsRueckmeldungen('p1');
    expect(rueckmeldungen, hasLength(3),
        reason: 'alle drei Entscheidungen zählen, nicht nur die zwei Ja');
    expect((await person()).similarityThreshold, isNotNull);
  });

  testWidgets('auch ohne eine einzige Zuordnung wird gelernt', (tester) async {
    await zeige(tester);
    await tester.tap(find.text('Keine wählen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nichts ausgewählt'));
    await tester.pumpAndSettle();

    expect(await db.facesForPerson('p1'), isEmpty);
    expect(await db.gesichtsRueckmeldungen('p1'), hasLength(3),
        reason: 'drei Ablehnungen sind eine Aussage');
  });
}
