import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/import_plan.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/automation_rules_screen.dart';
import 'package:photo_vault/screens/camera_presets_screen.dart';
import 'package:photo_vault/screens/import_plan_screen.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// Regeln und Kameravorgaben, deren Zielalbum gelöscht wurde (IMP-024).
///
/// Vorher blieben sie still stehen: Die Importprüfung sperrte jedes Foto,
/// auf das so eine Regel zutraf, mit einem allgemeinen Satz über „eine
/// Regel“, und der Import ohne Prüfung legte das Foto in ein Album, das es
/// nicht gibt. Jetzt fällt das fehlende Ziel weg, der Rest der Regel gilt,
/// die Prüfung nennt die Regel, und die Liste der Regeln zeigt sie an.
void main() {
  final t = lookupAppTexte(const Locale('de'));
  late Directory temp;
  late AppDatabase db;
  late StoragePaths pfade;
  late ImportService importe;
  late LibraryState library;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_regel_ohne_album_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'bibliothek')),
    );
    importe = ImportService(db, pfade);
    library = LibraryState()
      ..db = db
      ..paths = pfade
      ..importService = importe;
    await db.fuehreAus(AlbumAnlegen('weg', 'Bald weg', DateTime(2026)));
    await db.fuehreAus(
      RegelSpeichern(
        AutomationRulesCompanion.insert(
          id: 'r1',
          name: 'Urlaubsbilder',
          triggerType: 'dateiname',
          aiTagTerm: const Value('urlaub'),
          targetAlbumId: const Value('weg'),
          autoFavorite: const Value(true),
        ),
      ),
    );
    await db.upsertCameraPreset(
      CameraPresetsCompanion.insert(
        id: 'k1',
        cameraMake: 'Testkamera',
        cameraModel: 'T1',
        targetAlbumId: const Value('weg'),
        autoFavorite: const Value(true),
      ),
    );
    // Gelöscht, wie es ein anderes Gerät oder der Server tun kann.
    await (db.delete(db.albums)..where((a) => a.id.equals('weg'))).go();
  });

  tearDown(() async {
    library.dispose();
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<String> foto(String name, List<int> bytes) async {
    final f = File(p.join(temp.path, name));
    await f.writeAsBytes(bytes);
    return f.path;
  }

  Future<int> albumzeilen() async =>
      (await db.select(db.albumAssets).get()).length;

  test('die Prüfung sperrt das Foto nicht und nennt die Regel', () async {
    final dienst = ImportPlanDienst(db, importe);
    final quelle = await foto('urlaub.jpg', [1, 2, 3]);
    final plan = await dienst.erstelle([quelle]);
    final e = plan.eintraege.single;
    expect(e.art, ImportPlanArt.neu);
    expect(e.regelnOhneZiel, ['Urlaubsbilder']);
    expect(e.albumIds, isEmpty, reason: 'das fehlende Ziel fällt weg');
    expect(e.favorit, isTrue, reason: 'der Rest der Regel gilt');

    final r = await importe.importFile(
      quelle,
      erwartetePruefsumme: plan.pruefsummen[quelle],
      erwarteteAngaben: e.angaben,
      beiEintrag: (id) => dienst.uebernehme(plan, e, id),
    );
    expect(r.outcome, ImportOutcome.imported);
    expect((await db.assetById(r.assetId!))!.isFavorite, isTrue);
    expect(await albumzeilen(), 0, reason: 'kein Album, das es nicht gibt');
  });

  test('ohne Prüfung landet nichts in einem gelöschten Album', () async {
    for (final (name, byte) in [('a.jpg', 7), ('b.jpg', 8)]) {
      final r = await importe.importFile(await foto(name, [byte]));
      final id = r.assetId!;
      await library.applyCameraPreset(
        id,
        cameraMake: 'Testkamera',
        cameraModel: 'T1',
      );
      await library.applyAutomationRules(
        id,
        rules: [
          (await db.allAutomationRules()).single.copyWith(
            triggerType: 'dateRange',
            dateFrom: Value(DateTime(2000)),
            dateTo: Value(DateTime(2100)),
          ),
        ],
        fileCreatedAt: DateTime(2026),
      );
      expect((await db.assetById(id))!.isFavorite, isTrue);
    }
    expect(await albumzeilen(), 0);
  });

  /// Die Ströme der Datenbank brauchen echte Zeit.
  Future<void> warte(WidgetTester tester, [int runden = 10]) async {
    for (var i = 0; i < runden; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> zeige(WidgetTester tester, Widget bildschirm) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: bildschirm,
      ),
    );
    await warte(tester);
  }

  Future<void> raeumeAb(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('die Regeln zeigen das gelöschte Zielalbum an', (tester) async {
    await zeige(tester, AutomationRulesScreen(library: library));
    expect(find.textContaining(t.regelZielalbumGeloescht), findsOneWidget);
    await raeumeAb(tester);
  });

  testWidgets('die Kamera-Presets zeigen das gelöschte Zielalbum an', (
    tester,
  ) async {
    await zeige(tester, CameraPresetsScreen(library: library));
    expect(find.textContaining(t.presetZielalbumGeloescht), findsOneWidget);
    await raeumeAb(tester);
  });

  testWidgets('die Importprüfung lässt das Foto wählen und nennt den Grund', (
    tester,
  ) async {
    final quelle = (await tester.runAsync(
      () => foto('urlaub.jpg', [4, 5, 6]),
    ))!;
    await zeige(tester, ImportPlanScreen(library: library, dateien: [quelle]));
    for (
      var i = 0;
      i < 100 && find.text(t.importPlanStarten(1)).evaluate().isEmpty;
      i++
    ) {
      await warte(tester, 1);
    }
    expect(find.text(t.importPlanStarten(1)), findsOneWidget);
    expect(
      find.textContaining(t.importPlanZielGeloescht('Urlaubsbilder')),
      findsOneWidget,
    );
    final zeile = tester.widget<CheckboxListTile>(
      find.byType(CheckboxListTile).first,
    );
    expect(zeile.value, isTrue);
    expect(zeile.onChanged, isNotNull);
    await raeumeAb(tester);
  });
}
