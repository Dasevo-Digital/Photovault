import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/weissabgleich.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/develop_screen.dart';
import 'package:photo_vault/services/library_location.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:zierbild/temperaturregler.dart';

/// **Der Temperaturregler zeigt, wohin er das Bild schiebt** (#466): links
/// (tiefe Kelvin-Zahl) blau, rechts gelb – wie die Rechnung seit der
/// Umstellung auf die Bedeutung von Lightroom.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('6500 K liegt dort, wo der Verlauf neutral ist', () {
    expect(
      neutraleStelle(temperaturMin, temperaturMax),
      closeTo(4500 / 19125, 1e-12),
    );
    final v = temperaturVerlauf();
    expect(v.colors, [temperaturBlau, temperaturNeutral, temperaturGelb]);
    expect(v.stops![1], neutraleStelle(temperaturMin, temperaturMax));
  });

  testWidgets('die Spur ist links blau und rechts gelb', (tester) async {
    final rahmen = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: rahmen,
              child: SizedBox(
                width: 400,
                height: 48,
                child: SliderTheme(
                  data: const SliderThemeData(
                    trackShape: TemperaturSpur(),
                    trackHeight: 8,
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 0),
                    overlayShape: RoundSliderOverlayShape(overlayRadius: 0),
                  ),
                  child: Slider(
                    value: neutraleTemperatur,
                    min: temperaturMin,
                    max: temperaturMax,
                    onChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final grenze =
        rahmen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final pixel = (await tester.runAsync(() async {
      final bild = await grenze.toImage();
      final daten = await bild.toByteData(format: ui.ImageByteFormat.rawRgba);
      return (daten!, bild.width);
    }))!;
    (int, int, int) farbe(double anteil) {
      final x = (pixel.$2 * anteil).round();
      final i = (24 * pixel.$2 + x) * 4;
      return (
        pixel.$1.getUint8(i),
        pixel.$1.getUint8(i + 1),
        pixel.$1.getUint8(i + 2),
      );
    }

    final (lr, _, lb) = farbe(0.03);
    expect(lb, greaterThan(lr + 60), reason: 'links blau');
    final (rr, _, rb) = farbe(0.97);
    expect(rr, greaterThan(rb + 60), reason: 'rechts gelb');
  });

  group('am Rechner', () {
    late Directory wurzel;
    late AppDatabase db;
    late StoragePaths paths;

    setUp(() async {
      wurzel = Directory.systemTemp.createTempSync('pv_temperaturregler_');
      LibraryLocation.nutzeFuerTests(anker: wurzel);
      db = AppDatabase(NativeDatabase.memory());
      paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'l')),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('photo_vault/image_convert'),
            (aufruf) async => switch (aufruf.method) {
              'lensCorrectionStatus' => 'keinRaw',
              _ => null,
            },
          );
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: 'a1',
              originalFileName: 'a1.jpg',
              relativePath: 'originals/a1.jpg',
              checksum: 'c1',
              type: 'IMAGE',
              fileCreatedAt: DateTime(2026, 3, 5),
              importedAt: DateTime(2026, 3, 6),
            ),
          );
      // Eine frühere starke Erwärmung (2000 K in der alten Bedeutung),
      // umgerechnet – jenseits der alten Obergrenze von 12000 K.
      await db
          .into(db.developSettings)
          .insert(
            DevelopSettingsCompanion.insert(
              assetId: 'a1',
              temperature: Value(temperaturAusFruehererBedeutung(2000)),
              tint: const Value(0),
              updatedAt: DateTime(2026),
            ),
          );
    });

    tearDown(() async {
      LibraryLocation.zuruecksetzenFuerTests();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('photo_vault/image_convert'),
            null,
          );
      await db.close();
      wurzel.deleteSync(recursive: true);
    });

    testWidgets('Bereich, Verlauf und ein umgerechneter Wert', (tester) async {
      tester.view.physicalSize = const Size(1400, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final foto = (await tester.runAsync(() => db.assetById('a1')))!;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          theme: buildDarkTheme(),
          home: DevelopScreen(asset: foto, db: db, paths: paths),
        ),
      );
      final de = await AppTexte.delegate.load(const Locale('de'));
      Finder regler() => find.descendant(
        of: find.ancestor(
          of: find.text(de.entwTemperatur),
          matching: find.byWidgetPredicate((w) => w is Column),
        ),
        matching: find.byType(Slider),
      );
      await tester.runAsync(() async {
        for (var i = 0; i < 200; i++) {
          await tester.pump(const Duration(milliseconds: 25));
          await Future<void>.delayed(const Duration(milliseconds: 10));
          if (regler().evaluate().isNotEmpty &&
              tester.widget<Slider>(regler().first).onChanged != null) {
            break;
          }
        }
      });
      final slider = tester.widget<Slider>(regler().first);
      expect(slider.min, temperaturMin);
      expect(slider.max, temperaturMax);
      expect(slider.value, 21125.0);
      expect(slider.onChanged, isNotNull, reason: 'Automatik ist aus');
      final thema = tester.widget<SliderTheme>(
        find
            .ancestor(of: regler().first, matching: find.byType(SliderTheme))
            .first,
      );
      expect(thema.data.trackShape, isA<TemperaturSpur>());
      // Die Katalogprüfungen (reglerSpalte in katalog_bea_test.dart) suchen
      // den Regler als letztes Kind der Spalte mit seiner Beschriftung.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Column &&
              w.children.length == 2 &&
              w.children.last is Slider &&
              (w.children.last as Slider).max == temperaturMax,
        ),
        findsOneWidget,
      );
      expect(find.text('21125'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}
