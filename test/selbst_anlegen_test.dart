import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/zeitraum_dialog.dart';

/// Reisen und Aktivitäten von Hand anlegen.
///
/// **Der Weg neben dem Vorschlag, nicht statt seiner.** Erkannt wird nur,
/// was Fotos hergeben – vier Bilder über eine Dreiviertelstunde, zwei
/// Kilometer Weg. Die Radtour mit zwei Bildern fällt durch dieses Raster,
/// ohne deshalb nicht stattgefunden zu haben.
void main() {
  late Directory temp;
  late AppDatabase db;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pv_selbst_');
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  Future<void> foto(String id, DateTime wann,
          {bool gesperrt = false, bool papierkorb = false}) =>
      db.insertAsset(AssetsCompanion.insert(
        id: id,
        relativePath: 'originals/$id.jpg',
        originalFileName: '$id.jpg',
        type: 'IMAGE',
        checksum: id,
        fileCreatedAt: wann,
        importedAt: wann,
        isLocked: Value(gesperrt),
        isTrashed: Value(papierkorb),
      ));

  group('die Aufnahmen eines Zeitraums', () {
    test('einschliesslich beider Randtage', () async {
      // Wer den 14. Juni als letzten Tag nennt, meint auch das Foto von
      // 23:50 Uhr. Ein naiver Vergleich auf Mitternacht verlöre es.
      await foto('frueh', DateTime(2026, 6, 12, 0, 5));
      await foto('spaet', DateTime(2026, 6, 14, 23, 50));
      await foto('davor', DateTime(2026, 6, 11, 23, 59));
      await foto('danach', DateTime(2026, 6, 15, 0, 1));

      final drin = await db.aufnahmenImZeitraum(
          DateTime(2026, 6, 12), DateTime(2026, 6, 14));
      expect(drin.map((a) => a.id).toSet(), {'frueh', 'spaet'});
    });

    test('gesperrte und geloeschte bleiben draussen', () async {
      // Dieselbe Regel wie überall sonst: Ein gesperrtes Foto darf nicht
      // über eine neu angelegte Reise wieder sichtbar werden.
      await foto('offen', DateTime(2026, 6, 13, 10));
      await foto('gesperrt', DateTime(2026, 6, 13, 11), gesperrt: true);
      await foto('papierkorb', DateTime(2026, 6, 13, 12), papierkorb: true);

      final drin = await db.aufnahmenImZeitraum(
          DateTime(2026, 6, 13), DateTime(2026, 6, 13));
      expect(drin.map((a) => a.id).toSet(), {'offen'});
    });

    test('ein Tag ohne Fotos gibt eine leere Liste, keinen Fehler', () async {
      expect(
          await db.aufnahmenImZeitraum(
              DateTime(2026, 1, 1), DateTime(2026, 1, 1)),
          isEmpty);
    });
  });

  group('der Dialog', () {
    Future<Zeitraumangabe?> zeige(WidgetTester tester,
        {bool mitArt = false}) async {
      Zeitraumangabe? ergebnis;
      await tester.pumpWidget(MaterialApp(
        // Mit dem App-Thema und nicht mit dem nackten: Der Dialog faerbt
        // "kein Foto" ueber AppSemantik.warnung, und die Erweiterung
        // haengt am Thema.
        theme: buildLightTheme(),
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => ergebnis = await frageZeitraum(
                    context, titel: 'Anlegen', db: db, mitArt: mitArt),
                child: const Text('los'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('los'));
      await tester.pumpAndSettle();
      return ergebnis;
    }

    testWidgets('ohne Namen bleibt Uebernehmen gesperrt', (tester) async {
      // Ein Zeitraum ohne Namen ergäbe eine Zeile, die in der Liste als
      // leerer Streifen dasteht.
      await zeige(tester);
      final knopf = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Übernehmen'));
      expect(knopf.onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'Harzwoche');
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Übernehmen'))
              .onPressed,
          isNotNull);
    });

    testWidgets('die Zahl der Fotos steht schon im Fenster', (tester) async {
      // Ohne sie legt man eine Reise an und sieht erst danach, dass sie
      // leer ist – und weiss nicht, ob das am Zeitraum liegt.
      final heute = DateTime.now();
      await foto('a', DateTime(heute.year, heute.month, heute.day, 9));
      await foto('b', DateTime(heute.year, heute.month, heute.day, 10));
      await zeige(tester);
      expect(find.text('2 Fotos in diesem Zeitraum'), findsOneWidget);
    });

    testWidgets('leer wird als leer benannt', (tester) async {
      await zeige(tester);
      expect(find.text('Kein Foto in diesem Zeitraum'), findsOneWidget);
    });

    testWidgets('nach der Art wird nur gefragt, wo sie gebraucht wird',
        (tester) async {
      await zeige(tester);
      expect(find.text('Art'), findsNothing, reason: 'eine Reise hat keine');
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      await zeige(tester, mitArt: true);
      expect(find.text('Art'), findsOneWidget);
    });
  });
}
