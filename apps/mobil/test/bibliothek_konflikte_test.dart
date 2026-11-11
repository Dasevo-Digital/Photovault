import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/bibliothek.dart';
import 'package:photo_vault_mobil/sitzung.dart';

/// Der Punkt am Reiter „Bibliothek“ zeigt auf offene Fälle unter
/// „Änderungen und Konflikte“ (#340). Die Seite muss dann den Weg dorthin
/// zeigen (#366) – vorher lag er nur hinter dem Kontokreis.
void main() {
  Future<Sitzung> sitzung(WidgetTester tester, int faelle) async {
    final ordner = Directory.systemTemp.createTempSync('pv_konflikte_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final pfade = (await tester.runAsync(
      () => StoragePaths.forTesting(ordner),
    ))!;
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final verbindung = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: MockClient((_) async => http.Response('', 404)),
    );
    return Sitzung()
      ..db = db
      ..paths = pfade
      ..abgleich = Abgleich(db, verbindung)
      ..abgleichszustand = Abgleichszustand(
        erreichbar: true,
        ausstehend: 0,
        faelle: faelle,
      );
  }

  Future<AppTexte> zeige(WidgetTester tester, Sitzung s) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(body: Bibliothek(sitzung: s)),
      ),
    );
    await tester.pump();
    return AppTexte.of(tester.element(find.byType(Bibliothek)));
  }

  // Der Strom der Personen schliesst mit einem Timer – vor dem Ende
  // abbauen, sonst steht er beim Aufräumen noch aus.
  Future<void> abbauen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('mit offenen Fällen steht der Weg oben', (tester) async {
    final t = await zeige(tester, await sitzung(tester, 2));
    expect(find.text(t.syncUebersicht), findsOneWidget);
    expect(find.text(t.syncZuEntscheiden(2)), findsOneWidget);
    await abbauen(tester);
  });

  testWidgets('ohne Fälle kein Hinweis', (tester) async {
    final t = await zeige(tester, await sitzung(tester, 0));
    expect(find.text(t.syncUebersicht), findsNothing);
    await abbauen(tester);
  });
}
