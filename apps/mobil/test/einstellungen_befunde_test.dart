// Einstellungen der Bibliothek: behobene Befunde aus dem Prüfkatalog der
// Handy-App (MOB, Issue #418): je Befund ein Test, der ohne die Korrektur
// scheitert.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/bibliothekseinstellungen.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/einstellungen.dart';
import 'package:photo_vault_mobil/sitzung.dart';

void main() {
  Future<(Sitzung, AppDatabase)> sitzung(WidgetTester tester) async {
    final ordner = Directory.systemTemp.createTempSync('pv_einst_befund_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final pfade = (await tester.runAsync(
      () => StoragePaths.forTesting(ordner),
    ))!;
    return (
      Sitzung()
        ..db = db
        ..paths = pfade,
      db,
    );
  }

  Future<AppTexte> oeffne(WidgetTester tester, Sitzung s) async {
    tester.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(body: Einstellungen(sitzung: s)),
                ),
              ),
              child: const Text('auf'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('auf'));
    await tester.pumpAndSettle();
    return AppTexte.of(tester.element(find.byType(Einstellungen)));
  }

  Finder tagesfeld(AppTexte t) => find.descendant(
    of: find.ancestor(of: find.text(t.einstNach), matching: find.byType(Row)),
    matching: find.byType(TextField),
  );

  testWidgets('MOB-158 Frist eingetippt und die Seite verlassen: sie gilt '
      'trotzdem', (tester) async {
    final (s, db) = await sitzung(tester);
    final t = await oeffne(tester, s);
    await tester.enterText(tagesfeld(t), '14');
    await tester.pump();
    // Zurück, ohne zu bestätigen.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.byType(Einstellungen), findsNothing);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect((await bibliothekseinstellungen(db)).papierkorbTage, 14);
  });

  testWidgets('MOB-158 Frist eingetippt und woanders hingetippt: gespeichert', (
    tester,
  ) async {
    final (s, db) = await sitzung(tester);
    final t = await oeffne(tester, s);
    await tester.tap(tagesfeld(t));
    await tester.enterText(tagesfeld(t), '21');
    await tester.pump();
    // Der Fokus geht, ohne Eingabetaste (die Zifferntastatur hat keine).
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect((await bibliothekseinstellungen(db)).papierkorbTage, 21);
    expect(find.text(t.einstGespeichert), findsOneWidget);
  });
}
