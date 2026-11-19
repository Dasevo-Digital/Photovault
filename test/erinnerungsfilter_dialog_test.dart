import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/erinnerungsfilter.dart';
import 'package:teilen_ui/erinnerungsfilter.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/familientage_abschnitt.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  testWidgets(
    'Ein geöffneter Familientag verschwindet auch bei einem extern übernommenen Ausschluss',
    (tester) async {
      await db
          .into(db.people)
          .insert(
            PeopleCompanion.insert(
              id: 'p',
              name: 'Testperson',
              geburtsdatum: Value(DateTime(2000, 11, 19)),
            ),
          );
      final library = LibraryState()..db = db;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          home: Scaffold(
            body: FamilientageAbschnitt(
              library: library,
              heute: DateTime(2026, 11, 19),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Testperson'), findsOneWidget);
      await db.fuehreAus(
        ErinnerungsfilterSetzen(Erinnerungsfilter(personen: ['p'])),
      );
      for (
        var i = 0;
        i < 8 && find.textContaining('Testperson').evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(find.textContaining('Testperson'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      library.dispose();
    },
  );

  Future<void> oeffne(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => zeigeErinnerungsfilter(context, db),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
  }

  testWidgets('Abbrechen erhält Ausschlüsse, Speichern übernimmt Personen', (
    tester,
  ) async {
    await db.fuehreAus(const PersonAnlegen('p', 'Testperson'));
    await db.fuehreAus(
      ErinnerungsfilterSetzen(Erinnerungsfilter(alben: ['entfernt'])),
    );
    await oeffne(tester);
    await tester.tap(find.text('Testperson'));
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect((await db.erinnerungsfilter()).personen, isEmpty);
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Testperson'));
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect((await db.erinnerungsfilter()).personen, ['p']);
    expect((await db.erinnerungsfilter()).alben, ['entfernt']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Beschädigte Filter werden erst nach ausdrücklichem Speichern ersetzt',
    (tester) async {
      const kaputt = '{ "fassung": 8 }';
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            const AppSettingsCompanion(
              id: Value(0),
              erinnerungsfilter: Value(kaputt),
            ),
          );
      await oeffne(tester);
      expect(find.textContaining('nicht lesbar'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(
        (await db.select(db.appSettings).getSingle()).erinnerungsfilter,
        kaputt,
      );
      await tester.tap(find.text('Öffnen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect((await db.erinnerungsfilter()).leer, isTrue);
    },
  );
}
