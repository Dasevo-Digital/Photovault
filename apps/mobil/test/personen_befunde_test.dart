// Personen: behobene Befunde aus dem Prüfkatalog der Handy-App (MOB,
// Issue #418): je Befund ein Test, der ohne die Korrektur scheitert.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/personen.dart';
import 'package:photo_vault_mobil/sitzung.dart';

/// Zwei unbenannte Gesichter, die Anna ähneln – „Ohne Namen“ zeigt sie
/// als Gruppe „Anna?“. Dazu Bert, dem sie inzwischen gehören könnten.
Future<(Sitzung, AppDatabase)> _mitGruppe(WidgetTester tester) async {
  final ordner = Directory.systemTemp.createTempSync('pv_personen_');
  addTearDown(() => ordner.deleteSync(recursive: true));
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  Uint8List vektor(double x) {
    final v = Float32List(128);
    final laenge = math.sqrt(x * x + 1);
    v[0] = x / laenge;
    v[1] = 1 / laenge;
    return Uint8List.view(v.buffer);
  }

  await tester.runAsync(() async {
    for (final id in ['g1', 'g2', 'g3']) {
      await db.insertAsset(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'pruef-$id',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2025),
          importedAt: DateTime(2026),
        ),
      );
    }
    await db.fuehreAus(const PersonAnlegen('anna', 'Anna'));
    await db.fuehreAus(const PersonAnlegen('bert', 'Bert'));
    for (final (id, aufnahme, person, x) in [
      ('fa', 'g1', 'anna', 0.05),
      ('f1', 'g2', null, 0.0),
      ('f2', 'g3', null, 0.02),
    ]) {
      await db
          .into(db.faces)
          .insert(
            FacesCompanion.insert(
              id: id,
              assetId: aufnahme,
              personId: Value(person),
              boxX: 0.1,
              boxY: 0.1,
              boxW: 0.2,
              boxH: 0.2,
              embedding: Value(vektor(x)),
            ),
          );
    }
  });
  final pfade = (await tester.runAsync(() => StoragePaths.forTesting(ordner)))!;
  return (
    Sitzung()
      ..db = db
      ..paths = pfade,
    db,
  );
}

Future<void> _bis(WidgetTester tester, bool Function() bedingung) async {
  for (var i = 0; i < 30 && !bedingung(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
}

Widget _app(Sitzung sitzung) => MaterialApp(
  locale: const Locale('de'),
  localizationsDelegates: AppTexte.localizationsDelegates,
  supportedLocales: AppTexte.supportedLocales,
  home: Scaffold(body: Personen(sitzung: sitzung)),
);

Future<Map<String, (String?, bool)>> _gesichter(
  WidgetTester tester,
  AppDatabase db,
) async => {
  for (final f in (await tester.runAsync(() => db.allFaces()))!)
    f.id: (f.personId, f.isIgnored),
};

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

  testWidgets('#454 eine veraltete Gruppe unter „Ohne Namen“: „Beiseite“ '
      'nimmt inzwischen benannten Gesichtern nicht die Person', (tester) async {
    final (sitzung, db) = await _mitGruppe(tester);
    await tester.pumpWidget(_app(sitzung));
    await _bis(tester, () => find.text('Anna?').evaluate().isNotEmpty);
    final t = AppTexte.of(tester.element(find.byType(Personen)));
    await tester.tap(find.text('Anna?'));
    await tester.pumpAndSettle();
    expect(find.text(t.gesichterBeiseite), findsOneWidget);

    // Während das Blatt offen ist, benennt sie jemand anderswo als Bert.
    await tester.runAsync(
      () => db.fuehreAus(const GesichterZuordnen(['f1', 'f2'], 'bert')),
    );
    await tester.tap(find.text(t.gesichterBeiseite));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    final f = await _gesichter(tester, db);
    expect(f['f1'], ('bert', false));
    expect(f['f2'], ('bert', false));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('#454 „Das ist Anna“, nachdem Anna in Bert aufgegangen ist: '
      'die Gesichter landen auf keiner Kennung ohne Person', (tester) async {
    final (sitzung, db) = await _mitGruppe(tester);
    await tester.pumpWidget(_app(sitzung));
    await _bis(tester, () => find.text('Anna?').evaluate().isNotEmpty);
    await tester.tap(find.text('Anna?'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => db.fuehreAus(
        const PersonenZusammenfuehren(behalten: 'bert', entfernen: 'anna'),
      ),
    );
    await tester.tap(find.text('Das ist Anna'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    final f = await _gesichter(tester, db);
    expect(f['f1'], (null, false));
    expect(f['f2'], (null, false));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('#454 zurück auf der Personenseite: „Ohne Namen“ zeigt keine '
      'Gruppe mehr, die inzwischen benannt ist', (tester) async {
    final (sitzung, db) = await _mitGruppe(tester);
    await tester.pumpWidget(_app(sitzung));
    await _bis(tester, () => find.text('Anna?').evaluate().isNotEmpty);
    final t = AppTexte.of(tester.element(find.byType(Personen)));
    expect(find.text(t.gesichterOhneNamen), findsOneWidget);

    // Eine andere Seite darüber (etwa eine Person mit „Weitere Fotos“);
    // dort werden die beiden Anna zugeordnet.
    Navigator.of(
      tester.element(find.byType(Personen)),
    ).push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => db.fuehreAus(const GesichterZuordnen(['f1', 'f2'], 'anna')),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
    await tester.pumpAndSettle();
    await _bis(
      tester,
      () => find.text(t.gesichterOhneNamen).evaluate().isEmpty,
    );
    expect(find.text('Anna?'), findsNothing);
    expect(find.text(t.gesichterOhneNamen), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));
  });
}
