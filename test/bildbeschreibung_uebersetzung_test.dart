import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/widgets/asset_info_sheet.dart';

/// Die deutschen KI-Bildunterschriften wurden zwar erzeugt und mitdurchsucht,
/// aber nirgends angezeigt – die Info-Ansicht zeigte immer das englische
/// Original. Und wer die Übersetzung erst nachträglich einschaltete, hatte
/// keinen Weg, die vorhandenen Sätze zu übertragen, ohne das
/// Beschreibungsmodell über die ganze Bibliothek erneut laufen zu lassen.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late StoragePaths paths;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_caption_de_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<AssetData> lege(String id,
      {String? englisch, String? deutsch, bool gesperrt = false}) async {
    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.heic',
          relativePath: 'originals/$id.heic',
          checksum: id,
          fileCreatedAt: DateTime(2024, 5, 1),
          importedAt: DateTime(2024, 5, 2),
          type: 'IMAGE',
          aiCaption: Value(englisch),
          aiCaptionDe: Value(deutsch),
          aiCaptionScanned: Value(englisch != null),
          isLocked: Value(gesperrt),
        ));
    return (await db.assetById(id))!;
  }

  test('zu übersetzen ist genau das, was englisch vorliegt und noch kein Deutsch hat',
      () async {
    await lege('a', englisch: 'a dog on a beach');
    await lege('b', englisch: 'a cat', deutsch: 'eine Katze');
    await lege('c'); // noch gar keine Beschreibung
    await lege('d', englisch: ''); // leerer Satz zählt nicht als vorhanden
    await lege('e', englisch: 'a locked photo', gesperrt: true);

    final offen = await db.assetsForCaptionTranslation();
    expect(offen.map((a) => a.id), ['a']);

    // Die Zählung muss exakt zur Liste passen – dieselbe Zusicherung wie für
    // alle anderen Aufgaben (siehe background_task_counts_test.dart).
    expect(await db.countCaptionTranslation(), 1);

    // Nach einem Modellwechsel will man alles neu übersetzen.
    final alle = await db.assetsForCaptionTranslation(alle: true);
    expect(alle.map((a) => a.id).toList()..sort(), ['a', 'b']);
  });

  test('setAiCaptionDe lässt das englische Original und das Merkmal unberührt', () async {
    await lege('a', englisch: 'a dog on a beach');
    await db.setAiCaptionDe('a', 'ein Hund am Strand');

    final nachher = (await db.assetById('a'))!;
    expect(nachher.aiCaptionDe, 'ein Hund am Strand');
    expect(nachher.aiCaption, 'a dog on a beach',
        reason: 'das Original bleibt, sonst wäre ein Abschalten der '
            'Übersetzung nur über einen neuen Modelldurchlauf rückgängig zu machen');
    expect(nachher.aiCaptionScanned, isTrue);
    expect(await db.countCaptionTranslation(), 0);
  });

  Future<void> zeigeInfo(WidgetTester tester, AssetData asset, Locale sprache) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: sprache,
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Scaffold(
        body: AssetInfoSheet(
          asset: asset,
          db: db,
          paths: paths,
          onUpdated: (_) {},
          onClose: () {},
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('bei deutscher Oberfläche steht die deutsche Fassung da', (tester) async {
    final asset = await lege('a', englisch: 'a dog on a beach', deutsch: 'ein Hund am Strand');
    await zeigeInfo(tester, asset, const Locale('de'));

    expect(find.text('ein Hund am Strand'), findsOneWidget);
    expect(find.text('a dog on a beach'), findsNothing);
    expect(find.text('KI-Beschreibung'), findsOneWidget);
  });

  testWidgets('ohne Übersetzung steht das Original da, erkennbar an EN', (tester) async {
    final asset = await lege('a', englisch: 'a dog on a beach');
    await zeigeInfo(tester, asset, const Locale('de'));

    expect(find.text('a dog on a beach'), findsOneWidget);
    // Welche Sprache im Feld steht, sagt der hervorgehobene der beiden
    // Umschaltknöpfe – deshalb braucht die Beschriftung es nicht mehr zu
    // wiederholen.
    final en = tester.widget<Text>(find.text('EN'));
    final de = tester.widget<Text>(find.text('DE'));
    expect(en.style?.fontWeight, FontWeight.w700);
    expect(de.style?.fontWeight, FontWeight.w400);
  });

  testWidgets('bei englischer Oberfläche bleibt es beim Original', (tester) async {
    final asset = await lege('a', englisch: 'a dog on a beach', deutsch: 'ein Hund am Strand');
    await zeigeInfo(tester, asset, const Locale('en'));

    expect(find.text('a dog on a beach'), findsOneWidget);
    expect(find.text('ein Hund am Strand'), findsNothing);
  });

  group('von Hand ändern', () {
    test('ein geänderter Satz wird von den Nachholvorgängen nicht angefasst', () async {
      await lege('a', englisch: 'a dog on a beach');
      expect(await db.countCaptionBackfill(), 0);
      expect((await db.assetsForCaptionBackfill(alle: true)).map((x) => x.id), ['a']);
      expect(await db.countCaptionTranslation(), 1);

      await db.setAiCaptionVonHand('a', 'ein Hund am Strand', deutsch: true);

      final nachher = (await db.assetById('a'))!;
      expect(nachher.aiCaptionDe, 'ein Hund am Strand');
      expect(nachher.aiCaption, 'a dog on a beach', reason: 'das Original bleibt stehen');
      expect(nachher.aiCaptionEdited, isTrue);

      // Das ist der Punkt: „Alle Fotos" ist für einen Modellwechsel gedacht,
      // nicht zum Wegwerfen getippter Sätze.
      expect(await db.assetsForCaptionBackfill(alle: true), isEmpty);
      expect(await db.countCaptionTranslation(), 0);
      expect(await db.assetsForCaptionTranslation(alle: true), isEmpty);
    });

    test('das Leeren beider Felder gibt das Foto wieder frei', () async {
      await lege('a', englisch: 'a dog on a beach');
      await db.setAiCaptionVonHand('a', 'ein Hund am Strand', deutsch: true);
      await db.setAiCaptionVonHand('a', '', deutsch: true);
      expect((await db.assetById('a'))!.aiCaptionEdited, isTrue,
          reason: 'die englische Fassung steht ja noch');

      await db.setAiCaptionVonHand('a', '   ', deutsch: false);

      final leer = (await db.assetById('a'))!;
      expect(leer.aiCaption, isNull);
      expect(leer.aiCaptionDe, isNull);
      expect(leer.aiCaptionEdited, isFalse);
      expect(leer.aiCaptionScanned, isFalse);
      // Ohne eigenen Knopf zum Zurücknehmen: leer heisst „mach du wieder".
      expect(await db.countCaptionBackfill(), 1);
    });

    test('eine von Hand geschriebene Fassung zählt als vorhanden', () async {
      await lege('a');
      expect(await db.countCaptionBackfill(), 1);

      await db.setAiCaptionVonHand('a', 'ein Hund am Strand', deutsch: true);

      final nachher = (await db.assetById('a'))!;
      expect(nachher.aiCaptionScanned, isTrue,
          reason: 'sonst stünde das Foto weiter unter „Wartend", obwohl da etwas steht');
      expect(await db.countCaptionBackfill(), 0);
    });

    testWidgets('die Kopfzeile läuft auch im schmalen Bedienfeld nicht über',
        (tester) async {
      // Das Info-Bedienfeld sitzt seitlich in der Vollbildansicht und ist
      // dort schmal; die Beschriftung „KI-Beschreibung, von Hand geändert"
      // steht neben zwei Umschaltknöpfen.
      await lege('a', englisch: 'a dog on a beach', deutsch: 'ein Hund');
      await db.setAiCaptionVonHand('a', 'ein Hund am Strand', deutsch: true);
      final geaendert = (await db.assetById('a'))!;

      tester.view.physicalSize = const Size(320, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: AssetInfoSheet(
            asset: geaendert,
            db: db,
            paths: paths,
            onUpdated: (_) {},
            onClose: () {},
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
      expect(find.text('DE'), findsOneWidget);
      expect(find.text('EN'), findsOneWidget);
    });

    testWidgets('das Feld speichert beim Verlassen und der Schalter holt das Original',
        (tester) async {
      final asset = await lege('a', englisch: 'a dog on a beach', deutsch: 'ein Hund');
      await zeigeInfo(tester, asset, const Locale('de'));

      await tester.enterText(find.text('ein Hund'), 'ein Hund am Strand');
      // Speichern hängt am Verlieren des Fokus, wie beim Freitext darüber.
      await tester.tap(find.text('EN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect((await db.assetById('a'))!.aiCaptionDe, 'ein Hund am Strand');
      // Und der Schalter zeigt jetzt das englische Original.
      expect(find.text('a dog on a beach'), findsOneWidget);
      expect(find.text('KI-Beschreibung, von Hand geändert'), findsOneWidget);
    });
  });
}
