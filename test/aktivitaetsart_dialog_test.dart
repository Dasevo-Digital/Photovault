import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/aktivitaetsart_anzeige.dart';

/// Das Fenster, in dem man die Art einer Aktivität wählt – oder eine
/// neue einträgt.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<void> aktivitaet(String id, String art) => db.aktivitaetAnlegen(
        AktivitaetenCompanion.insert(
          id: id,
          name: id,
          art: art,
          von: DateTime(2026, 6, 1, 9),
          bis: DateTime(2026, 6, 1, 12),
          angelegtAm: DateTime(2026),
        ),
        const [],
      );

  /// Öffnet das Fenster und legt das Ergebnis in [ergebnisse] ab.
  final ergebnisse = <String, String?>{};

  Future<void> zeige(WidgetTester tester, {String? aktuell}) async {
    ergebnisse.clear();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                ergebnisse['art'] =
                    await frageAktivitaetsart(context, db: db, aktuell: aktuell);
              },
              child: const Text('auf'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('auf'));
    await tester.pumpAndSettle();
  }

  testWidgets('die mitgelieferten Arten stehen darin, Spaziergang zuerst',
      (tester) async {
    await zeige(tester);
    expect(find.text('Spaziergang'), findsOneWidget);
    expect(find.text('Wanderung'), findsOneWidget);
    expect(find.text('Sonstiges'), findsOneWidget);
    // Der Spaziergang steht über der Wanderung – vom Kürzeren zum
    // Längeren, so wie die Aufzählung sie führt.
    expect(tester.getTopLeft(find.text('Spaziergang')).dy,
        lessThan(tester.getTopLeft(find.text('Wanderung')).dy));
  });

  testWidgets('eine gewählte Art kommt zurück', (tester) async {
    await zeige(tester);
    await tester.tap(find.text('Spaziergang'));
    await tester.pumpAndSettle();
    expect(ergebnisse['art'], 'spaziergang');
  });

  testWidgets('selbst eingetragene Arten stehen mit darin', (tester) async {
    await aktivitaet('a', 'Konzert');
    await zeige(tester);
    expect(find.text('Konzert'), findsOneWidget);
    await tester.tap(find.text('Konzert'));
    await tester.pumpAndSettle();
    expect(ergebnisse['art'], 'Konzert');
  });

  testWidgets('eine neue Art lässt sich eintippen', (tester) async {
    await zeige(tester);
    await tester.tap(find.text('Neue Art …'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  Konzert  ');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(ergebnisse['art'], 'Konzert', reason: 'ohne Leerzeichen ringsum');
  });

  testWidgets('wer eine mitgelieferte eintippt, bekommt die mitgelieferte',
      (tester) async {
    // Sonst stünden zwei Einträge namens „Wanderung" nebeneinander,
    // einer davon ohne Symbol und ohne Übersetzung.
    await zeige(tester);
    await tester.tap(find.text('Neue Art …'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Wanderung');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(ergebnisse['art'], 'wanderung');
  });

  testWidgets('Abbrechen gibt nichts zurück', (tester) async {
    await zeige(tester);
    // Neben das Fenster tippen schliesst es.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(ergebnisse['art'], isNull);
  });
}
