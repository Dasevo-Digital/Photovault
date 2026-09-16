import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/selection_action_bar.dart';

/// Der Knopf, bei dem man sicher sein muss, was man drückt.
///
/// Befund der 15. Prüfrunde: Er trug `Colors.red` – und weisse Schrift
/// darauf ergibt 3,68:1, wo Knopfschrift 4,5:1 braucht. Ausgerechnet
/// dort. `kontrast_test.dart` hält die Zahlen fest; hier steht, dass der
/// Knopf sie auch wirklich benutzt.
void main() {
  for (final (name, thema) in [
    ('hell', buildLightTheme()),
    ('dunkel', buildDarkTheme()),
  ]) {
    testWidgets('der Loeschknopf traegt die Fehlerfarbe ($name)',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        theme: thema,
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Builder(builder: (context) {
          ctx = context;
          return const SizedBox.shrink();
        }),
      ));

      // Nicht abwarten: Der Dialog gibt erst zurück, wenn geklickt wird.
      unawaitedDialog(ctx);
      await tester.pumpAndSettle();

      final knopf = tester.widget<FilledButton>(find.widgetWithText(
          FilledButton, AppTexte.of(ctx).allgLoeschen));
      final schema = thema.colorScheme;
      final zustand = <WidgetState>{};
      expect(knopf.style?.backgroundColor?.resolve(zustand), schema.error,
          reason: 'nicht Colors.red');
      expect(knopf.style?.foregroundColor?.resolve(zustand), schema.onError,
          reason: 'wer nur den Grund tauscht, laesst die Schrift auf der '
              'Vorgabe stehen – und die ist fuer eine andere Farbe gedacht');
    });
  }
}

/// Öffnet den Dialog, ohne auf seine Antwort zu warten.
void unawaitedDialog(BuildContext context) {
  confirmDialog(context, 'Titel', 'Meldung');
}
