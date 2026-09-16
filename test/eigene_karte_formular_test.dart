import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/eigenkarte.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/eigene_karte_einstellung.dart';
import 'package:photo_vault/widgets/kartenquellen_uebersicht.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

/// Der Weg von der Übersicht ins Formular – für die Vorlagen, die sich
/// nicht mit einem Klick einschalten lassen.
///
/// **Warum beide Widgets zusammen im Test stehen.** Getrennt sind beide
/// grün und die Verbindung trotzdem tot: Die Übersicht ruft nur einen
/// Rückruf, das Formular hat nur eine öffentliche Methode. Erst die
/// Verdrahtung – dieselbe wie im Einstellungsbildschirm – beweist, dass
/// die Vorlage ankommt.
void main() {
  late AppDatabase db;
  late LibraryState library;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()..db = db;
  });

  tearDown(() async {
    melde.verlaufLeeren();
    setzeEigeneKarte(null);
    await db.close();
  });

  Future<void> zeige(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final formular = GlobalKey<EigeneKarteEinstellungState>();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              KartenquellenUebersicht(
                library: library,
                aufVorlage: (v) => formular.currentState?.vorlageEinsetzen(v),
              ),
              EigeneKarteEinstellung(key: formular, library: library),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Was in einem Textfeld mit dieser Beschriftung steht.
  String feld(WidgetTester tester, String beschriftung) {
    final f = tester.widget<TextField>(find.ancestor(
      of: find.text(beschriftung),
      matching: find.byType(TextField),
    ));
    return f.controller!.text;
  }

  testWidgets('Eintragen fuellt alles aus ausser dem Schluessel',
      (tester) async {
    await zeige(tester);
    final v = kartenvorlagen.firstWhere((v) => v.brauchtSchluessel);
    await tester.tap(find.descendant(
      of: find.ancestor(
          of: find.text(v.name), matching: find.byType(ListTile)),
      matching: find.text('Eintragen'),
    ));
    await tester.pumpAndSettle();

    expect(feld(tester, 'Name'), v.name);
    expect(feld(tester, 'Kacheladresse'), v.url);
    expect(feld(tester, 'Namensnennung'), v.nennung);
    expect(feld(tester, 'Höchste Zoomstufe'), '${v.stufe}');
    // Und genau das eine Stück fehlt noch.
    expect(feld(tester, 'Kacheladresse'), contains(schluesselMarke));
    expect(await db.eigeneKarteWert(), isNull);
  });

  testWidgets('wo es den Schluessel gibt, ist anklickbar', (tester) async {
    await zeige(tester);
    final v = kartenvorlagen.firstWhere((v) => v.woher != null);
    await tester.tap(find.descendant(
      of: find.ancestor(
          of: find.text(v.name), matching: find.byType(ListTile)),
      matching: find.text('Eintragen'),
    ));
    await tester.pumpAndSettle();

    final knopf = find.widgetWithText(
        TextButton, 'Schlüssel gibt es bei ${v.woher}');
    expect(knopf, findsOneWidget);
    expect(tester.widget<TextButton>(knopf).onPressed, isNotNull);
  });
}
