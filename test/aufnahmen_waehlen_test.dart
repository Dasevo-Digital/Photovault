import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/aufnahmen_waehlen_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';

/// Das Raster, in dem man die Fotos einer Reise oder Aktivität anhakt.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState bib;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_wahl_');
    db = AppDatabase(NativeDatabase.memory());
    final pfade = await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')));
    bib = LibraryState()
      ..db = db
      ..paths = pfade
      ..backupService = BackupService(db, pfade);
    // Drei am 14. Juni, eines eine Woche vorher.
    for (final (id, tag, stunde) in [
      ('a0', 14, 9),
      ('a1', 14, 10),
      ('a2', 14, 11),
      ('alt', 7, 9),
    ]) {
      await db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'c-$id',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 6, tag, stunde),
            importedAt: DateTime(2026),
          ));
    }
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  /// Ein Behälter für das Ergebnis: Der Bildschirm gibt es erst
  /// zurück, wenn er verlassen wird – lange nachdem [zeige] fertig ist.
  final ergebnisse = <String, Set<String>?>{};

  Future<void> zeige(WidgetTester tester,
      {required Set<String> vorhanden}) async {
    ergebnisse.clear();
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
                ergebnisse['wahl'] = await Navigator.of(context).push<Set<String>>(
                  MaterialPageRoute(
                    builder: (_) => AufnahmenWaehlenScreen(
                      library: bib,
                      titel: 'Fotos',
                      vorhanden: vorhanden,
                      von: DateTime(2026, 6, 14, 9),
                      bis: DateTime(2026, 6, 14, 11),
                    ),
                  ),
                );
              },
              child: const Text('auf'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('auf'));
    // Bis der Übergang durch ist: Während die Seite hereinschiebt,
    // liegt ihre Leiste noch neben dem Fenster, und ein Tipp darauf
    // ginge ins Leere.
    await tester.pumpAndSettle();
  }

  Future<void> raeumeAb(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('der Zeitraum ist die Voreinstellung, nicht die Grenze',
      (tester) async {
    await zeige(tester, vorhanden: {'a0', 'a1'});
    // Drei aus dem Zeitraum – das alte Foto ist nicht dabei.
    expect(find.byType(AssetThumbnailTile), findsNWidgets(3));

    await tester.tap(find.text('Alle Fotos'));
    await tester.pumpAndSettle();
    expect(find.byType(AssetThumbnailTile), findsNWidgets(4));
    await raeumeAb(tester);
  });

  testWidgets('Antippen hakt an und wieder ab', (tester) async {
    await zeige(tester, vorhanden: {'a0'});
    expect(find.textContaining('1 Foto gewählt'), findsOneWidget);

    await tester.tap(find.byType(AssetThumbnailTile).at(1));
    await tester.pump();
    expect(find.textContaining('2 Fotos gewählt'), findsOneWidget);

    await tester.tap(find.byType(AssetThumbnailTile).at(1));
    await tester.pump();
    expect(find.textContaining('1 Foto gewählt'), findsOneWidget);
    await raeumeAb(tester);
  });

  testWidgets('was nicht im Bild steht, fällt nicht heraus', (tester) async {
    // DIE Eigenschaft. Das alte Foto gehört dazu, liegt aber ausserhalb
    // des gezeigten Zeitraums. Würde die Ansicht ihre Auswahl aus dem
    // Sichtbaren bilden, verschwände es beim Sichern still.
    await zeige(tester, vorhanden: {'a0', 'alt'});
    expect(find.textContaining('2 Fotos gewählt'), findsOneWidget);
    expect(find.textContaining('1 davon ausserhalb'), findsOneWidget);

    await tester.tap(find.text('Fertig'));
    await tester.pumpAndSettle();
    expect(ergebnisse['wahl'], {'a0', 'alt'});
    await raeumeAb(tester);
  });

  testWidgets('Zurück ohne Fertig gibt nichts zurück', (tester) async {
    // Ein Zurück darf die Zuordnung nicht leeren: Der Aufrufer bekommt
    // `null` und lässt alles, wie es war.
    await zeige(tester, vorhanden: {'a0'});
    await tester.tap(find.byType(AssetThumbnailTile).first);
    await tester.pump();
    // Nicht `pageBack()`: Das sucht den Knopf über seinen englischen
    // Kurzhinweis, und diese Ansicht läuft auf Deutsch.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(ergebnisse['wahl'], isNull);
    await raeumeAb(tester);
  });

  group('die Ausgangsmenge kommt aus der Datenbank', () {
    /// **Zwei Wege, auf denen Zuordnungen still verschwanden.**
    ///
    /// Beim Sichern wird die Zuordnungstabelle geleert und mit genau der
    /// zurueckgegebenen Menge neu geschrieben. Wer diese Menge aus einer
    /// ANSICHT aufbaut statt aus der gespeicherten Zuordnung, verliert
    /// alles, was die Ansicht nicht zeigt - und zwar endgueltig, ohne
    /// dass jemand etwas angetippt haette.
    ///
    /// 1. `aufnahmenDerAktivitaet` laesst weg, was im Papierkorb liegt
    ///    oder gesperrt ist.
    /// 2. Sie ist ausserdem leer, solange `_laden()` laeuft - und die
    ///    Knoepfe der Titelleiste standen schon da.
    ///
    /// Der zweite Fall erklaert einen gemeldeten: Eine Aktivitaet mit
    /// vier Fotos zeigte "1 Foto gewaehlt", und ein Haken haette die
    /// anderen drei geloescht.
    late AppDatabase d2;

    setUp(() async {
      d2 = db;
      await d2.into(d2.aktivitaeten).insert(AktivitaetenCompanion.insert(
            id: 'akt',
            name: 'Wanderung',
            art: 'wanderung',
            von: DateTime(2026, 6, 14, 9),
            bis: DateTime(2026, 6, 14, 11),
            angelegtAm: DateTime(2026, 6, 14),
          ));
    });

    test('sie enthaelt auch, was der Bildschirm nicht zeigen darf', () async {
      await (d2.update(d2.assets)..where((t) => t.id.equals('a1')))
          .write(const AssetsCompanion(isTrashed: Value(true)));
      await (d2.update(d2.assets)..where((t) => t.id.equals('a2')))
          .write(const AssetsCompanion(isLocked: Value(true)));
      await d2.setzeAufnahmenDerAktivitaet('akt', {'a0', 'a1', 'a2'});

      // Was der Bildschirm zeigen kann:
      final sichtbar = await d2.aufnahmenDerAktivitaet('akt');
      expect(sichtbar.map((a) => a.id), ['a0']);

      // Was wirklich zugeordnet ist - und was der Auswahlbildschirm
      // deshalb als Ausgangsmenge bekommen muss:
      expect(await d2.zuordnungenDerAktivitaet('akt'), {'a0', 'a1', 'a2'});
    });

    test('Fertig ohne Aenderung laesst alles stehen', () async {
      await (d2.update(d2.assets)..where((t) => t.id.equals('a1')))
          .write(const AssetsCompanion(isTrashed: Value(true)));
      await d2.setzeAufnahmenDerAktivitaet('akt', {'a0', 'a1'});

      // Der Weg, den der Detailbildschirm jetzt geht.
      final vorher = await d2.zuordnungenDerAktivitaet('akt');
      await d2.setzeAufnahmenDerAktivitaet('akt', vorher);

      expect(await d2.zuordnungenDerAktivitaet('akt'), {'a0', 'a1'},
          reason: 'ohne Antippen darf nichts verschwinden');
    });

    test('ein einziger Haken loescht die uebrigen nicht', () async {
      await d2.setzeAufnahmenDerAktivitaet('akt', {'a0', 'a1', 'a2'});

      // Der gemeldete Fall: Der Nutzer hakt EIN Foto zusaetzlich an.
      final vorher = await d2.zuordnungenDerAktivitaet('akt');
      await d2.setzeAufnahmenDerAktivitaet('akt', {...vorher, 'alt'});

      expect(await d2.zuordnungenDerAktivitaet('akt'),
          {'a0', 'a1', 'a2', 'alt'});
    });

    test('dasselbe fuer Reisen', () async {
      await d2.into(d2.reisen).insert(ReisenCompanion.insert(
            id: 'r1',
            name: 'Reise',
            von: DateTime(2026, 6, 14, 9),
            bis: DateTime(2026, 6, 14, 11),
            angelegtAm: DateTime(2026, 6, 14),
          ));
      await (d2.update(d2.assets)..where((t) => t.id.equals('a1')))
          .write(const AssetsCompanion(isTrashed: Value(true)));
      await d2.setzeAufnahmenDerReise('r1', {'a0', 'a1'});

      expect((await d2.aufnahmenDerReise('r1')).map((a) => a.id), ['a0']);
      expect(await d2.zuordnungenDerReise('r1'), {'a0', 'a1'});
    });

    test('und die Bildschirme holen sie sich auch von dort', () {
      // Die Abfrage allein hilft nichts, wenn der Bildschirm weiter aus
      // seiner Anzeigeliste baut - genau das war der Fehler. Geprueft
      // wird deshalb die Verdrahtung, wie in karten_kachelspeicher_test.
      for (final (pfad, erwartet) in [
        ('lib/screens/aktivitaet_detail_screen.dart',
            'zuordnungenDerAktivitaet'),
        ('lib/screens/reise_detail_screen.dart', 'zuordnungenDerReise'),
      ]) {
        final quelle = File(pfad).readAsStringSync();
        expect(quelle, contains(erwartet),
            reason: '$pfad baut die Ausgangsmenge nicht aus der Datenbank');
        expect(quelle, isNot(contains('final vorher = {for (final a in _aufnahmen)')),
            reason: '$pfad baut sie noch aus der Anzeigeliste');
      }
    });
  });
}
