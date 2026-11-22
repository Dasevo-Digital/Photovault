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
import 'package:photo_vault/screens/import_progress_sheet.dart';
import 'package:photo_vault/services/library_location.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/state/importlauf.dart';
import 'package:photo_vault/state/library_state.dart';

/// Der Import hängt nicht mehr am Fortschrittsblatt (IMP-039).
///
/// Vorher lief er im Zustand eines modalen Blattes, das sich weder
/// wegschieben noch abbrechen liess – die App war für die Dauer des
/// Imports gesperrt. Jetzt ist er ein Lauf in der Aufgabenleiste, das
/// Blatt eine Ansicht darauf, und Fehler wie Ergebnis bleiben erreichbar,
/// wenn das Blatt weg ist.
void main() {
  final de = lookupAppTexte(const Locale('de'));
  late Directory temp;
  late AppDatabase db;
  late StoragePaths pfade;
  late ImportService importe;
  late LibraryState library;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_importlauf_');
    LibraryLocation.nutzeFuerTests(anker: temp);
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'bibliothek')),
    );
    importe = ImportService(db, pfade);
    library = LibraryState()
      ..db = db
      ..paths = pfade
      ..importService = importe;
    // Die Auswertung danach liefe über das Ende des Tests hinaus.
    await db.setAutoAnalyzeAfterImport(false);
    melde.verlaufLeeren();
  });

  tearDown(() async {
    melde.alleSchliessen();
    LibraryLocation.zuruecksetzenFuerTests();
    library.dispose();
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<ImportPlan> plan(int n, {String stamm = 'f'}) async {
    final dateien = [
      for (var i = 0; i < n; i++)
        (File(
          p.join(temp.path, '$stamm$i.jpg'),
        )..writeAsBytesSync([1, 2, 3, i, stamm.codeUnitAt(0)])).path,
    ];
    return ImportPlanDienst(db, importe).erstelle(dateien);
  }

  Importlauf neuerLauf(ImportPlan plan, {List<Importlauf>? gezeigt}) {
    final lauf = Importlauf(
      library: library,
      plan: plan,
      texte: de,
      zeigen: gezeigt?.add,
    );
    library.setzeImportlauf(lauf);
    return lauf;
  }

  test('der Import steht in der Aufgabenleiste und meldet sein Ende', () async {
    final gezeigt = <Importlauf>[];
    final lauf = neuerLauf(await plan(3), gezeigt: gezeigt);
    final ende = lauf.starte();
    expect(library.laufendeAufgaben.map((l) => l.schluessel), [
      Importlauf.schluessel,
    ], reason: 'mit Fortschritt und „Abbrechen“ in der Leiste');
    expect(library.etwasLaeuft, isTrue, reason: 'Rückfrage beim Beenden');
    await ende;

    expect(lauf.fertig, isTrue);
    expect(lauf.importierteIds, hasLength(3));
    expect(lauf.quittungId, isNotNull);
    expect(library.offeneAufgaben, isEmpty);
    expect(await db.select(db.assets).get(), hasLength(3));
    // Niemand sah hin: Das Ergebnis kommt als Meldung mit „Anzeigen“.
    final m = melde.verlauf.single;
    expect(m.text, startsWith(de.importAbgeschlossen));
    expect(m.text, contains(de.importBilanzNeu(3)));
    expect(m.aktion?.beschriftung, de.importAnzeigen);
    m.aktion!.beiDruck();
    expect(gezeigt, [lauf]);
  });

  test('wer auf das Blatt sieht, bekommt keine zweite Meldung', () async {
    final lauf = neuerLauf(await plan(2))..angezeigt();
    await lauf.starte();
    expect(lauf.fertig, isTrue);
    expect(melde.verlauf, isEmpty);
  });

  test('der Import lässt sich abbrechen', () async {
    final lauf = neuerLauf(await plan(40));
    final ende = lauf.starte();
    while (lauf.erledigt < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    lauf.abbrechen();
    await ende;
    expect(lauf.abgebrochen, isTrue);
    expect(lauf.fertig, isTrue);
    expect(library.offeneAufgaben, isEmpty);
    final n = (await db.select(db.assets).get()).length;
    expect(n, lessThan(40));
    expect(n, lauf.importierteIds.length);
    expect(melde.verlauf.single.text, startsWith(de.importAbgebrochen));
  });

  test('ein Abbruch des ganzen Laufs meldet sich auch ohne Blatt', () async {
    final p0 = await plan(2);
    // Eine Regel ändert sich zwischen Prüfung und Import.
    await db.upsertAutomationRule(
      AutomationRulesCompanion.insert(
        id: 'neu',
        name: 'Neu',
        triggerType: 'dateiname',
        aiTagTerm: const Value('x'),
      ),
    );
    final lauf = neuerLauf(p0);
    await lauf.starte();
    expect(lauf.gescheitert.keys.toSet(), p0.pruefsummen.keys.toSet());
    expect(
      melde.verlauf.map((m) => m.text),
      contains(de.importPlanGeaendert),
      reason: 'der Grund, gleich ob jemand hinsieht',
    );
    final ende = melde.verlauf.firstWhere(
      (m) => m.text.startsWith(de.importAbgeschlossen),
    );
    expect(ende.text, contains(de.importBilanzFehler(2)));
    expect(ende.art, Meldungsart.warnung);
  });

  testWidgets('das Blatt lässt sich wegschieben, der Lauf bleibt', (
    tester,
  ) async {
    final p0 = (await tester.runAsync(() => plan(1)))!;
    final lauf = Importlauf(library: library, plan: p0, texte: de);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => zeigeImportblatt(context, lauf),
              child: const Text('öffnen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('öffnen'));
    await tester.pumpAndSettle();
    expect(find.text(de.importLaeuft), findsOneWidget);
    expect(find.text(de.allgAbbrechen), findsOneWidget);
    expect(lauf.sichtbar, isTrue);

    // Daneben klicken schliesst das Blatt.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.text(de.importLaeuft), findsNothing);
    expect(lauf.sichtbar, isFalse);

    // „Im Hintergrund weiter“ ebenso.
    await tester.tap(find.text('öffnen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(de.importImHintergrund));
    await tester.pumpAndSettle();
    expect(find.text(de.importLaeuft), findsNothing);

    // Wieder geöffnet zeigt es das Ergebnis samt erneutem Versuch.
    lauf
      ..fertig = true
      ..fehler = 1
      ..gescheitert[p0.eintraege.single.pfad] = 'pv_import_quelle_geaendert';
    await tester.tap(find.text('öffnen'));
    await tester.pumpAndSettle();
    expect(find.text(de.importAbgeschlossen), findsOneWidget);
    expect(find.text(de.importErneutVersuchen(1)), findsOneWidget);
    expect(find.text(de.allgAbbrechen), findsNothing);
  });
}
