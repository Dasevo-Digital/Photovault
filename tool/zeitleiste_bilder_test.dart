/// **Die Zeitleiste als Bild – Quadrate gegen bündige Reihen.**
///
/// Kein Teil der Prüfsuite; liegt deshalb unter `tool/`. Zahlen sagen, ob
/// eine Reihe bündig ist. Ob eine Wand aus Fotos gut aussieht, sagt nur
/// das Bild.
///
/// ```sh
/// PV_BILDER=~/Desktop/pv_zeitleiste flutter test tool/zeitleiste_bilder_test.dart
/// ```
///
/// Die Vorschaubilder sind **erzeugt**, nicht echt: farbige Flächen in
/// genau den Seitenverhältnissen, die die echte Bibliothek hat (aus ihr
/// abgefragt, siehe die Liste unten). Damit zeigt das Bild die Anordnung
/// und nichts Privates – dieselbe Regel wie in docs/screenshots/README.md,
/// hier sogar gegenstandslos, weil kein einziges echtes Foto vorkommt.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/db/rasterzeile.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/month_grouped_asset_grid.dart';
import 'package:photo_vault/widgets/timeline_grid_layout.dart';

/// Die ersten 48 Masse der echten Bibliothek, in ihrer Reihenfolge.
/// Abgefragt, nicht ausgedacht – damit das Bild zeigt, was der Nutzer
/// wirklich sähe: viel Hochformat vom Telefon, dazwischen Querformate.
const _masse = [
  [1536, 2048], [1536, 2048], [1536, 2048], [1536, 2048], [1536, 2048],
  [1536, 2048], [1536, 2048], [1536, 2048], [1536, 2048], [1536, 2048],
  [2048, 1536], [1536, 2048], [1536, 2048], [1080, 1920], [1536, 2048],
  [1536, 2048], [2048, 1536], [1152, 2048], [1152, 2048], [1536, 2048],
  [2048, 1536], [1536, 2048], [1536, 2048], [1536, 2048], [1536, 2048],
  [1536, 2048], [1536, 2048], [1536, 2048], [1308, 1744], [1536, 2048],
  [720, 1280], [1536, 2048], [1600, 900], [1200, 1600], [1600, 900],
  [1600, 900], [576, 1024], [1600, 900], [1600, 900], [1600, 1200],
  [1200, 1600], [1600, 900], [1600, 900], [1600, 900], [2048, 1706],
  [4032, 2268], [4032, 2268], [4032, 2268],
];

void main() {
  final ziel = Platform.environment['PV_BILDER'];

  testWidgets('Quadrate und Reihen nebeneinander', (tester) async {
    if (ziel == null) {
      markTestSkipped('PV_BILDER nicht gesetzt');
      return;
    }
    // ignore: avoid_print
    print('>> Start');
    final wurzel = Directory.systemTemp.createTempSync('pv_zl_bilder_');
    addTearDown(() => wurzel.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ordner = Directory(p.join(wurzel.path, 'l'));

    // Farbige Flaechen in den echten Seitenverhaeltnissen. Alles, was die
    // Platte anfasst, gehoert in runAsync - AUCH das Anlegen der Ablage.
    // Ein `await` auf echte Ein-/Ausgabe ausserhalb haengt in der
    // Testbuehne wortlos, bis der Lauf abgeschossen wird; genau daran hat
    // dieses Werkzeug zweimal gestanden.
    late final StoragePaths paths;
    await tester.runAsync(() async {
      // forTesting ist fuer Tests gedacht, und das hier ist eines - nur
      // liegt es unter tool/, weil es kein Teil der Suite sein soll. Der
      // Prueferwarnung deshalb ausdruecklich widersprochen, statt eine
      // zweite Zugangsart zu bauen, die es sonst nirgends gaebe.
      // ignore: invalid_use_of_visible_for_testing_member
      paths = await StoragePaths.forTesting(ordner);
      for (var i = 0; i < _masse.length; i++) {
        final b = _masse[i][0], h = _masse[i][1];
        // Auf Vorschaugroesse herunter, wie es die App auch tut - und
        // kleiner als die echten 400 Punkte: Hier zaehlt die Form, nicht
        // die Schaerfe, und 48 Bilder Pixel fuer Pixel zu malen dauerte
        // laenger als der ganze Lauf.
        const lang = 200;
        final kurz = b > h ? (200 * h / b).round() : (200 * b / h).round();
        final bild = img.Image(
            width: b > h ? lang : kurz, height: b > h ? kurz : lang);
        // Eine Farbe je Kachel, dazu ein heller Balken am oberen Rand:
        // Wuerde etwas beschnitten, fehlte er.
        final ton = (i * 47) % 256;
        img.fill(bild,
            color: img.ColorRgb8(60 + ton ~/ 2, 90, 200 - ton ~/ 2));
        img.fillRect(bild,
            x1: 0,
            y1: 0,
            x2: bild.width - 1,
            y2: (bild.height * 0.12).round(),
            color: img.ColorRgb8(240, 240, 240));
        final rel = 'thumbs/t$i.png';
        final datei = paths.absolute(rel);
        await datei.parent.create(recursive: true);
        await datei.writeAsBytes(img.encodePng(bild));
        await db.into(db.assets).insert(AssetsCompanion.insert(
              id: 'a$i',
              originalFileName: 'a$i.jpg',
              relativePath: 'o/a$i.jpg',
              checksum: 'c$i',
              type: 'IMAGE',
              fileCreatedAt: DateTime(2026, 3, 20 - i ~/ 24),
              importedAt: DateTime(2026),
              thumbnailRelativePath: Value(rel),
              widthPx: Value(b),
              heightPx: Value(h),
            ));
      }
    });

    // ignore: avoid_print
    print('>> Bilder und Datensaetze fertig');
    final assets = await db.select(db.assets).get();

    // ignore: avoid_print
    print('>> ${assets.length} Aufnahmen');
    for (final form in Zeitleistenform.values) {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // ignore: avoid_print
      print('>> baue ${form.name}');
      // pumpWidget gehoert MIT in runAsync: Image.file loest die Datei
      // erst beim Aufbau auf, und die Aufloesung braucht echte Zeit.
      // Ausserhalb bleibt das Bild leer, und uebrig bleiben nur die
      // Abzeichen darueber - so sah der erste Durchgang aus.
      await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: Scaffold(
          body: RepaintBoundary(
            child: MonthGroupedAssetGrid(
              assets: [for (final x in assets) Rasterzeile.aus(x)],
              paths: paths,
              onTap: (_) {},
              form: form,
            ),
          ),
        ),
      ));
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      });
      await tester.pump();

      // ignore: avoid_print
      print('>> ${form.name} gepumpt');
      final grenze = tester
          .firstElement(find.byType(RepaintBoundary))
          .renderObject! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final bild = await grenze.toImage(pixelRatio: 1.0);
        final daten = await bild.toByteData(format: ui.ImageByteFormat.png);
        bild.dispose();
        final datei = File(p.join(ziel, 'zeitleiste_${form.name}.png'));
        await datei.parent.create(recursive: true);
        await datei.writeAsBytes(daten!.buffer.asUint8List());
        // ignore: avoid_print
        print('geschrieben: ${datei.path} '
            '(${daten.lengthInBytes ~/ 1024} KB)');
      });
    }
  });
}
