import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/automation_rules_screen.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// Bearbeiten einer Regel, deren gespeicherter Begriff nicht (mehr) im
/// Vokabular steht (KI-167). Die Auswahl „KI-Tag-Begriff“ verlangt einen
/// Wert aus ihren Einträgen; vorbelegt war ungeprüft das gespeicherte
/// `aiTagTerm`, und der Dialog brach mit einer Zusicherung ab.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_regel_');
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

  AutomationRuleData regel(String art, String? begriff) => AutomationRuleData(
    id: 'r',
    name: 'R',
    triggerType: art,
    aiTagTerm: begriff,
    autoFavorite: false,
  );

  test('die Vorbelegung steht immer im Vokabular oder ist leer', () {
    const vokabular = ['Strand', 'Wald'];
    expect(vorbelegterKiTagBegriff(null, vokabular), 'Strand');
    expect(vorbelegterKiTagBegriff(regel('aiTag', 'Wald'), vokabular), 'Wald');
    expect(
      vorbelegterKiTagBegriff(regel('aiTag', 'Entfernt'), vokabular),
      isNull,
      reason: 'kein stiller Ersatz für einen entfernten Begriff',
    );
    expect(
      vorbelegterKiTagBegriff(regel('dateiname', 'TEST'), vokabular),
      'Strand',
    );
    expect(vorbelegterKiTagBegriff(regel('aiTag', 'Wald'), const []), isNull);
  });

  /// Die Ströme der Datenbank brauchen echte Zeit; ein Ladekreis liesse
  /// pumpAndSettle nie zur Ruhe kommen.
  Future<void> warte(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> zeige(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: AutomationRulesScreen(library: library),
      ),
    );
    await warte(tester);
  }

  /// Die Ströme der Datenbank hinterlassen sonst Wecker, die den Test
  /// überleben.
  Future<void> raeumeAb(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> bearbeite(WidgetTester tester) async {
    await tester.tap(
      find.byTooltip(lookupAppTexte(const Locale('de')).allgBearbeiten),
    );
    await warte(tester);
  }

  testWidgets('ein entfernter Begriff öffnet den Dialog mit leerer Auswahl', (
    tester,
  ) async {
    final t = lookupAppTexte(const Locale('de'));
    await tester.runAsync(
      () => db
          .into(db.automationRules)
          .insert(
            AutomationRulesCompanion.insert(
              id: 'r1',
              name: 'Alte Regel',
              triggerType: 'aiTag',
              aiTagTerm: const Value('Gibt es nicht mehr'),
            ),
          ),
    );
    await zeige(tester);
    await bearbeite(tester);

    expect(tester.takeException(), isNull);
    final auswahl = tester.widget<DropdownButton<String>>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byWidgetPredicate(
          (w) => w is DropdownButton<String> && w.items!.length > 5,
        ),
      ),
    );
    expect(auswahl.value, isNull);
    expect(find.text(t.regelTagBegriff), findsOneWidget);
    await raeumeAb(tester);
  });

  testWidgets('„Dateiname enthält“ lässt sich auf „KI-Tag“ umstellen', (
    tester,
  ) async {
    final t = lookupAppTexte(const Locale('de'));
    await tester.runAsync(
      () => db
          .into(db.automationRules)
          .insert(
            AutomationRulesCompanion.insert(
              id: 'r1',
              name: 'Testregel',
              triggerType: 'dateiname',
              aiTagTerm: const Value('TEST'),
            ),
          ),
    );
    await zeige(tester);
    await bearbeite(tester);

    await tester.tap(find.text(t.regelAusloeserDateiname).last);
    await warte(tester);
    await tester.tap(find.text(t.regelAusloeserTag).last);
    await warte(tester);

    expect(tester.takeException(), isNull);
    expect(find.text(t.regelTagBegriff), findsOneWidget);
    final vokabular = (await tester.runAsync(db.aiTagVocabularyTerms))!;
    expect(find.text(vokabular.first), findsWidgets);
    await raeumeAb(tester);
  });
}
