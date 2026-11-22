import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:photo_vault/services/library_location.dart';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:kern/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/develop_screen.dart';
import 'package:photo_vault/services/segmentation_service.dart';
import 'package:kern/services/modell_halter.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// **Die Maskenwerkzeuge nahmen keine Geste an.**
///
/// Im Bericht standen vier Punkte nebeneinander - Pinsel/Rechteck,
/// Ellipse/Verlauf, Farbe und KI -, alle mit demselben Satz: "es laesst
/// sich kein Rechteck aufziehen". Vier Werkzeuge, eine Ursache.
///
/// Der Maskeneditor haengt unter einem `Center`. Dort bekommt er lockere
/// Zwaenge: Der `LayoutBuilder` meldet als `maxWidth`/`maxHeight` die
/// ganze freie Flaeche, der Stapel darunter schrumpft aber auf das
/// eingepasste Bild samt Rand. Die Umrechnung Zeigerpunkt -> Bildpunkt
/// rechnete mit der gemeldeten Flaeche, die Geste kam aber in
/// Koordinaten des geschrumpften Kastens an. Bei einem querformatigen
/// Bild in einer hochformatigen Flaeche liegt der so berechnete
/// Bildbereich komplett unterhalb dessen, was der Zeiger je erreicht -
/// die Umrechnung gab fuer jeden Punkt `null` zurueck, und `null` heisst
/// im Editor: nichts tun.
///
/// Zweiter, kleinerer Fehler an derselben Stelle: Das Bild sitzt in
/// einem `Padding` von [AppSpacing.lg]; die Umrechnung wusste davon
/// nichts und war auch bei passender Flaeche um diesen Rand verschoben.
/// Eine Segmentierung, deren Einbettung erst rechnet, wenn [tor] offen ist.
class _Segmentierung implements SegmentationService {
  final tor = Completer<void>();

