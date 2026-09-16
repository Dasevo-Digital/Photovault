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
import 'package:photo_vault/services/textstellen.dart';
import 'package:photo_vault/widgets/textrahmen.dart';

/// Der erkannte Text lag bis Schema 60 ausschliesslich in der Datenbank und
/// war ausschliesslich durchsuchbar – 2406 von 7988 Aufnahmen trugen einen
/// Text, den niemand lesen konnte, und niemand sah, wo im Bild er steht.
/// Diese Prüfungen decken die Ablage der Stellen und den Nachlauf ab, der die
/// schon gescannten Fotos wieder hervorholt.

void main() {
  group('Ablage der Stellen', () {
    test('Rundlauf erhält Text und Rechteck', () {
      final vorher = [
        const Textstelle(text: 'Straße des 17. Juni', links: 0.1, oben: 0.2, breite: 0.5, hoehe: 0.05),
        const Textstelle(text: '135', links: 0.1, oben: 0.3, breite: 0.1, hoehe: 0.04),
      ];
      final nachher = textstellenAusJson(textstellenNachJson(vorher));
      expect(nachher.length, 2);
      expect(nachher.first.text, 'Straße des 17. Juni');
      expect(nachher.first.links, closeTo(0.1, 1e-9));
      expect(nachher.first.breite, closeTo(0.5, 1e-9));
      expect(nachher.last.text, '135');
    });

    test('vier Nachkommastellen genügen und werden eingehalten', () {
      final json = textstellenNachJson([
        const Textstelle(text: 'x', links: 0.123456789, oben: 0, breite: 1, hoehe: 1),
      ]);
      expect(json.contains('0.1235'), isTrue, reason: json);
      expect(json.contains('123456'), isFalse, reason: json);
    });

    test('Werte ausserhalb von 0..1 werden beschnitten', () {
      final zurueck = textstellenAusJson(textstellenNachJson([
        const Textstelle(text: 'x', links: -0.4, oben: 1.7, breite: 0.2, hoehe: 0.2),
      ]));
      expect(zurueck.single.links, 0.0);
      expect(zurueck.single.oben, 1.0);
    });

    test('kaputte Ablage ergibt eine leere Liste, keine Ausnahme', () {
      // Eine Anzeige darf an einer unlesbaren Zeichenkette nicht scheitern –
      // ein Foto ohne Kästchen ist richtig, ein Foto gar nicht zu zeigen wäre
      // falsch.
      expect(textstellenAusJson('kein json'), isEmpty);
      expect(textstellenAusJson('{"nicht":"eine liste"}'), isEmpty);
      expect(textstellenAusJson('[{"t":"ohne masse"}]'), isEmpty);
      expect(textstellenAusJson(null), isEmpty);
      expect(textstellenAusJson(''), isEmpty);
    });

    test('einzelne kaputte Einträge werfen die guten nicht mit weg', () {
      final zurueck = textstellenAusJson(
          '[{"t":"gut","x":0,"y":0,"b":1,"h":1},{"t":"kaputt"},17]');
      expect(zurueck.length, 1);
      expect(zurueck.single.text, 'gut');
    });

    test('textAusStellen ergibt genau das, was ocrText immer enthielt', () {
      expect(
        textAusStellen([
          const Textstelle(text: 'erste', links: 0, oben: 0, breite: 1, hoehe: 1),
          const Textstelle(text: '', links: 0, oben: 0, breite: 1, hoehe: 1),
          const Textstelle(text: 'zweite', links: 0, oben: 0, breite: 1, hoehe: 1),
        ]),
        'erste\nzweite',
      );
    });
  });

  group('Was die Texterkennung noch vor sich hat', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> lege(
      String id, {
      String? text,
      String? boxen,
      bool gescannt = false,
      bool gesperrt = false,
    }) async {
      await db.insertAsset(AssetsCompanion.insert(
        id: id,
        relativePath: 'originals/$id.jpg',
        originalFileName: '$id.jpg',
        type: 'IMAGE',
        fileSizeBytes: const Value(10),
        checksum: id,
        fileCreatedAt: DateTime(2026, 8, 1),
        importedAt: DateTime(2026, 8, 1),
        ocrText: Value(text),
        ocrBoxen: Value(boxen),
        ocrScanned: Value(gescannt),
        isLocked: Value(gesperrt),
      ));
    }

    test('nie gescannt kommt dran', () async {
      await lege('neu');
      expect([for (final a in await db.assetsForOcrBackfill()) a.id], ['neu']);
      expect(await db.countOcrBackfill(), 1);
    });

    test('gescannt mit Text, aber ohne Stellen kommt erneut dran', () async {
      // Der eigentliche Punkt: Ohne diesen Fall blieben alle vor Schema 60
      // erkannten Texte für immer ohne Kästchen, denn ocrScanned steht bei
      // ihnen längst auf wahr.
      await lege('alt', text: 'Bahnhof', gescannt: true);
      expect([for (final a in await db.assetsForOcrBackfill()) a.id], ['alt']);
    });

    test('gescannt mit Text UND Stellen ist fertig', () async {
      await lege('fertig', text: 'Bahnhof', boxen: '[]', gescannt: true);
      expect(await db.assetsForOcrBackfill(), isEmpty);
      expect(await db.countOcrBackfill(), 0);
    });

    test('gescannt ohne Text bleibt aussen vor', () async {
      // Über fünftausend Aufnahmen dieser Bibliothek enthalten keinen Text.
      // Sie erneut durchzurechnen kostet Stunden und ergibt wieder nichts.
      await lege('leer', text: '', gescannt: true);
      expect(await db.assetsForOcrBackfill(), isEmpty);
    });

    test('gesperrte Fotos bleiben aussen vor, auch im neuen Fall', () async {
      await lege('tresor', text: 'geheim', gescannt: true, gesperrt: true);
      expect(await db.assetsForOcrBackfill(), isEmpty);
    });

    test('setOcrResult legt Text und Stellen zusammen ab', () async {
      await lege('x');
      final stellen = [
        const Textstelle(text: 'Kino', links: 0.2, oben: 0.3, breite: 0.4, hoehe: 0.1),
      ];
      await db.setOcrResult('x', textAusStellen(stellen),
          boxen: textstellenNachJson(stellen));
      final a = (await db.assetById('x'))!;
      expect(a.ocrText, 'Kino');
      expect(a.ocrScanned, isTrue);
      expect(textstellenAusJson(a.ocrBoxen).single.text, 'Kino');
    });
  });

  group('Info-Ansicht', () {
    late Directory tempRoot;
    late AppDatabase db;
    late StoragePaths paths;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('pv_ocr_');
      db = AppDatabase(NativeDatabase.memory());
      paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
    });

    tearDown(() async {
      await db.close();
      tempRoot.deleteSync(recursive: true);
    });

    Future<AssetData> lege({String? text, String? boxen}) async {
      await db.into(db.assets).insert(AssetsCompanion.insert(
            id: 'a',
            originalFileName: 'schild.jpg',
            relativePath: 'originals/schild.jpg',
            checksum: 'a',
            fileCreatedAt: DateTime(2026, 5, 1),
            importedAt: DateTime(2026, 5, 2),
            type: 'IMAGE',
            fileSizeBytes: const Value(1000),
            ocrText: Value(text),
            ocrBoxen: Value(boxen),
            ocrScanned: const Value(true),
          ));
      return (await db.assetById('a'))!;
    }

    Future<void> zeige(WidgetTester tester, AssetData asset) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
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

    testWidgets('zeigt den erkannten Text markierbar an', (tester) async {
      final asset = await lege(text: 'Straße des 17. Juni\n135');
      await zeige(tester, asset);
      expect(find.text('Erkannter Text'), findsOneWidget);
      // SelectableText und nicht Text: Der halbe Nutzen ist, eine Nummer vom
      // Schild abzunehmen, ohne sie abzutippen.
      expect(
        find.widgetWithText(SelectableText, 'Straße des 17. Juni\n135'),
        findsOneWidget,
      );
      expect(find.byTooltip('Text kopieren'), findsOneWidget);
    });

    testWidgets('nennt die Zahl der Stellen, sobald es welche gibt', (tester) async {
      final asset = await lege(
        text: 'Kino',
        boxen: textstellenNachJson([
          const Textstelle(text: 'Kino', links: 0.1, oben: 0.1, breite: 0.2, hoehe: 0.1),
        ]),
      );
      await zeige(tester, asset);
      expect(find.text('1 Textstelle im Bild'), findsOneWidget);
    });

    testWidgets('behauptet bei einem Foto vor Schema 60 keine null Stellen', (tester) async {
      final asset = await lege(text: 'Kino');
      await zeige(tester, asset);
      expect(find.textContaining('Textstelle'), findsNothing);
    });

    testWidgets('ohne erkannten Text steht der Abschnitt nicht da', (tester) async {
      final asset = await lege(text: '');
      await zeige(tester, asset);
      expect(find.text('Erkannter Text'), findsNothing);
    });
  });

  group('Textrahmen', () {
    testWidgets('sitzt am Anteil der Fläche, nicht des Fensters', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 200,
            child: Stack(
              children: [
                Textrahmen(
                  stelle: Textstelle(
                      text: 'Kino', links: 0.25, oben: 0.5, breite: 0.5, hoehe: 0.25),
                  flaeche: Size(400, 200),
                ),
              ],
            ),
          ),
        ),
      ));
      final kasten = tester.getSize(find.byType(Textrahmen));
      // 0,5 * 400 plus zweimal zwei Punkte Luft um die Buchstaben.
      expect(kasten.width, closeTo(204, 0.01));
      expect(kasten.height, closeTo(54, 0.01));
    });

    testWidgets('Antippen meldet den Text dieser Zeile', (tester) async {
      String? gemeldet;
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 200,
            child: Stack(
              children: [
                Textrahmen(
                  stelle: const Textstelle(
                      text: 'Kino', links: 0.25, oben: 0.25, breite: 0.5, hoehe: 0.5),
                  flaeche: const Size(400, 200),
                  beiTipp: (t) => gemeldet = t,
                ),
              ],
            ),
          ),
        ),
      ));
      await tester.tap(find.byType(Textrahmen));
      await tester.pump();
      expect(gemeldet, 'Kino');
    });
  });
}
