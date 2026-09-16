import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/widgets/meldungsfenster.dart';

/// Die Meldungen, wie man sie sieht.
///
/// Der Stapel liegt über jedem Bildschirm. Das ist bequem und gefährlich
/// zugleich – deshalb prüft der wichtigste Test hier nicht, was man
/// sieht, sondern was man **darunter** noch anfassen kann.
void main() {
  late Meldungsdienst d;

  setUp(() => d = Meldungsdienst());
  tearDown(() => d.dispose());

  var gedrueckt = 0;

  Future<void> zeige(WidgetTester tester,
      {Size groesse = const Size(1200, 900)}) async {
    gedrueckt = 0;
    tester.view.physicalSize = groesse;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      builder: (context, kind) => mitMeldungen(kind, dienst: d),
      home: Scaffold(
        appBar: AppBar(title: const Text('Bildschirm')),
        body: Center(
          child: FilledButton(
            onPressed: () => gedrueckt++,
            child: const Text('Darunter'),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  /// Räumt den Stapel ab. Nötig am Ende jedes Tests, der eine Meldung
  /// stehen lässt: Der Rahmen prüft direkt nach dem Testkörper auf
  /// offene Uhren – vor jedem `tearDown`.
  Future<void> ruhe(WidgetTester tester) async {
    d.alleSchliessen();
    await tester.pump();
  }

  testWidgets('eine Meldung erscheint mit ihrem Text', (tester) async {
    await zeige(tester);
    d.erfolg('Alles gesichert');
    await tester.pump();
    expect(find.text('Alles gesichert'), findsOneWidget);
    await ruhe(tester);
  });

  testWidgets('der Knopf darunter bleibt anklickbar', (tester) async {
    // **Der Test, der diesen Bildschirm rechtfertigt.** Eine Einblendung
    // über allem ist ein unsichtbarer Deckel, wenn man ihn falsch baut:
    // Ein IgnorePointer über dem Stapel nähme den ganzen Teilbaum aus der
    // Trefferprüfung, `Align` und `Padding` ohne einen fangen dagegen
    // nichts ab. Ohne diesen Test sieht beides gleich aus.
    await zeige(tester);
    d.hinweis('Irgendetwas');
    await tester.pump();
    expect(find.text('Irgendetwas'), findsOneWidget);

    await tester.tap(find.text('Darunter'));
    await tester.pump();
    expect(gedrueckt, 1);
    await ruhe(tester);
  });

  testWidgets('wegklicken lässt sie verschwinden', (tester) async {
    await zeige(tester);
    d.fehler('Kaputt');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text('Kaputt'), findsNothing);
    await ruhe(tester);
  });

  testWidgets('ein Hinweis geht von selbst, ein Fehler bleibt', (tester) async {
    await zeige(tester);
    d.hinweis('Geht gleich');
    d.fehler('Bleibt stehen');
    await tester.pump();
    expect(find.text('Geht gleich'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Geht gleich'), findsNothing);
    expect(find.text('Bleibt stehen'), findsOneWidget);

    await tester.pump(const Duration(minutes: 2));
    expect(find.text('Bleibt stehen'), findsOneWidget);
    await ruhe(tester);
  });

  testWidgets('der Knopf an einer Meldung wirkt und schliesst sie',
      (tester) async {
    await zeige(tester);
    var zurueck = 0;
    d.hinweis('3 Fotos gelöscht',
        aktion: (beschriftung: 'Rückgängig', beiDruck: () => zurueck++));
    await tester.pump();
    await tester.tap(find.text('Rückgängig'));
    await tester.pump();
    expect(zurueck, 1);
    expect(find.text('3 Fotos gelöscht'), findsNothing);
    await ruhe(tester);
  });

  testWidgets('dieselbe Meldung mehrfach zeigt eine Karte mit Zahl',
      (tester) async {
    await zeige(tester);
    for (var i = 0; i < 3; i++) {
      d.warnung('Datei nicht lesbar');
    }
    await tester.pump();
    expect(find.text('Datei nicht lesbar'), findsOneWidget);
    expect(find.text('3×'), findsOneWidget);
    await ruhe(tester);
  });

  testWidgets('im breiten Fenster steht der Stapel oben rechts',
      (tester) async {
    await zeige(tester);
    d.hinweis('Oben rechts');
    await tester.pump();
    final karte = tester.getRect(find.text('Oben rechts'));
    expect(karte.center.dx, greaterThan(600), reason: 'rechte Hälfte von 1200');
    expect(karte.center.dy, lessThan(450), reason: 'obere Hälfte von 900');
    // Und unterhalb der Titelleiste – darüber lägen ihre Knöpfe.
    expect(karte.top, greaterThan(kToolbarHeight));
    await ruhe(tester);
  });

  testWidgets('im schmalen Fenster weicht er nach unten', (tester) async {
    // Über die ganze Breite verdeckt eine Karte oben mehr als unten.
    await zeige(tester, groesse: const Size(420, 900));
    d.hinweis('Unten');
    await tester.pump();
    expect(tester.getRect(find.text('Unten')).center.dy, greaterThan(450));
    await ruhe(tester);
  });

  testWidgets('die Glocke zählt und öffnet den Verlauf', (tester) async {
    await zeige(tester);
    d.hinweis('Eins');
    d.erfolg('Zwei');
    await tester.pump();
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.notifications_none));
    await tester.pumpAndSettle();
    expect(find.text('Meldungen'), findsOneWidget);
    // Die Tafel klappt im Stapel auf, nicht als Dialog – über dem
    // Navigator gibt es keinen.
    expect(find.byType(Dialog), findsNothing);
    // Beide stehen im Verlauf, auch wenn eine schon verblasst wäre.
    expect(find.text('Eins'), findsWidgets);
    expect(d.ungelesen, 0);
    await ruhe(tester);
  });

  testWidgets('ohne Meldung und ohne Ungelesenes ist da nichts',
      (tester) async {
    await zeige(tester);
    expect(find.byIcon(Icons.notifications_none), findsNothing);
    expect(find.byType(Material).evaluate().length, greaterThan(0));
    await ruhe(tester);
  });

  testWidgets('nach dem Verblassen bleibt die Glocke stehen', (tester) async {
    // Sonst wäre die Meldung doch wieder weg – nur langsamer.
    await zeige(tester);
    d.hinweis('Verpasst');
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Verpasst'), findsNothing);
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
    await ruhe(tester);
  });
}
