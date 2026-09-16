import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/typed_confirm_dialog.dart';

/// Der Bestätigungsdialog für unumkehrbare Aktionen.
///
/// Er war ungeprüft – und trug denselben Fehler wie zehn weitere Stellen
/// dieser App: Die Textsteuerung wurde weggeworfen, sobald `showDialog`
/// zurückkam. Die Ausblendung läuft dann noch, das Textfeld baut sich
/// dabei weiter auf und greift auf eine Steuerung zu, die es nicht mehr
/// gibt. In der Auslieferung sind die Behauptungen abgeschaltet und es
/// fällt nicht auf; hier fällt es sofort auf.
void main() {
  Future<bool?> zeige(WidgetTester tester) async {
    bool? ergebnis;
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
                ergebnis = await showTypedConfirmDialog(
                  context,
                  title: 'Wirklich?',
                  message: 'Das ist endgültig.',
                  confirmationWord: 'LÖSCHEN',
                );
              },
              child: const Text('auf'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('auf'));
    await tester.pumpAndSettle();
    return ergebnis;
  }

  testWidgets('der Knopf bleibt gesperrt, bis das Wort genau stimmt',
      (tester) async {
    await zeige(tester);
    final knopf = find.widgetWithText(FilledButton, 'Endgültig löschen');
    expect(tester.widget<FilledButton>(knopf).onPressed, isNull);

    // Gross- und Kleinschreibung zaehlt – sonst waere die Huerde keine.
    await tester.enterText(find.byType(TextField), 'löschen');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(knopf).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'LÖSCHEN');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(knopf).onPressed, isNotNull);
  });

  testWidgets('das Schliessen wirft keine Steuerung zu frueh weg',
      (tester) async {
    // Der eigentliche Grund fuer diese Datei: Bis hierher stuerzte das
    // Ausblenden im Fehlersuchbetrieb ab.
    await zeige(tester);
    await tester.enterText(find.byType(TextField), 'LÖSCHEN');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Endgültig löschen'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Abbrechen gibt falsch zurueck', (tester) async {
    await zeige(tester);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
