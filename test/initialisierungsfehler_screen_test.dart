import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/initialisierungsfehler_screen.dart';

void main() {
  testWidgets('Startfehler zeigt Einzelheiten und lässt sich wiederholen', (tester) async {
    var versuche = 0;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: InitialisierungsfehlerScreen(
        fehler: 'database is locked',
        erneutVersuchen: () async => versuche++,
      ),
    ));
    final t = AppTexte.of(tester.element(find.byType(Scaffold)));

    expect(find.text(t.startFehlerTitel), findsOneWidget);
    expect(find.text('database is locked'), findsOneWidget);
    await tester.tap(find.text(t.startFehlerErneut));
    await tester.pump();

    expect(versuche, 1);
  });
}
