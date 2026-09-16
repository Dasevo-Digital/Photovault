import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/develop_screen.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// **Der Entwickeln-Bildschirm.**
///
/// Zwei Meldungen: Die KI-Restaurierung sagte „eingereiht" und danach
/// nichts mehr – ein Vorgang, der an einer echten Aufnahme rund hundert
/// Sekunden dauert, verschwand aus dem Blick genau des Bildschirms, auf
/// dem man ihn ausgelöst hat. Und der Verlauf zeigte eine Liste von
/// Zeitpunkten, ohne zu sagen, was an jedem davon getan wurde.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths paths;
  late AssetData foto;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_entw_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'l')));

    // Der native Kanal antwortet im Pruefstand nicht von selbst. Ohne
    // diese Antwort bliebe der Bildschirm im Ladezustand stehen, und
    // geprueft waere gar nichts.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('photo_vault/image_convert'),
      (aufruf) async => switch (aufruf.method) {
        'lensCorrectionStatus' => 'keinRaw',
        _ => null,
      },
    );

    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: 'a1',
          originalFileName: 'a1.jpg',
          relativePath: 'originals/a1.jpg',
          checksum: 'c1',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2026, 3, 5),
          importedAt: DateTime(2026, 3, 6),
        ));
    foto = (await db.assetById('a1'))!;
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('photo_vault/image_convert'), null);
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  /// `pumpAndSettle` geht hier nicht: Ohne nativen Render bleibt im
  /// Bildbereich ein Ladering stehen, und ein Ring hoert nie auf.
  Future<void> takte(WidgetTester tester, [int wie = 40]) async {
    for (var i = 0; i < wie; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
  }

  Future<void> zeige(WidgetTester tester) async {
    // Hoch genug, dass die ganze Reglerspalte ohne Rollen dasteht -
    // ein Regler ausserhalb des Bildes nimmt keine Geste an.
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: DevelopScreen(asset: foto, db: db, paths: paths),
    ));
    await takte(tester);
  }

  Future<void> abbauen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  group('Der Fortschritt der Restaurierung', () {
    testWidgets('ohne Auftrag steht dort nichts', (tester) async {
      await zeige(tester);
      expect(find.text('KI-Restaurierung'), findsNothing);
      await abbauen(tester);
    });

    testWidgets('ein wartender Auftrag sagt, dass er wartet', (tester) async {
      await db.createRestoreJob(RestoreJobsCompanion.insert(
        id: 'j1',
        assetId: 'a1',
        status: 'queued',
        createdAt: DateTime(2026, 3, 6),
      ));
      await zeige(tester);
      expect(find.text('KI-Restaurierung'), findsOneWidget);
      expect(find.textContaining('Wartet'), findsOneWidget);
      await abbauen(tester);
    });

    testWidgets('ein laufender Auftrag zeigt Prozent und Restzeit',
        (tester) async {
      await db.createRestoreJob(RestoreJobsCompanion.insert(
        id: 'j1',
        assetId: 'a1',
        status: 'running',
        createdAt: DateTime.now().subtract(const Duration(seconds: 50)),
        startedAt: Value(DateTime.now().subtract(const Duration(seconds: 50))),
        tilesDone: const Value(10),
        tilesTotal: const Value(20),
      ));
      await zeige(tester);
      expect(find.textContaining('50'), findsWidgets);
      await abbauen(tester);
    });

    testWidgets('der Auftrag eines anderen Fotos geht mich nichts an',
        (tester) async {
      await db.into(db.assets).insert(AssetsCompanion.insert(
            id: 'a2',
            originalFileName: 'a2.jpg',
            relativePath: 'originals/a2.jpg',
            checksum: 'c2',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 3, 5),
            importedAt: DateTime(2026, 3, 6),
          ));
      await db.createRestoreJob(RestoreJobsCompanion.insert(
        id: 'j2',
        assetId: 'a2',
        status: 'running',
        createdAt: DateTime(2026, 3, 6),
      ));
      await zeige(tester);
      expect(find.text('KI-Restaurierung'), findsNothing);
      await abbauen(tester);
    });
  });

  group('Der Verlauf', () {
    testWidgets('haelt schon waehrend der Sitzung fest, was getan wurde',
        (tester) async {
      await zeige(tester);
      // Der Regler fuer die Belichtung steht ganz oben in der Spalte.
      final regler = find.byType(Slider).first;
      await tester.drag(regler, const Offset(60, 0));
      await takte(tester);

      await tester.tap(find.byIcon(Icons.history));
      await takte(tester, 20);

      // Nicht nur wann, auch was: Vorher stand hier eine Liste von
      // Zeitpunkten, und nichts sonst.
      expect(find.text('Diese Sitzung'), findsOneWidget);
      expect(find.text('Belichtung'), findsWidgets);
      expect(find.text('Stand beim Öffnen'), findsOneWidget);
      await abbauen(tester);
    });

    testWidgets('ohne jede Aenderung gibt es nichts zu zeigen', (tester) async {
      await zeige(tester);
      await tester.tap(find.byIcon(Icons.history));
      await takte(tester, 20);
      // Ein einziger Schritt ist kein Verlauf.
      expect(find.text('Diese Sitzung'), findsNothing);
      await abbauen(tester);
    });
  });
  group('Die Regler wirken beim Ziehen', () {
    /// **Sechs Regler zeigten waehrend des Ziehens nichts.** Die
    /// Live-Vorschau laeuft ueber den Shader, und der kann Schaerfe,
    /// Rauschunterdrueckung, Klarheit und Vignettierung gar nicht und
    /// den Weissabgleich nur genaehert (gemessen bis 6,1 % Abweichung).
    /// Sie standen deshalb auf `liveVorschau: false` – was hiess: der
    /// Regler bewegt sich, das Bild nicht, bis man loslaesst.
    ///
    /// Ein Render der Vorschau kostet gemessen 42 ms (6000×4000,
    /// Kante 1600). Waehrend des Ziehens nativ zu rechnen ist damit
    /// moeglich, und zwar genau statt genaehert.
    int rendervorgaenge = 0;

    setUp(() {
      rendervorgaenge = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('photo_vault/image_convert'),
        (aufruf) async {
          if (aufruf.method == 'developImage') rendervorgaenge++;
          return switch (aufruf.method) {
            'lensCorrectionStatus' => 'keinRaw',
            _ => null,
          };
        },
      );
    });

    /// Zieht am Regler mit [beschriftung] in mehreren Schritten – so, wie
    /// ein Finger es tut, und nicht in einem Sprung.
    Future<void> ziehe(WidgetTester tester, String beschriftung) async {
      final zeile = find.ancestor(
          of: find.text(beschriftung),
          matching: find.byWidgetPredicate((w) => w is Column));
      final regler = find.descendant(of: zeile, matching: find.byType(Slider));
      final mitte = tester.getCenter(regler.first);
      final griff = await tester.startGesture(mitte);
      for (var i = 0; i < 6; i++) {
        await griff.moveBy(const Offset(8, 0));
        await takte(tester, 6);
      }
      await griff.up();
      await takte(tester, 20);
    }

    testWidgets('die Vignettierung rechnet schon waehrend des Ziehens',
        (tester) async {
      await zeige(tester);
      final vorher = rendervorgaenge;
      await ziehe(tester, 'Vignettierung');
      // Mehr als der eine Render, der frueher erst nach dem Loslassen
      // kam: Das Bild ist dem Regler gefolgt.
      expect(rendervorgaenge - vorher, greaterThan(1),
          reason: 'waehrend des Ziehens wurde nicht gerechnet');
      await abbauen(tester);
    });

    testWidgets('es laeuft trotzdem immer nur ein Render', (tester) async {
      // Ohne diese Regel waere eine langsame Datei - ein RAW geht durch
      // CIRAWFilter - eine Warteschlange, die nie leer wird.
      await zeige(tester);
      final vorher = rendervorgaenge;
      await ziehe(tester, 'Klarheit');
      final anzahl = rendervorgaenge - vorher;
      expect(anzahl, greaterThan(1));
      expect(anzahl, lessThanOrEqualTo(8),
          reason: 'je Bewegung hoechstens ein Render, plus Nachzuegler');
      await abbauen(tester);
    });

    testWidgets('auch sie stehen danach im Verlauf', (tester) async {
      // Diese Regler laufen nicht ueber den Entpreller, und dort wird
      // der Schritt sonst festgehalten - ohne Nachfassen fehlten sie im
      // Verlauf ganz.
      await zeige(tester);
      await ziehe(tester, 'Klarheit');
      await tester.tap(find.byIcon(Icons.history));
      await takte(tester, 20);
      expect(find.text('Diese Sitzung'), findsOneWidget);
      expect(find.text('Klarheit'), findsWidgets);
      await abbauen(tester);
    });

    testWidgets('die Belichtung bleibt beim Shader', (tester) async {
      // Sie ist im Shader genau (0,1 % Abweichung) - dort waere ein
      // nativer Render je Bewegung verschenkte Arbeit.
      await zeige(tester);
      final vorher = rendervorgaenge;
      await ziehe(tester, 'Belichtung');
      expect(rendervorgaenge - vorher, lessThanOrEqualTo(2),
          reason: 'waehrend des Ziehens zeichnet der Shader');
      await abbauen(tester);
    });
  },
      skip: Platform.isMacOS
          ? false
          : 'Der native Live-Render ist nur der maßgebliche macOS-Pfad.');
}
