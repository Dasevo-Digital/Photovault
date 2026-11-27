import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/l10n/app_localizations_de.dart';
import 'package:photo_vault/services/hochskalieren.dart';
import 'package:photo_vault/services/restore_queue_service.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/hochskalieren_dialog.dart';

/// Der Dialog des Hochskalierens (#500): Faktoren über den Grenzen sind
/// gesperrt und sagen warum, ohne Modell steht der Weg zu den Einstellungen
/// da und „Starten“ bleibt aus.
void main() {
  final de = AppTexteDe();

  /// Öffnet den Dialog und gibt zurück, was er am Ende liefert.
  Future<int? Function()> oeffne(
    WidgetTester tester, {
    required int? breite,
    required int? hoehe,
    bool modell = true,
    Hochskalierquelle quelle = Hochskalierquelle.entwicklung,
    bool uebergangen = false,
    bool ungespeichert = false,
  }) async {
    // Gross genug, dass alle drei Zeilen ohne Rollen zu sehen sind – sonst
    // träfe ein Tipp auf die unterste die Knöpfe darunter.
    tester.view
      ..physicalSize = const Size(1400, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    int? ergebnis;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => ergebnis = await showDialog<int>(
                  context: context,
                  builder: (_) => HochskalierenDialog(
                    breite: breite,
                    hoehe: hoehe,
                    modellInstalliert: modell,
                    quelle: quelle,
                    restaurierungUebergangen: uebergangen,
                    ungespeichert: ungespeichert,
                  ),
                ),
                child: const Text('auf'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('auf'));
    await tester.pumpAndSettle();
    return () => ergebnis;
  }

  RadioListTile<int> zeile(WidgetTester tester, int faktor) =>
      tester.widget<RadioListTile<int>>(
        find.widgetWithText(RadioListTile<int>, de.hochskalierenFaktor(faktor)),
      );

  FilledButton starten(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton));

  testWidgets('zu grosse Faktoren sind gesperrt und sagen warum', (
    tester,
  ) async {
    // 3× gäbe 180 MP, 4× eine Kante von 20.000 px.
    final ergebnis = await oeffne(tester, breite: 5000, hoehe: 4000);

    expect(find.text(de.hochskalierenQuelle(5000, 4000, 20)), findsOneWidget);
    expect(
      find.text(de.hochskalierenZiel(10000, 8000, 80)),
      findsOneWidget,
      reason: 'die Zielgrösse in Pixeln und Megapixeln',
    );
    expect(zeile(tester, 2).enabled, isTrue);
    expect(zeile(tester, 3).enabled, isFalse);
    expect(zeile(tester, 4).enabled, isFalse);
    expect(
      find.text(de.hochskalierenGesperrtPixel(hochskalierMaxPixel ~/ 1000000)),
      findsOneWidget,
    );
    expect(
      find.text(de.hochskalierenGesperrtKante(hochskalierMaxKante)),
      findsOneWidget,
    );

    // Ein Tipp auf eine gesperrte Zeile ändert die Wahl nicht.
    await tester.tap(find.text(de.hochskalierenFaktor(4)));
    await tester.pump();
    await tester.tap(find.text(de.allgStarten));
    await tester.pumpAndSettle();
    expect(ergebnis(), 2);
  });

  testWidgets('ohne Modell: Hinweis auf die Einstellungen, kein Start', (
    tester,
  ) async {
    await oeffne(tester, breite: 1000, hoehe: 750, modell: false);

    expect(find.text(de.hochskalierenModellFehlt), findsOneWidget);
    expect(de.hochskalierenModellFehlt, contains('Einstellungen → KI-Modelle'));
    expect(starten(tester).onPressed, isNull);
  });

  testWidgets('Gegenprobe: ein kleines Foto darf alles, vorgewählt ist 4×', (
    tester,
  ) async {
    final ergebnis = await oeffne(tester, breite: 1000, hoehe: 750);

    for (final f in hochskalierFaktoren) {
      expect(zeile(tester, f).enabled, isTrue, reason: '$f×');
    }
    expect(find.text(de.hochskalierenModellFehlt), findsNothing);
    expect(find.textContaining('Gesperrt'), findsNothing);

    await tester.tap(find.text(de.allgStarten));
    await tester.pumpAndSettle();
    expect(ergebnis(), 4);
  });

  testWidgets('eine andere Wahl wird übernommen', (tester) async {
    final ergebnis = await oeffne(tester, breite: 1000, hoehe: 750);

    await tester.tap(find.text(de.hochskalierenFaktor(3)));
    await tester.pump();
    await tester.tap(find.text(de.allgStarten));
    await tester.pumpAndSettle();
    expect(ergebnis(), 3);
  });

  testWidgets('unbekannte Grösse: nichts zu wählen', (tester) async {
    await oeffne(tester, breite: null, hoehe: null);

    expect(find.text(de.restaurGrundAufloesung), findsOneWidget);
    expect(find.byType(RadioListTile<int>), findsNothing);
    expect(starten(tester).onPressed, isNull);
  });

  testWidgets('sagt, woraus gerechnet wird, und was nicht zählt', (
    tester,
  ) async {
    await oeffne(
      tester,
      breite: 1000,
      hoehe: 750,
      quelle: Hochskalierquelle.restaurierung,
      ungespeichert: true,
    );
    expect(find.text(de.hochskalierenVorlageRestaurierung), findsOneWidget);
    expect(find.text(de.hochskalierenUngespeichert), findsOneWidget);
    expect(find.text(de.hochskalierenRestaurierungUebergangen), findsNothing);
  });

  testWidgets('eine übergangene Restaurierung wird genannt', (tester) async {
    await oeffne(tester, breite: 1000, hoehe: 750, uebergangen: true);
    expect(find.text(de.hochskalierenRestaurierungUebergangen), findsOneWidget);
  });

  testWidgets('Gegenprobe: ohne Anlass kein Hinweis', (tester) async {
    await oeffne(tester, breite: 1000, hoehe: 750);
    expect(find.text(de.hochskalierenVorlageRestaurierung), findsNothing);
    expect(find.text(de.hochskalierenUngespeichert), findsNothing);
    expect(find.text(de.hochskalierenRestaurierungUebergangen), findsNothing);
  });
}
