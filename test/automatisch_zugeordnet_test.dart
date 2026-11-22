import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/person_detail_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/automatisch_zugeordnet_marke.dart';
import 'package:photo_vault/widgets/gesichtsrahmen.dart';

/// **Automatisch zugeordnete Gesichter sind zu sehen (PER-074).**
///
/// Der Schalter „Sichere Vorschläge automatisch übernehmen“ verspricht eine
/// Kennzeichnung, damit sich solche Zuordnungen nachsehen lassen. Die
/// Wiedererkennung schrieb sie (`faces.automatischZugeordnet`), keine
/// Oberfläche las sie. Jetzt trägt ein solches Gesicht ein Zeichen;
/// bestätigen oder einer anderen Person zuordnen nimmt es weg.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState bibliothek;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_automatisch_');
    db = AppDatabase(NativeDatabase.memory());
    final pfade = await StoragePaths.forTesting(
      Directory(p.join(wurzel.path, 'lib')),
    );
    bibliothek = LibraryState()
      ..db = db
      ..paths = pfade
      ..backupService = BackupService(db, pfade);
    await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anna'));
    await db.createPerson(PeopleCompanion.insert(id: 'p2', name: 'Ben'));
    for (final id in ['a1', 'a2']) {
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.jpg',
              relativePath: 'originals/$id.jpg',
              checksum: 'pruef-$id',
              type: 'IMAGE',
              fileCreatedAt: DateTime(2026, 6, 14),
              importedAt: DateTime(2026),
            ),
          );
    }
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> gesicht(
    String id, {
    String asset = 'a1',
    String person = 'p1',
    bool automatisch = true,
  }) => db
      .into(db.faces)
      .insert(
        FacesCompanion.insert(
          id: id,
          assetId: asset,
          personId: Value(person),
          boxX: 0.2,
          boxY: 0.2,
          boxW: 0.5,
          boxH: 0.5,
          automatischZugeordnet: Value(automatisch),
        ),
      );

  Future<FaceData> lies(String id) =>
      (db.select(db.faces)..where((t) => t.id.equals(id))).getSingle();

  group('die Kennzeichnung', () {
    test('bestätigen – dieselbe Person noch einmal – nimmt sie weg', () async {
      await gesicht('f1');
      await db.fuehreAus(const GesichterZuordnen(['f1'], 'p1'));
      final f = await lies('f1');
      expect(f.personId, 'p1');
      expect(f.automatischZugeordnet, isFalse);
    });

    test('einer anderen Person zuordnen nimmt sie weg', () async {
      await gesicht('f1');
      await db.fuehreAus(const GesichterZuordnen(['f1'], 'p2'));
      expect((await lies('f1')).automatischZugeordnet, isFalse);
    });

    test('die Zuordnung lösen nimmt sie weg', () async {
      await gesicht('f1');
      await db.fuehreAus(const ZuordnungLoesen('f1'));
      final f = await lies('f1');
      expect(f.personId, isNull);
      expect(f.automatischZugeordnet, isFalse);
    });

    test('die Personenseite erfährt, welche Fotos sie tragen', () async {
      await gesicht('f1');
      await gesicht('f2', asset: 'a2', automatisch: false);
      await gesicht('f3', person: 'p2');
      expect(await db.watchAutomatischZugeordnete('p1').first, {
        'a1': ['f1'],
      });
    });
  });

  group('der Gesichtsrahmen', () {
    Future<void> zeige(
      WidgetTester tester,
      FaceData g, {
      VoidCallback? beiTipp,
      VoidCallback? beiBestaetigen,
    }) => tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: Stack(
              children: [
                Gesichtsrahmen(
                  gesicht: g,
                  personName: 'Anna',
                  flaeche: const Size(400, 400),
                  beiTipp: beiTipp,
                  beiBestaetigen: beiBestaetigen,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    testWidgets('trägt das Zeichen; ein Tipp darauf bestätigt nur', (
      tester,
    ) async {
      await tester.runAsync(() => gesicht('f1'));
      final g = await tester.runAsync(() => lies('f1'));
      var getippt = 0, bestaetigt = 0;
      await zeige(
        tester,
        g!,
        beiTipp: () => getippt++,
        beiBestaetigen: () => bestaetigt++,
      );
      final zeichen = find.byType(AutomatischZugeordnetMarke);
      expect(zeichen, findsOneWidget);
      expect(
        find.byTooltip('Automatisch zugeordnet – zum Bestätigen antippen'),
        findsOneWidget,
      );
      await tester.tap(zeichen);
      await tester.pump();
      expect((getippt, bestaetigt), (0, 1));
      // Der Rahmen selbst bleibt, was er war.
      await tester.tapAt(tester.getCenter(find.byType(Gesichtsrahmen)));
      await tester.pump();
      expect((getippt, bestaetigt), (1, 1));
    });

    testWidgets('ein von Hand zugeordnetes Gesicht trägt keins', (
      tester,
    ) async {
      await tester.runAsync(() => gesicht('f1', automatisch: false));
      final g = await tester.runAsync(() => lies('f1'));
      await zeige(tester, g!);
      expect(find.byType(AutomatischZugeordnetMarke), findsNothing);
    });
  });

  testWidgets('die Personenseite zeigt das Zeichen am Foto, bis es bestätigt '
      'ist', (tester) async {
    await tester.runAsync(() async {
      await gesicht('f1');
      await gesicht('f2', asset: 'a2', automatisch: false);
    });
    final person = await tester.runAsync(
      () => (db.select(db.people)..where((t) => t.id.equals('p1'))).getSingle(),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: PersonDetailScreen(library: bibliothek, person: person!),
      ),
    );
    Future<void> warte() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    melde.verlaufLeeren();
    await warte();
    // Zwei Fotos, nur eines mit automatisch zugeordnetem Gesicht.
    expect(find.byType(AutomatischZugeordnetMarke), findsOneWidget);

    await tester.tap(find.byType(AutomatischZugeordnetMarke));
    await warte();
    expect(
      (await tester.runAsync(() => lies('f1')))!.automatischZugeordnet,
      isFalse,
    );
    expect(find.byType(AutomatischZugeordnetMarke), findsNothing);
    expect(melde.verlauf.first.text, 'Zuordnung bestätigt.');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
