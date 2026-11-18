import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:kern/db/database.dart';
import 'package:photo_vault/services/library_location.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/develop_screen.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// **Masken gelten wie die Regler erst mit „Speichern“.**
///
/// BEA-046: Eine Maske, die man im Entwickeln anlegte, stand sofort in der
/// Datenbank; eine per X gelöschte war sofort weg. „Zurück ohne Speichern“
/// liess beides so stehen – anders als jeder Regler.
///
/// BEA-048: „Zurücksetzen“ löschte Einstellungen und Entwicklungsdatei,
/// liess die Masken aber stehen; beim nächsten Öffnen wirkten sie wieder.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths paths;
  late AssetData foto;
  final jpeg = img.encodeJpg(img.Image(width: 8, height: 8));

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_maskensitzung_');
    // Die Entwickeln-Ansicht fragt den Ort der Bibliothek ab.
    LibraryLocation.nutzeFuerTests(anker: wurzel);
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'l')));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('photo_vault/image_convert'),
          (aufruf) async => switch (aufruf.method) {
            'lensCorrectionStatus' => 'keinRaw',
            'developImage' => jpeg,
            _ => null,
          },
        );

    final datei = File(paths.absolute('originals/a1.jpg').path);
    await datei.parent.create(recursive: true);
    final bild = img.Image(width: 400, height: 200);
    img.fill(bild, color: img.ColorRgb8(120, 140, 160));
    await datei.writeAsBytes(img.encodePng(bild));

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
            widthPx: const Value(4000),
            heightPx: const Value(2000),
          ),
        );
    foto = (await db.assetById('a1'))!;
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

  /// Echte Datei- und Datenbankarbeit läuft im Prüfstand nur unter
  /// `runAsync`; der Takt des Bildschirms nur mit `pump`. Beides
  /// abwechselnd, bis [fertig] gilt.
  Future<void> abwarten(
    WidgetTester tester, {
    bool Function()? fertig,
    int runden = 40,
  }) async {
    for (var i = 0; i < runden; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 25));
      if (fertig?.call() ?? false) break;
    }
  }

  /// Öffnet den Bildschirm über einer Startseite, damit „Zurück“ einen
  /// Weg hat.
  Future<void> zeige(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          theme: buildDarkTheme(),
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<bool>(
                    builder: (_) =>
                        DevelopScreen(asset: foto, db: db, paths: paths),
                  ),
                ),
                child: const Text('öffnen'),
              ),
            ),
          ),
        ),
      );
    });
    await tester.tap(find.text('öffnen'));
    await abwarten(tester, runden: 30);
  }

  Future<void> abbauen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<List<DevelopMaskData>> masken(WidgetTester tester) async =>
      (await tester.runAsync(() => db.masksForAsset('a1')))!;

  /// Zeichnet ein Rechteck und bestätigt es mit „Fertig“.
  Future<void> rechteckAnlegen(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.auto_fix_high_outlined));
    await abwarten(tester, runden: 5);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Rechteck'));
    await abwarten(tester, runden: 5);
    final editor = find.byWidgetPredicate(
      (w) => w is GestureDetector && w.onPanStart != null,
    );
    final mitte = tester.getCenter(editor);
    final griff = await tester.startGesture(mitte - const Offset(80, 40));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 8; i++) {
      await griff.moveBy(const Offset(20, 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await griff.up();
    await tester.pump(const Duration(milliseconds: 25));
    await tester.tap(find.text('Fertig'));
    await abwarten(
      tester,
      fertig: () => find.text('Maske 1').evaluate().isNotEmpty,
      runden: 80,
    );
    expect(find.text('Maske 1'), findsOneWidget);
  }

  Future<void> zurueck(WidgetTester tester) async {
    await tester.tap(find.byType(BackButton));
    await abwarten(
      tester,
      fertig: () => find.byType(DevelopScreen).evaluate().isEmpty,
    );
    expect(find.byType(DevelopScreen), findsNothing);
  }

  List<File> maskendateien() {
    final ordner = Directory(
      p.dirname(paths.absolute(paths.maskRelativePath('x')).path),
    );
    if (!ordner.existsSync()) return const [];
    return ordner.listSync().whereType<File>().toList();
  }

  /// Eine gespeicherte Maske samt Datei, wie sie eine frühere Sitzung
  /// hinterlassen hat.
  Future<DevelopMaskData> gespeicherteMaske(WidgetTester tester) async {
    final pfad = paths.maskRelativePath('alt');
    return (await tester.runAsync(() async {
      final datei = paths.absolute(pfad);
      await datei.parent.create(recursive: true);
      await datei.writeAsBytes(img.encodePng(img.Image(width: 4, height: 4)));
      final id = await db
          .into(db.developMasks)
          .insert(
            DevelopMasksCompanion.insert(
              assetId: 'a1',
              maskRelativePath: pfad,
              label: 'Himmel',
              createdAt: DateTime(2026, 3, 7),
            ),
          );
      return (await db.masksForAsset('a1')).firstWhere((m) => m.id == id);
    }))!;
  }

  group('Zurück ohne Speichern (BEA-046)', () {
    testWidgets('lässt keine neue Maske zurück', (tester) async {
      await zeige(tester);
      await rechteckAnlegen(tester);
      await zurueck(tester);
      expect(await masken(tester), isEmpty);
      expect(maskendateien(), isEmpty, reason: 'die Datei gehört zu nichts');
      await abbauen(tester);
    });

    testWidgets('lässt eine gelöschte Maske stehen', (tester) async {
      final alt = await gespeicherteMaske(tester);
      await zeige(tester);
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(InputChip, 'Himmel'),
          matching: find.byIcon(Icons.close),
        ),
      );
      await abwarten(tester, runden: 5);
      expect(find.text('Himmel'), findsNothing);
      await zurueck(tester);
      expect((await masken(tester)).map((m) => m.id), [alt.id]);
      expect(paths.absolute(alt.maskRelativePath).existsSync(), isTrue);
      await abbauen(tester);
    });
  });

  testWidgets(
    'Speichern legt die neue Maske an',
    (tester) async {
      await zeige(tester);
      await rechteckAnlegen(tester);
      await tester.tap(find.byTooltip('Speichern'));
      await abwarten(
        tester,
        fertig: () => find.byType(DevelopScreen).evaluate().isEmpty,
        runden: 60,
      );
      final gespeichert = await masken(tester);
      expect(gespeichert, hasLength(1));
      expect(
        paths.absolute(gespeichert.single.maskRelativePath).existsSync(),
        isTrue,
      );
      await abbauen(tester);
    },
    // Unter Linux und Windows rendert der Shader; der braucht im
    // Prüfstand ein Fenster, das es hier nicht gibt.
    skip: !Platform.isMacOS,
  );

  testWidgets('Zurücksetzen löscht auch die Masken (BEA-048)', (tester) async {
    final alt = await gespeicherteMaske(tester);
    await zeige(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Zurücksetzen'),
      ),
    );
    await abwarten(tester, runden: 5);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Zurücksetzen'),
      ),
    );
    await abwarten(
      tester,
      fertig: () => find.byType(DevelopScreen).evaluate().isEmpty,
    );
    expect(await masken(tester), isEmpty);
    expect(paths.absolute(alt.maskRelativePath).existsSync(), isFalse);
    await abbauen(tester);
  });
}
