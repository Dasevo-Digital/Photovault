// Personen: behobene Befunde aus dem Prüfkatalog der Handy-App (MOB,
// Issue #418): je Befund ein Test, der ohne die Korrektur scheitert.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/personen.dart';
import 'package:photo_vault_mobil/sitzung.dart';

void main() {
  testWidgets('MOB-081 ohne Personen: der Hinweis zeigt, wo das Telefon '
      'selbst benennt', (tester) async {
    final ordner = Directory.systemTemp.createTempSync('pv_personen_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final pfade = (await tester.runAsync(
      () => StoragePaths.forTesting(ordner),
    ))!;
    final sitzung = Sitzung()
      ..db = db
      ..paths = pfade;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(body: Personen(sitzung: sitzung)),
      ),
    );
    // Kein pumpAndSettle: Der Abschnitt „Ohne Namen“ dreht, bis die
    // Datenbank antwortet, und die antwortet nur mit echter Zeit.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    final t = AppTexte.of(tester.element(find.byType(Personen)));
    expect(find.text(t.personenLeer), findsOneWidget);
    // Benannt wird auch auf dem Telefon (MOB-071): unter „Ohne Namen“
    // und im Betrachter, nicht nur am Rechner.
    expect(t.personenLeer, isNot(contains('Rechner')));
    expect(t.personenLeer, contains(t.gesichterOhneNamen));
    expect(t.personenLeer, contains(t.betrachterGesichterZeigen));
    final en = lookupAppTexte(const Locale('en'));
    expect(en.personenLeer, contains(en.gesichterOhneNamen));
    expect(en.personenLeer, contains(en.betrachterGesichterZeigen));
    // Erst abbauen, dann schliesst die Datenbank ohne offene Abfrage.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
