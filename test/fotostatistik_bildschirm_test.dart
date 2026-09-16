import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/familienstatistik_screen.dart';
import 'package:photo_vault/services/familienstatistik.dart';
import 'package:photo_vault/services/fotostatistik.dart';
import 'package:photo_vault/services/stammbaum.dart';
import 'package:photo_vault/services/verwandtschaftsgrad.dart';

/// Die Familienstatistik nach dem Umbau: Die Bilder stehen vorn, die
/// Lebensdaten hinten, und leere Kacheln gibt es nicht mehr.
void main() {
  group('auftritteFuerPersonen', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> bild(String id,
            {bool gesperrt = false, bool papierkorb = false}) =>
        db.into(db.assets).insert(AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.jpg',
              relativePath: 'originals/$id.jpg',
              checksum: 'pruef-$id',
              type: 'IMAGE',
              fileCreatedAt: DateTime(2024, 6, 3),
              importedAt: DateTime(2024),
              isLocked: Value(gesperrt),
              isTrashed: Value(papierkorb),
            ));

    Future<void> gesicht(String assetId, String personId) =>
        db.into(db.faces).insert(FacesCompanion.insert(
              id: '$assetId-$personId',
              assetId: assetId,
              personId: Value(personId),
              boxX: 0,
              boxY: 0,
              boxW: 1,
              boxH: 1,
            ));

    test('gesperrte und geloeschte Aufnahmen bleiben draussen', () async {
      // Derselbe Grundsatz wie bei den Reisen: Was hinter der PIN liegt,
      // darf ausserhalb nicht auftauchen – auch nicht als Saeule in einem
      // Diagramm, die verraet, dass es dort etwas gibt.
      await bild('offen');
      await bild('gesperrt', gesperrt: true);
      await bild('weg', papierkorb: true);
      for (final b in ['offen', 'gesperrt', 'weg']) {
        await gesicht(b, 'anna');
      }

      final treffer = await db.auftritteFuerPersonen({'anna'});
      expect([for (final a in treffer) a.assetId], ['offen']);
    });

    test('nur die angefragten Personen', () async {
      await bild('b1');
      await gesicht('b1', 'anna');
      await gesicht('b1', 'bert');
      expect(await db.auftritteFuerPersonen({'anna'}), hasLength(1));
      expect(await db.auftritteFuerPersonen({'anna', 'bert'}), hasLength(2));
    });

    test('ohne Personen wird gar nicht erst gefragt', () async {
      await bild('b1');
      await gesicht('b1', 'anna');
      expect(await db.auftritteFuerPersonen(const {}), isEmpty);
    });
  });

  group('der Bildschirm', () {
    Familienstatistik ohneLebensdaten() => familienstatistik(
          personen: [
            (
              id: 'anna',
              name: 'Anna',
              geschlecht: Geschlecht.weiblich,
              geburt: DateTime(1990, 3, 1),
              tod: null
            ),
            (
              id: 'bert',
              name: 'Bert',
              geschlecht: Geschlecht.maennlich,
              geburt: null,
              tod: null
            ),
          ],
          netz: Verwandtschaftsnetz(const []),
          fokus: 'anna',
          ereignisse: const [],
        );

    Future<void> zeige(WidgetTester tester, Fotostatistik foto) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: FamilienstatistikScreen(
          statistik: ohneLebensdaten(),
          fokusName: 'Anna',
          foto: foto,
          namen: const {'anna': 'Anna', 'bert': 'Bert'},
        ),
      ));
      await tester.pumpAndSettle();
    }

    Fotostatistik mitBildern() => fotostatistik(
          auftritte: [
            for (var i = 0; i < 5; i++)
              (
                personId: 'anna',
                assetId: 'a$i',
                zeit: DateTime(2020 + i, 6, 1)
              ),
            (personId: 'bert', assetId: 'a0', zeit: DateTime(2020, 6, 1)),
          ],
          betrachtet: {'anna', 'bert'},
          geburt: {'anna': DateTime(1990, 3, 1)},
        );

    testWidgets('die Fotos stehen vor den Lebensdaten', (tester) async {
      await zeige(tester, mitBildern());
      final fotos = tester.getTopLeft(find.text('Auf den Fotos')).dy;
      final leben = tester.getTopLeft(find.text('Aus den Lebensdaten')).dy;
      expect(fotos, lessThan(leben));
    });

    testWidgets('leere Kacheln stehen nicht mehr da, ein Satz erklaert warum',
        (tester) async {
      await zeige(tester, mitBildern());
      // Ohne Sterbe- und Hochzeitsdaten: keine Kachel, sondern ein Satz.
      expect(find.text('Lebensalter'), findsNothing);
      expect(find.text('Heiratsalter'), findsNothing);
      expect(find.textContaining('Photo Vault schätzt sie nicht'),
          findsOneWidget);
    });

    testWidgets('Anzahl, Zeitraum und Alter stehen an der Person',
        (tester) async {
      await zeige(tester, mitBildern());
      final anna = find.ancestor(
          of: find.text('Anna'), matching: find.byType(ListTile));
      expect(anna, findsOneWidget);
      // 2020 bis 2024, fuenf Jahre, 30 bis 34 Jahre alt.
      expect(
          find.descendant(
              of: anna, matching: find.textContaining('2020 bis 2024')),
          findsOneWidget);
      expect(
          find.descendant(
              of: anna, matching: find.textContaining('30 bis 34 Jahre alt')),
          findsOneWidget);
      // Fuenf Aufnahmen, nicht sechs: Berts Bild ist dasselbe wie Annas.
      expect(find.descendant(of: anna, matching: find.text('5')),
          findsOneWidget);
    });

    testWidgets('ohne Geburtsdatum steht kein Alter da', (tester) async {
      await zeige(tester, mitBildern());
      // Bert hat keins – seine Zeile nennt Zeitraum, aber kein Alter.
      final bert = find.ancestor(
          of: find.text('Bert'), matching: find.byType(ListTile));
      expect(bert, findsOneWidget);
      expect(
          find.descendant(
              of: bert, matching: find.textContaining('Jahre alt')),
          findsNothing);
    });

    testWidgets('gemeinsame Auftritte werden gezeigt', (tester) async {
      await zeige(tester, mitBildern());
      expect(find.text('Anna · Bert'), findsOneWidget);
    });

    testWidgets('ohne ein einziges Foto sagt der Bildschirm das',
        (tester) async {
      await zeige(
          tester,
          fotostatistik(
              auftritte: const [], betrachtet: {'anna', 'bert'}));
      expect(find.textContaining('noch niemand auf einem Foto erkannt'),
          findsOneWidget);
      // Die Zahl der Fehlenden waere hier eine Wiederholung: Der Satz
      // sagt schon, dass niemand dabei ist.
      expect(find.textContaining('auf keinem Bild'), findsNothing);
      // Die Lebensdaten stehen trotzdem da – ein Stammbaum ohne Fotos
      // ist immer noch ein Stammbaum.
      expect(find.text('Aus den Lebensdaten'), findsOneWidget);
    });
  });
}