  @override
  Future<SamImageEmbedding> encodeImage(img.Image decoded) async {
    await tor.future;
    return SamImageEmbedding(
      embeddings: Float32List(1),
      positionalEmbeddings: Float32List(1),
      scale: 1,
      originalWidth: decoded.width,
      originalHeight: decoded.height,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths paths;
  late AssetData foto;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_maskgeste_');
    LibraryLocation.nutzeFuerTests(anker: wurzel);
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'l')));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('photo_vault/image_convert'),
          (aufruf) async => switch (aufruf.method) {
            'lensCorrectionStatus' => 'keinRaw',
            _ => null,
          },
        );

    // Ein echtes Bild auf der Platte: Ohne Vorschaubytes zeigt der
    // Bildschirm einen Ladering statt des Editors, und die Geste haette
    // gar kein Ziel. Querformat 2:1 - das ist der Fall aus dem Bericht.
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

  Future<void> takte(WidgetTester tester, [int wie = 40]) async {
    for (var i = 0; i < wie; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
  }

  /// Taktet, bis [ziel] da ist – höchstens rund 15 s, mit echten Pausen
  /// dazwischen. In der CI kam das Werkzeugmenü unter Last später als nach
  /// festen Takten, und der Chip fehlte beim Tippen.
  Future<void> taktebis(WidgetTester tester, Finder ziel) async {
    for (var i = 0; i < 300 && ziel.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 25));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
    }
  }

  /// Hochformatige Flaeche, querformatiges Bild - so stand es auf dem
  /// Schreibtisch, und genau so faellt die Fehlrechnung am staerksten aus.
  Future<void> zeige(
    WidgetTester tester, {
    ModellHalter<SegmentationService>? segmentation,
  }) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Der Bildschirm liest seine Vorschau von der Platte, und echte
    // Ein-/Ausgabe laeuft in einem Widget-Pruefstand nur unter
    // `runAsync`: Sonst haengt das `await` wortlos und im Bild stuende
    // bis zum Schluss ein Ladering.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          theme: buildDarkTheme(),
          home: DevelopScreen(
            asset: foto,
            db: db,
            paths: paths,
            segmentation: segmentation,
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 25));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await takte(tester);
  }

  Future<void> abbauen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Der Maskeneditor: der einzige Zieh-Empfaenger im Bild.
  Finder derEditor() => find.byWidgetPredicate(
    (w) => w is GestureDetector && w.onPanStart != null,
  );

  /// Der Knopf "Fertig" ist genau dann bedienbar, wenn eine Form
  /// entstanden ist - er ist der ehrlichste Zeuge dafuer.
  bool fertigBedienbar(WidgetTester tester) {
    final knopf = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Fertig'),
        matching: find.byType(FilledButton),
      ),
    );
    return knopf.onPressed != null;
  }

  Future<void> werkzeug(WidgetTester tester, String name) async {
    await tester.tap(find.byIcon(Icons.auto_fix_high_outlined));
    final chip = find.widgetWithText(ChoiceChip, name);
    await taktebis(tester, chip);
    await tester.tap(chip);
    await takte(tester, 10);
  }

  /// Zieht quer ueber die Bildmitte - so, wie ein Finger es tut.
  Future<void> ziehe(WidgetTester tester) async {
    final mitte = tester.getCenter(derEditor());
    final griff = await tester.startGesture(mitte - const Offset(80, 40));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 8; i++) {
      await griff.moveBy(const Offset(20, 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await griff.up();
    await takte(tester, 10);
  }

  group('Die Zieh-Werkzeuge nehmen die Geste an', () {
    testWidgets('Rechteck', (tester) async {
      await zeige(tester);
      await werkzeug(tester, 'Rechteck');
      expect(
        fertigBedienbar(tester),
        isFalse,
        reason: 'ohne Geste gibt es noch keine Form',
      );
      await ziehe(tester);
      expect(
        fertigBedienbar(tester),
        isTrue,
        reason: 'das Ziehen hat kein Rechteck erzeugt',
      );
      await abbauen(tester);
    });

    testWidgets('Ellipse', (tester) async {
      await zeige(tester);
      await werkzeug(tester, 'Ellipse');
      await ziehe(tester);
      expect(fertigBedienbar(tester), isTrue);
      await abbauen(tester);
    });

    testWidgets('Verlauf', (tester) async {
      await zeige(tester);
      await werkzeug(tester, 'Verlauf');
      await ziehe(tester);
      expect(fertigBedienbar(tester), isTrue);
      await abbauen(tester);
    });

    testWidgets('Pinsel', (tester) async {
      await zeige(tester);
      await werkzeug(tester, 'Pinsel');
      await ziehe(tester);
      expect(fertigBedienbar(tester), isTrue);
      await abbauen(tester);
    });
  });

  group('Die Tipp-Werkzeuge nehmen den Tipp an', () {
    testWidgets('Farbe nimmt die Farbe unter dem Finger auf', (tester) async {
      await zeige(tester);
      await werkzeug(tester, 'Farbe');
      // Der Farbwaehler dekodiert die Vorschau in einem eigenen
      // Isolat - das laeuft nur unter `runAsync` zu Ende.
      final ziel = tester.getCenter(derEditor());
      await tester.runAsync(() async {
        await tester.tapAt(ziel);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 25));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await takte(tester, 15);
      expect(
        fertigBedienbar(tester),
        isTrue,
        reason: 'der Tipp hat keine Farbauswahl erzeugt',
      );
      await abbauen(tester);
    });

    testWidgets('Helligkeit ist gleich bereit, ohne Geste', (tester) async {
      await zeige(tester);
      await werkzeug(tester, 'Helligkeit');
      expect(fertigBedienbar(tester), isTrue);
      expect(find.text('Von'), findsOneWidget);
      expect(find.text('Bis'), findsOneWidget);
      await abbauen(tester);
    });
  });

  group('Graupunkt (#353)', () {
    Finder pipette() => find.byWidgetPredicate(
      (w) => w is MouseRegion && w.cursor == SystemMouseCursors.precise,
    );

    bool automatik(WidgetTester tester) => tester
        .widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, 'Automatischer Weißabgleich'),
        )
        .value;

    testWidgets('ein Klick ins Bild stellt den Weissabgleich ein', (
      tester,
    ) async {
      await zeige(tester);
      expect(automatik(tester), isTrue);
      await tester.ensureVisible(find.text('Graupunkt wählen'));
      await tester.pump();
      await tester.tap(find.text('Graupunkt wählen'));
      await tester.pump();
      expect(pipette(), findsOneWidget);
      final ziel = tester.getCenter(pipette());
      await tester.runAsync(() async {
        await tester.tapAt(ziel);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 25));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await takte(tester, 15);
      expect(automatik(tester), isFalse);
      // Das Foto ist bläulich, also muss der Regler unter 6500 K stehen.
      expect(find.text('6500'), findsNothing);
      // Die Pipette gibt die Fläche wieder frei.
      expect(pipette(), findsNothing);
      await abbauen(tester);
    });

    testWidgets('noch einmal drücken bricht ab', (tester) async {
      await zeige(tester);
      await tester.ensureVisible(find.text('Graupunkt wählen'));
      await tester.pump();
      await tester.tap(find.text('Graupunkt wählen'));
      await tester.pump();
      await tester.tap(
        find.text('Klicke auf etwas, das grau oder weiss sein soll'),
      );
      await tester.pump();
      expect(pipette(), findsNothing);
      expect(automatik(tester), isTrue);
      await abbauen(tester);
    });
  });

  // Das Rasterisieren auf Originalauflösung dauert Sekunden, und solange
  // blieb „Fertig“ bedienbar: Ein zweiter Klick legte dieselbe Maske ein
  // zweites Mal an.
  testWidgets('zweimal „Fertig“ legt die Maske nur einmal an', (tester) async {
    await zeige(tester);
    await werkzeug(tester, 'Rechteck');
    await ziehe(tester);
    final fertig = find.ancestor(
      of: find.text('Fertig'),
      matching: find.byType(FilledButton),
    );
    await tester.tap(fertig);
    await tester.tap(fertig);
    // Das Rasterisieren läuft in einem eigenen Isolat.
    await tester.runAsync(() async {
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 25));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await takte(tester, 10);
    expect(find.text('Maske 1'), findsOneWidget);
    await abbauen(tester);
  });

  // Wer zwischen „KI“ und einem anderen Werkzeug wechselte, solange die
  // Einbettung noch rechnete, startete einen zweiten Durchgang. Beide
  // liehen das Modell, zurückgegeben wurde es beim Schliessen nur einmal –
  // und das Segmentierungsmodell blieb bis zum Programmende geladen.
  testWidgets('Werkzeugwechsel während der Einbettung leiht nur einmal', (
    tester,
  ) async {
    final dienst = _Segmentierung();
    final halter = ModellHalter<SegmentationService>(
      name: 'SAM',
      installiert: true,
      laden: () async => dienst,
      entsorgen: (_) async {},
    );
    await zeige(tester, segmentation: halter);
    await tester.tap(find.byIcon(Icons.auto_fix_high_outlined));
    await takte(tester, 10);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Pinsel'));
    await takte(tester, 5);
    await tester.tap(find.widgetWithText(ChoiceChip, 'KI'));
    await takte(tester, 5);
    dienst.tor.complete();
    await tester.runAsync(() async {
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 25));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await abbauen(tester);
    expect(halter.nutzer, 0, reason: 'offene Leihen nach dem Schliessen');
  });

  // Bis die kleine Fassung für die Helligkeitsmaske da war, las und
  // dekodierte jeder Aufruf das volle Original noch einmal – bei jeder
  // Reglerbewegung und jedem Werkzeugwechsel ein eigener Durchgang.
  testWidgets('die Helligkeitsmaske lädt ihr Foto nur einmal', (tester) async {
    await zeige(tester);
    // Ab hier liegt das Original nicht mehr da und wird „geholt“ – so lässt
    // sich zählen, wie oft die Maske es anfordert.
    final original = File(paths.absolute('originals/a1.jpg').path);
    final inhalt = original.readAsBytesSync();
    original.deleteSync();
    final tor = Completer<void>();
    var geholt = 0;
    paths.beschaffe = (pfad) async {
      geholt++;
      await tor.future;
      if (!original.existsSync()) original.writeAsBytesSync(inhalt);
    };
    await werkzeug(tester, 'Helligkeit');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Pinsel'));
    await takte(tester, 5);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Helligkeit'));
    await takte(tester, 5);
    await tester.runAsync(() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 25));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      tor.complete();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 25));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    expect(geholt, 1);
    await abbauen(tester);
  });
}
