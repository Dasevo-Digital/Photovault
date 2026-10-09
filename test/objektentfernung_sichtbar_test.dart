import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/image_editor_screen.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// **„Objektentfernung geht nicht."**
///
/// Sie ging nicht, weil es sie nicht zu sehen gab: Der Knopf fiel ganz
/// weg, solange das LaMa-Modell fehlte – mit dem Argument, ein Werkzeug,
/// das beim Antippen nur „geht nicht" meldet, sei schlechter als keines.
/// Das Ergebnis war schlechter als beides. In den Einstellungen steht ein
/// Modell namens „Objektentfernung (LaMa)", in der Bearbeitung gab es
/// dazu nichts, und nirgends stand ein Zusammenhang.
///
/// Jetzt steht der Knopf da – abgeschaltet, und sein Hinweistext sagt,
/// was fehlt und wo es herkommt.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths pfade;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_retusche_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(wurzel.path, 'lib')),
    );
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<AssetData> aufnahme({bool mitKratzer = false}) async {
    final bild = img.Image(
      width: mitKratzer ? 320 : 40,
      height: mitKratzer ? 240 : 30,
    );
    img.fill(bild, color: img.ColorRgb8(120, 140, 160));
    if (mitKratzer) {
      img.drawLine(
        bild,
        x1: 10,
        y1: 20,
        x2: 300,
        y2: 220,
        color: img.ColorRgb8(250, 250, 250),
      );
    }
    final datei = pfade.absolute('originals/a1.jpg');
    await datei.parent.create(recursive: true);
    await datei.writeAsBytes(img.encodeJpg(bild));
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'a1',
            originalFileName: 'a1.jpg',
            relativePath: 'originals/a1.jpg',
            checksum: 'c_a1',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 1, 1),
            importedAt: DateTime(2026, 1, 1),
          ),
        );
    return (db.select(db.assets)..where((t) => t.id.equals('a1'))).getSingle();
  }

  /// Legt eine leere Datei an, die aussieht wie das Modell – mehr fragt
  /// `InpaintingService.isAvailable` nicht ab, und mehr braucht dieser
  /// Test auch nicht: Gerechnet wird hier nichts.
  String modellordner() {
    final ordner = Directory(p.join(wurzel.path, 'models'))
      ..createSync(recursive: true);
    File(p.join(ordner.path, 'lama_fp32.onnx')).writeAsStringSync('');
    return ordner.path;
  }

  Future<void> zeige(
    WidgetTester tester,
    AssetData asset,
    String? modelle,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: ImageEditorScreen(
          asset: asset,
          db: db,
          paths: pfade,
          modelsDir: modelle,
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  IconButton knopf(WidgetTester tester) => tester.widget<IconButton>(
    find.ancestor(
      of: find.byIcon(Icons.auto_fix_high),
      matching: find.byType(IconButton),
    ),
  );

  testWidgets('ohne Modell steht der Knopf da und sagt, was fehlt', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final asset = await aufnahme();
      await zeige(tester, asset, null);

      // Er ist da - vorher war an dieser Stelle gar nichts.
      final k = knopf(tester);
      expect(k.onPressed, isNull, reason: 'abgeschaltet');
      expect(k.tooltip, contains('LaMa-Modell'));
      expect(k.tooltip, contains('KI-Modelle'));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  testWidgets('mit Modell ist er bedienbar und zieht den Pinsel auf', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final asset = await aufnahme();
      await zeige(tester, asset, modellordner());

      final k = knopf(tester);
      expect(k.onPressed, isNotNull);
      expect(k.tooltip, 'Objekt entfernen');

      // Und der Griff danach: Antippen legt die Malfläche über das Bild.
      expect(find.text('Entfernen'), findsNothing);
      await tester.tapAt(tester.getCenter(find.byIcon(Icons.auto_fix_high)));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(find.text('Entfernen'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  testWidgets(
    'die Kratzersuche legt einen Vorschlag an, der sich anwenden lässt',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      addTearDown(melde.verlaufLeeren);

      await tester.runAsync(() async {
        final asset = await aufnahme(mitKratzer: true);
        await zeige(tester, asset, modellordner());
        await tester.tapAt(tester.getCenter(find.byIcon(Icons.auto_fix_high)));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        FilledButton anwenden() => tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Entfernen'),
            matching: find.byWidgetPredicate((w) => w is FilledButton),
          ),
        );
        expect(anwenden().onPressed, isNull, reason: 'noch nichts markiert');

        await tester.tap(find.byIcon(Icons.healing_outlined));
        for (var i = 0; i < 40 && melde.sichtbare.isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(melde.sichtbare.single.text, startsWith('Vorschlag: 1 Kratzer'));
        await tester.pump();
        expect(anwenden().onPressed, isNotNull, reason: 'der Vorschlag genügt');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      });
    },
  );
}
