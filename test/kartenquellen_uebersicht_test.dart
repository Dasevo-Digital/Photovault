import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/eigenkarte.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/services/platform/webseite_oeffnen.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/kartenquellen_uebersicht.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

void main() {
  late AppDatabase db;
  late LibraryState library;
  final gereicht = <Kartenvorlage>[];

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()..db = db;
    gereicht.clear();
  });

  tearDown(() async {
    melde.verlaufLeeren();
    setzeEigeneKarte(null);
    await db.close();
  });

  Future<void> zeige(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: KartenquellenUebersicht(
            library: library,
            aufVorlage: gereicht.add,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Die Zeile einer Quelle – von ihrem Namen aus zum ListTile hinauf.
  Finder zeile(String name) => find.ancestor(
        of: find.text(name),
        matching: find.byType(ListTile),
      );

  testWidgets('alle mitgelieferten Karten stehen drin', (tester) async {
    await zeige(tester);
    expect(find.text('Hell'), findsOneWidget);
    expect(find.text('Dunkel'), findsOneWidget);
    expect(find.text('Topografie'), findsOneWidget);
  });

  testWidgets('und jede Vorlage', (tester) async {
    await zeige(tester);
    for (final v in kartenvorlagen) {
      expect(find.text(v.name), findsOneWidget, reason: v.name);
    }
  });

  testWidgets('die Tiefe steht in Stufen UND in Metern', (tester) async {
    // Der eigentliche Zweck: „bis Stufe 17" sagt niemandem etwas.
    await zeige(tester);
    expect(find.textContaining('bis Stufe 19 · rund 18 m'), findsWidgets);
    expect(find.textContaining('bis Stufe 17 · rund 74 m'), findsOneWidget);
    expect(find.textContaining('bis Stufe 20 · rund 9 m'), findsWidgets);
  });

  testWidgets('gemessen und behauptet werden auseinandergehalten',
      (tester) async {
    await zeige(tester);
    expect(find.textContaining('nachgemessen'), findsWidgets);
    expect(find.textContaining('laut Anbieter'), findsWidgets);
  });

  testWidgets('wo ein Schluessel noetig ist, steht es dabei', (tester) async {
    await zeige(tester);
    final mitSchluessel =
        kartenvorlagen.where((v) => v.brauchtSchluessel).length;
    expect(find.textContaining('Schlüssel nötig'), findsNWidgets(mitSchluessel));
  });

  testWidgets('die Namensnennung jedes Anbieters steht dabei', (tester) async {
    // Sie ist eine Lizenzauflage - eine Uebersicht ohne sie waere eine
    // Werbeliste.
    await zeige(tester);
    expect(find.textContaining('© Esri'), findsWidgets);
    expect(find.textContaining('© OpenStreetMap contributors'), findsWidgets);
  });

  testWidgets('jede Zeile fuehrt zur Seite ihres Anbieters', (tester) async {
    // Ohne diesen Knopf muesste man den Anbieternamen abtippen, um seine
    // Bedingungen zu lesen - genau die Bedingungen, auf die die Warnung
    // vor dem Einschalten verweist.
    await zeige(tester);
    for (final v in kartenvorlagen) {
      expect(
        find.descendant(
            of: zeile(v.name), matching: find.byIcon(Icons.open_in_new)),
        findsOneWidget,
        reason: v.name,
      );
    }
    for (final name in ['Hell', 'Dunkel', 'Topografie']) {
      expect(
        find.descendant(
            of: zeile(name), matching: find.byIcon(Icons.open_in_new)),
        findsOneWidget,
        reason: name,
      );
    }
  });

  testWidgets('eine Vorlage ohne Schluessel laesst sich einschalten',
      (tester) async {
    await zeige(tester);
    final v = kartenvorlagen.firstWhere((v) => v.sofortNutzbar);
    await tester.tap(find.descendant(
        of: zeile(v.name), matching: find.text('Übernehmen')));
    await tester.pumpAndSettle();

    // Erst die Warnung, und zwar dieselbe wie im Formular darunter.
    expect(find.text('Bevor du eine fremde Kartenquelle einschaltest'),
        findsOneWidget);
    await tester.tap(find.text('Verstanden, einschalten'));
    await tester.pumpAndSettle();

    // In den Einstellungen, im laufenden Kartenweg und als Standard.
    final gespeichert = await db.eigeneKarteWert();
    expect(gespeichert?.url, v.url);
    expect(gespeichert?.nennung, v.nennung);
    expect(gespeichert?.stufe, v.stufe);
    expect(eigeneKarte?.url, v.url);
    expect(await db.kartenansicht(), 'eigene');
  });

  testWidgets('wer die Warnung abbricht, hat nichts eingeschaltet',
      (tester) async {
    await zeige(tester);
    final v = kartenvorlagen.firstWhere((v) => v.sofortNutzbar);
    await tester.tap(find.descendant(
        of: zeile(v.name), matching: find.text('Übernehmen')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    expect(await db.eigeneKarteWert(), isNull);
    expect(eigeneKarte, isNull);
    expect(await db.kartenansicht(), isNot('eigene'));
  });

  testWidgets('eine Vorlage mit Schluessel wandert ins Formular',
      (tester) async {
    // Sie laesst sich NICHT mit einem Klick einschalten - in ihrer
    // Adresse stuende sonst die Schluesselmarke, und der Anbieter
    // antwortete mit einem Rechtefehler.
    await zeige(tester);
    final v = kartenvorlagen.firstWhere((v) => v.brauchtSchluessel);
    expect(find.descendant(of: zeile(v.name), matching: find.text('Übernehmen')),
        findsNothing);
    await tester.tap(
        find.descendant(of: zeile(v.name), matching: find.text('Eintragen')));
    await tester.pumpAndSettle();

    expect(gereicht, [v]);
    expect(await db.eigeneKarteWert(), isNull);
  });

  testWidgets('die gemerkte Ansicht traegt die Marke und keinen Knopf',
      (tester) async {
    await db.setzeKartenansicht('topo');
    await zeige(tester);
    expect(find.descendant(of: zeile('Topografie'), matching: find.text('Standard')),
        findsOneWidget);
    expect(
        find.descendant(
            of: zeile('Topografie'), matching: find.text('Als Standard')),
        findsNothing);
    // Die anderen tragen ihn sehr wohl.
    expect(find.descendant(of: zeile('Hell'), matching: find.text('Als Standard')),
        findsOneWidget);
  });

  testWidgets('eine mitgelieferte Karte laesst sich zum Standard machen',
      (tester) async {
    await db.setzeKartenansicht('dunkel');
    await zeige(tester);
    await tester.tap(find.descendant(
        of: zeile('Topografie'), matching: find.text('Als Standard')));
    await tester.pumpAndSettle();
    expect(await db.kartenansicht(), 'topo');
    // Und die Marke wandert mit, ohne dass der Bildschirm neu aufgebaut
    // wird.
    expect(find.descendant(of: zeile('Topografie'), matching: find.text('Standard')),
        findsOneWidget);
  });

  group('Adressen', () {
    test('jede Vorlage nennt eine erreichbare Anbieterseite', () {
      for (final v in kartenvorlagen) {
        expect(istWebadresse(v.seite), isTrue, reason: v.name);
        expect(v.seite, startsWith('https://'), reason: v.name);
      }
    });

    test('jeder mitgelieferte Stil ausser der eigenen Quelle auch', () {
      for (final s in Kartenstil.values) {
        if (s == Kartenstil.eigene) {
          // Was dort eingetragen ist, weiss die App nicht - eine
          // geratene Adresse waere schlimmer als keine.
          expect(s.seite, isNull);
          continue;
        }
        expect(istWebadresse(s.seite!), isTrue, reason: s.name);
      }
    });

    test('was keine Webadresse ist, wird gar nicht erst geoeffnet', () {
      // Der Wert landet als Argument eines Systembefehls - `open` unter
      // macOS startet auch Programme.
      expect(istWebadresse('file:///etc/passwd'), isFalse);
      expect(istWebadresse('/Applications/Rechner.app'), isFalse);
      expect(istWebadresse('javascript:alert(1)'), isFalse);
      expect(istWebadresse('https://'), isFalse);
      expect(istWebadresse(''), isFalse);
      expect(istWebadresse('http://beispiel.de/a?b=1&c=2'), isTrue);
    });
  });

  test('eine Vorlage wird unveraendert zur Quelle', () {
    final v = kartenvorlagen.first;
    final k = Eigenkarte.vonVorlage(v);
    expect(k.name, v.name);
    expect(k.url, v.url);
    expect(k.nennung, v.nennung);
    expect(k.stufe, v.stufe);
    expect(k.zugestimmt, isTrue);
    // Und sie kommt durch dieselbe Pruefung wie eine getippte Adresse.
    expect(Eigenkarte.adressfehler(k.url), isNull);
  });
}
