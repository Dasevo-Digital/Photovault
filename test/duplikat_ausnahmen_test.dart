import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/duplicates_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/clip_service.dart';
import 'package:photo_vault/services/embedding_similarity.dart';
import 'package:photo_vault/services/modell_halter.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/widgets/meldungsfenster.dart';

/// „Diese beiden sind schon in Ordnung so" – die Duplikatsuche zeigte
/// dieselbe Gruppe bisher bei jedem Aufruf wieder, ohne dass man sie hätte
/// abhaken können.
void main() {
  late Directory tempRoot;
  late AppDatabase db;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_dupl_');
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
    // Der Meldungsdienst ist ein Einzelstück: Was ein Test stehen lässt,
    // steht im nächsten noch da – samt laufender Uhr, über die der
    // Rahmen dann stolpert.
    melde.verlaufLeeren();
  });

  /// Zwei Vektoren, deren Kosinus-Ähnlichkeit über jeder sinnvollen Schwelle
  /// liegt, aber nicht identisch sind.
  Float32List vektor(double kippe) {
    final v = Float32List(512);
    v[0] = 1.0;
    v[1] = kippe;
    return v;
  }

  Future<void> lege(String id, Float32List v) async {
    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: id,
          fileCreatedAt: DateTime(2024, 5, 1),
          importedAt: DateTime(2024, 5, 2),
          type: 'IMAGE',
          thumbnailRelativePath: Value('thumbs/$id.jpg'),
        ));
    await db.saveEmbedding(id, v);
  }

  group('Gruppenbildung', () {
    test('ein ausgenommenes Paar wird nicht mehr zusammengefasst', () {
      final embeddings = {'a': vektor(0.01), 'b': vektor(0.02)};

      final ohne = findDuplicateGroups(DuplicateSearchParams(embeddings, 0.92));
      expect(ohne.single.toSet(), {'a', 'b'});

      final mit = findDuplicateGroups(DuplicateSearchParams(
        embeddings,
        0.92,
        ausnahmen: {duplikatPaarSchluessel('a', 'b')},
      ));
      expect(mit, isEmpty);
    });

    test('der Schlüssel gilt unabhängig von der Reihenfolge', () {
      // Zwei Fassungen desselben Formats wären genau die Art Fehler, die
      // sich nur als „die Ausnahme wirkt nicht" zeigt.
      expect(duplikatPaarSchluessel('b', 'a'), duplikatPaarSchluessel('a', 'b'));

      final embeddings = {'zebra': vektor(0.01), 'aal': vektor(0.02)};
      final mit = findDuplicateGroups(DuplicateSearchParams(
        embeddings,
        0.92,
        ausnahmen: {duplikatPaarSchluessel('zebra', 'aal')},
      ));
      expect(mit, isEmpty);
    });

    test('ein drittes, beiden ähnliches Foto hält die Gruppe zusammen', () {
      // Bekannte Grenze, bewusst so: C verbindet A und B, obwohl das Paar
      // A–B ausgenommen ist. Eine Gruppe aufzubrechen, weil eines ihrer
      // Paare ausgenommen ist, wäre die falschere Antwort.
      final embeddings = {'a': vektor(0.01), 'b': vektor(0.02), 'c': vektor(0.015)};
      final gruppen = findDuplicateGroups(DuplicateSearchParams(
        embeddings,
        0.92,
        ausnahmen: {duplikatPaarSchluessel('a', 'b')},
      ));
      expect(gruppen.single.toSet(), {'a', 'b', 'c'});
    });
  });

  group('Speicherung', () {
    test('eine Gruppe legt alle ihre Paare an und lässt sich zurücknehmen', () async {
      await db.ignoriereDuplikatgruppe(['a', 'b', 'c']);
      expect(await db.zaehleDuplikatAusnahmen(), 3, reason: 'drei Paare aus drei Fotos');
      expect(await db.duplikatAusnahmeSchluessel(), {
        duplikatPaarSchluessel('a', 'b'),
        duplikatPaarSchluessel('a', 'c'),
        duplikatPaarSchluessel('b', 'c'),
      });

      // Zweimal dasselbe darf nicht scheitern und nichts verdoppeln.
      await db.ignoriereDuplikatgruppe(['c', 'a', 'b']);
      expect(await db.zaehleDuplikatAusnahmen(), 3);

      await db.hebeDuplikatgruppeAuf(['a', 'b', 'c']);
      expect(await db.zaehleDuplikatAusnahmen(), 0);
    });

    test('das endgültige Löschen eines Fotos räumt seine Ausnahmen mit weg', () async {
      await lege('a', vektor(0.01));
      await lege('b', vektor(0.02));
      await db.ignoriereDuplikatgruppe(['a', 'b']);
      expect(await db.zaehleDuplikatAusnahmen(), 1);

      await db.deleteAssetRows(['a']);

      // Sonst bliebe eine Zeile ohne Foto liegen, die nie wieder wirken
      // kann und niemandem mehr auffällt.
      expect(await db.zaehleDuplikatAusnahmen(), 0);
    });
  });

  group('Ansicht', () {
    late LibraryState library;

    setUp(() async {
      final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
      library = LibraryState()
        ..db = db
        ..paths = paths
        ..backupService = BackupService(db, paths)
        ..clipBildHalter = ModellHalter<ClipService>(
          name: 'CLIP-Bild',
          installiert: true,
          laden: () async => throw StateError('im Test wird nichts geladen'),
          entsorgen: (_) async {},
        );
    });

    /// Baut den Bildschirm auf und wartet, bis der Durchlauf durch ist.
    ///
    /// Die Gruppenbildung läuft über `compute()` in einem echten Isolate.
    /// In der gestellten Zeit eines Widget-Tests kommt das nie zurück –
    /// deshalb dazwischen ein `runAsync`, in dem die Uhr wirklich läuft.
    Future<void> zeige(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // Erst etwas anderes zeigen, damit beim zweiten Aufruf wirklich ein
      // neuer Bildschirm entsteht. Sonst bliebe der State erhalten,
      // `initState` liefe nicht erneut, und ein Test, der „beim nächsten
      // Durchlauf" prüfen will, prüfte in Wahrheit nur die im Speicher
      // stehende Liste.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        builder: (context, kind) => mitMeldungen(kind),
        home: DuplicatesScreen(library: library),
      ));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
      }
      fail('der Durchlauf kam nicht zum Ende');
    }

    testWidgets('nennt die Zahl der Gruppen und der Fotos darin', (tester) async {
      await lege('a', vektor(0.01));
      await lege('b', vektor(0.02));
      await lege('c', vektor(0.015));

      await zeige(tester);

      // „7 Gruppen" allein sagt nicht, ob dahinter 14 oder 60 Fotos stehen.
      expect(find.text('1 Gruppen mit 3 Fotos'), findsOneWidget);
    });

    testWidgets('„Übergehen" blendet die Gruppe aus und merkt sich das', (tester) async {
      await lege('a', vektor(0.01));
      await lege('b', vektor(0.02));

      await zeige(tester);
      expect(find.text('1 Gruppen mit 2 Fotos'), findsOneWidget);

      await tester.tap(find.text('Übergehen'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Keine Gruppen gefunden'), findsOneWidget);
      expect(find.text('1 übergangen'), findsOneWidget);
      expect(await db.zaehleDuplikatAusnahmen(), 1);

      // Und der nächste Durchlauf zeigt sie ebenfalls nicht mehr – darum
      // ging es.
      await zeige(tester);
      expect(find.text('Keine Gruppen gefunden'), findsOneWidget);
    });

    testWidgets('die Meldung dazu verschwindet von selbst', (tester) async {
      // Der gemeldete Fehler: „2 Fotos werden bei der Duplikatsuche
      // künftig übergangen" blieb stehen, auch nach zwanzig Sekunden.
      // Ursache war Flutters Voreinstellung, jede SnackBar mit Knopf
      // liegen zu lassen. Seit der Meldungszentrale steht die Frist an
      // der Meldung selbst – dieser Test hält fest, dass sie greift.
      await lege('a', vektor(0.01));
      await lege('b', vektor(0.02));
      await zeige(tester);

      await tester.tap(find.text('Übergehen'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Der Knopf ist da, solange die Meldung steht.
      expect(find.text('Rückgängig'), findsOneWidget);
      expect(melde.sichtbare.single.dauer, const Duration(seconds: 8));

      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('Rückgängig'), findsNothing);
      expect(melde.sichtbare, isEmpty);
      // Nachlesbar bleibt sie – das ist der Unterschied zur SnackBar.
      expect(melde.verlauf, hasLength(1));
    });
  });
}
