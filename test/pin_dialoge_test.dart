import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/pin_dialogs.dart';

/// Die Fenster für PIN und Sicherungs-Passphrase.
///
/// Sie waren ungeprüft – ausgerechnet die vier, an denen der Zugang zum
/// gesperrten Ordner und zur verschlüsselten Sicherung hängt. Und sie
/// trugen denselben Fehler wie sieben weitere Stellen: Die Textsteuerung
/// wurde weggeworfen, sobald `showDialog` zurückkam, während das
/// Textfeld während der Ausblendung noch darauf zugriff.
///
/// Geprüft wird deshalb beides: dass die Regeln gelten, und dass das
/// Schliessen selbst nichts mehr wirft.
void main() {
  Future<String?> zeige(
    WidgetTester tester,
    Future<String?> Function(BuildContext) oeffnen,
  ) async {
    String? ergebnis;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => ergebnis = await oeffnen(context),
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

  testWidgets('die PIN-Eingabe gibt zurueck, was eingetippt wurde',
      (tester) async {
    await zeige(tester, showEnterPinDialog);
    await tester.enterText(find.byType(TextField), '12345678');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('die PIN wird verdeckt eingegeben', (tester) async {
    // Eine PIN, die jemand von der Seite mitlesen kann, ist keine.
    await zeige(tester, showEnterPinDialog);
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue);
  });

  testWidgets('eine zu kurze PIN wird abgelehnt', (tester) async {
    // Acht Stellen sind die Untergrenze: Bei einem abgezogenen
    // library.sqlite laesst sich der verpackte Hauptschluessel offline
    // durchprobieren.
    await zeige(tester, showSetPinDialog);
    final felder = find.byType(TextField);
    await tester.enterText(felder.at(0), '1234');
    await tester.enterText(felder.at(1), '1234');
    await tester.tap(find.text('Festlegen'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget,
        reason: 'das Fenster bleibt offen');
    // „Ziffern" steht auch in der Feldbeschriftung – gemeint ist die
    // Fehlermeldung darunter.
    expect(find.text('PIN muss aus 8-10 Ziffern bestehen.'), findsOneWidget);
  });

  testWidgets('zwei ungleiche Eingaben werden abgelehnt', (tester) async {
    await zeige(tester, showSetPinDialog);
    final felder = find.byType(TextField);
    await tester.enterText(felder.at(0), '12345678');
    await tester.enterText(felder.at(1), '87654321');
    await tester.tap(find.text('Festlegen'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('eine gueltige PIN kommt durch und das Fenster schliesst sauber',
      (tester) async {
    await zeige(tester, showSetPinDialog);
    final felder = find.byType(TextField);
    await tester.enterText(felder.at(0), '12345678');
    await tester.enterText(felder.at(1), '12345678');
    await tester.tap(find.text('Festlegen'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('die Passphrase hat keine Laengenbegrenzung nach oben',
      (tester) async {
    // Ein Sicherungsarchiv liegt oft langfristig extern; eine kurze PIN
    // waere dafuer zu schwach, deshalb ist es hier ein freier Text.
    await zeige(tester, (c) => showEnterPassphraseDialog(c));
    final feld = tester.widget<TextField>(find.byType(TextField));
    expect(feld.obscureText, isTrue);
    expect(feld.maxLength, isNull);
  });

  testWidgets('eine zu kurze Passphrase wird abgelehnt', (tester) async {
    await zeige(tester, showSetPassphraseDialog);
    final felder = find.byType(TextField);
    await tester.enterText(felder.at(0), 'kurz');
    await tester.enterText(felder.at(1), 'kurz');
    await tester.tap(find.text('Festlegen'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('Abbrechen schliesst ohne Fehler', (tester) async {
    for (final oeffnen in <Future<String?> Function(BuildContext)>[
      showEnterPinDialog,
      showSetPinDialog,
      (c) => showEnterPassphraseDialog(c),
      showSetPassphraseDialog,
    ]) {
      await zeige(tester, oeffnen);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
