import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/bildzuschnitt.dart';
import 'package:kern/services/modell_halter.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/develop_screen.dart';
import 'package:photo_vault/services/library_location.dart';
import 'package:photo_vault/services/segmentation_service.dart';
import 'package:photo_vault/services/vector_mask_service.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/develop_preview.dart'
    show VorherNachherVergleich;

/// **Masken, Pipetten und Graupunkt bei zugeschnittenem Foto (#457).**
///
/// Der Editor zeigt das Foto mit Zuschnitt und Drehung, rechnete aber in
/// Originalkoordinaten: Wo das Bild im Editor sitzt, ergab sich aus dem
/// Seitenverhältnis des Originals, und jeder Punkt ging ohne Umrechnung
/// als Originalpunkt in die Maske. Eine Form landete dadurch an einer
/// ganz anderen Stelle, als sie aufgezogen war; die KI-Auswahl wurde im
/// Format des Ausschnitts über das ganze Foto gelegt; und der Graupunkt
/// fiel bei abweichendem Seitenverhältnis oft ganz aus dem Bild.
///
/// Geprüft wird am Ergebnis: an der gespeicherten Maskendatei und am
/// Weissabgleich – nicht an einer Hilfsrechnung.

/// Eine Segmentierung, die um den angetippten Punkt eine kleine Fläche
/// auswählt – genug, um zu sehen, wohin die Auswahl gelegt wird.
class _Segmentierung implements SegmentationService {
  @override
  Future<SamImageEmbedding> encodeImage(img.Image decoded) async =>
      SamImageEmbedding(
        embeddings: Float32List(1),
        positionalEmbeddings: Float32List(1),
        scale:
            1024 /
            (decoded.width > decoded.height ? decoded.width : decoded.height),
        originalWidth: decoded.width,
        originalHeight: decoded.height,
      );

  @override
  Future<SamMaskResult> decodeMask(
    SamImageEmbedding embedding, {
    required List<Offset> foregroundPoints,
    List<Offset> backgroundPoints = const [],
  }) async {
    final logits = Float32List(256 * 256)..fillRange(0, 256 * 256, -1);
    final punkt = foregroundPoints.first * embedding.scale / 4;
    for (var y = punkt.dy.round() - 4; y <= punkt.dy.round() + 4; y++) {
      for (var x = punkt.dx.round() - 4; x <= punkt.dx.round() + 4; x++) {
        if (x >= 0 && y >= 0 && x < 256 && y < 256) logits[y * 256 + x] = 1;
      }
    }
    return SamMaskResult(
      logits: logits,
      iouScore: 1,
      sourceEmbedding: embedding,
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

  /// Das Foto, 400×200: oben bläulich, unten rötlich – so verrät der
  /// Graupunkt, welche Hälfte er getroffen hat.
  img.Image foto() {
    final bild = img.Image(width: 400, height: 200);
    for (var y = 0; y < 200; y++) {
      for (var x = 0; x < 400; x++) {
        if (y < 100) {
          bild.setPixelRgb(x, y, 100, 140, 220);
        } else {
          bild.setPixelRgb(x, y, 220, 140, 100);
        }
      }
    }
    return bild;
  }

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_zuschnittmaske_');
    LibraryLocation.nutzeFuerTests(anker: wurzel);
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'l')));
    final jpeg = Uint8List.fromList(img.encodeJpg(foto(), quality: 100));

    // Die Entwicklung liefert das ganze Foto; zugeschnitten und gedreht
    // wird danach in Dart – derselbe Weg wie am Mac.
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
    await datei.writeAsBytes(jpeg);
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
            widthPx: const Value(400),
            heightPx: const Value(200),
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

  Future<void> warte(WidgetTester tester, [int wie = 30]) =>
      tester.runAsync(() async {
        for (var i = 0; i < wie; i++) {
          await tester.pump(const Duration(milliseconds: 25));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });

  Future<void> zeige(
    WidgetTester tester,
    Bildzuschnitt zuschnitt, {
    ModellHalter<SegmentationService>? segmentation,
  }) async {
    await db
        .into(db.developSettings)
        .insert(
          DevelopSettingsCompanion.insert(
            assetId: 'a1',
            cropJson: Value(zuschnitt.json),
            updatedAt: DateTime(2026, 3, 7),
          ),
        );
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final asset = (await tester.runAsync(() => db.assetById('a1')))!;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          theme: buildDarkTheme(),
          home: DevelopScreen(
            asset: asset,
            db: db,
            paths: paths,
            segmentation: segmentation,
          ),
        ),
      );
    });
    // Rendern, Zuschneiden im Isolat, Histogramm.
    await warte(tester, 60);
    expect(find.byType(Image), findsWidgets, reason: 'keine Vorschau');
  }

  Future<void> abbauen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Wo das angezeigte Bild in [flaeche] sitzt: eingepasst, im Rand von
  /// 16 Punkten.
  Rect bildbereich(Rect flaeche, double seitenverhaeltnis) {
    final innen = flaeche.deflate(16);
    if (innen.width / innen.height > seitenverhaeltnis) {
      final b = innen.height * seitenverhaeltnis;
      return Rect.fromLTWH(
        innen.left + (innen.width - b) / 2,
        innen.top,
        b,
        innen.height,
      );
    }
    final h = innen.width / seitenverhaeltnis;
    return Rect.fromLTWH(
      innen.left,
      innen.top + (innen.height - h) / 2,
      innen.width,
      h,
    );
  }

  Offset an(Rect bild, double u, double v) =>
      Offset(bild.left + u * bild.width, bild.top + v * bild.height);

  /// Die eine Maskendatei, die beim „Fertig“ entstanden ist.
  img.Image gespeicherteMaske() {
    final ordner = Directory(paths.absolute('masks').path);
    final dateien = ordner
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png'))
        .toList();
    expect(dateien, hasLength(1));
    return img.decodePng(dateien.single.readAsBytesSync())!;
  }

  /// Der umschliessende Kasten der ausgewählten Bildpunkte.
  Rect ausgewaehlt(img.Image maske) {
    var x0 = maske.width, y0 = maske.height, x1 = -1, y1 = -1;
    for (var y = 0; y < maske.height; y++) {
      for (var x = 0; x < maske.width; x++) {
        if (maske.getPixel(x, y).r > 0) {
          if (x < x0) x0 = x;
          if (y < y0) y0 = y;
          if (x > x1) x1 = x;
          if (y > y1) y1 = y;
        }
      }
    }
    expect(x1, greaterThanOrEqualTo(0), reason: 'die Maske ist leer');
    return Rect.fromLTRB(x0.toDouble(), y0.toDouble(), x1 + 1.0, y1 + 1.0);
  }

  Future<void> fertig(WidgetTester tester) async {
    await tester.tap(
      find.ancestor(
        of: find.text('Fertig'),
        matching: find.byType(FilledButton),
      ),
    );
    await warte(tester, 40);
  }

  /// Der Maskeneditor: die Fläche über dem Bild, die Tipps annimmt.
  Finder derEditor() => find.byWidgetPredicate(
    (w) => w is GestureDetector && w.onTapUp != null && w.child is Stack,
  );

  // Rechts drei Viertel des Fotos, eine Vierteldrehung: angezeigt wird ein
  // Hochformat 2:3 statt des Querformats 2:1.
  final hochkant = Bildzuschnitt(links: 0.25, breite: 0.75, drehungen: 1);

  testWidgets('ein Rechteck landet im Original dort, wo es aufgezogen ist', (
    tester,
  ) async {
    await zeige(tester, hochkant);
    await tester.tap(find.byIcon(Icons.auto_fix_high_outlined));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Rechteck'));
    await tester.pump();

    final bild = bildbereich(tester.getRect(derEditor()), 2 / 3);
    final griff = await tester.startGesture(
      an(bild, 0.1, 0.1),
      kind: PointerDeviceKind.mouse,
    );
    // Die Zieh-Geste beginnt erst, wenn der Zeiger ein Stück gewandert
    // ist, und dort liegt dann der Anker. Mit der Maus sind das wenige
    // Punkte.
    await griff.moveBy(const Offset(3, 3));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 1; i <= 10; i++) {
      await griff.moveTo(
        Offset.lerp(an(bild, 0.1, 0.1), an(bild, 0.4, 0.3), i / 10)!,
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await griff.up();
    await tester.pump();
    await fertig(tester);

    // Angezeigt (u, v) liegt im Ausschnitt bei (v, 1 - u): x von 0,1 bis
    // 0,3 und y von 0,6 bis 0,9. Im Original kommt links das abgeschnittene
    // Viertel dazu.
    final kasten = ausgewaehlt(gespeicherteMaske());
    expect(kasten.left, closeTo(400 * (0.25 + 0.1 * 0.75), 3));
    expect(kasten.right, closeTo(400 * (0.25 + 0.3 * 0.75), 3));
    expect(kasten.top, closeTo(200 * 0.6, 3));
    expect(kasten.bottom, closeTo(200 * 0.9, 3));
    await abbauen(tester);
  });

  testWidgets('die KI-Auswahl wird an ihre Stelle im Original gelegt', (
    tester,
  ) async {
    final halter = ModellHalter<SegmentationService>(
      name: 'SAM',
      installiert: true,
      laden: () async => _Segmentierung(),
      entsorgen: (_) async {},
    );
    await zeige(tester, hochkant, segmentation: halter);
    await tester.tap(find.byIcon(Icons.auto_fix_high_outlined));
    await warte(tester, 30);

    final bild = bildbereich(tester.getRect(derEditor()), 2 / 3);
    await tester.tapAt(an(bild, 0.2, 0.3));
    await warte(tester, 30);
    await fertig(tester);

    final maske = gespeicherteMaske();
    expect(maske.width, closeTo(400, 2), reason: 'nicht im Format des Fotos');
    expect(maske.height, closeTo(200, 2));
    final kasten = ausgewaehlt(maske);
    expect(kasten.center.dx, closeTo(400 * (0.25 + 0.3 * 0.75), 4));
    expect(kasten.center.dy, closeTo(200 * 0.8, 4));
    await abbauen(tester);
  });

  testWidgets('eine gespeicherte Form wird über dem Ausschnitt gezeichnet', (
    tester,
  ) async {
    // Gespeichert im Original: Mitte bei (0,4 | 0,75), ein Rechteck,
    // das im Original doppelt so breit wie hoch ist.
    await db
        .into(db.developMasks)
        .insert(
          DevelopMasksCompanion.insert(
            assetId: 'a1',
            maskRelativePath: 'masks/alt.png',
            label: 'Maske 1',
            createdAt: DateTime(2026, 3, 7),
            shapeDefinitionJson: const Value(
              '{"type":"rectangle","cx":0.4,"cy":0.75,"hw":0.1,"hh":0.1,'
              '"rotation":0.0,"feather":0.2}',
            ),
          ),
        );
    await zeige(tester, hochkant);
    await tester.tap(find.widgetWithText(InputChip, 'Maske 1'));
    await tester.pump();
    await tester.tap(find.text('Form bearbeiten'));
    await tester.pump();

    final zeichnung =
        tester
                .widgetList<CustomPaint>(
                  find.descendant(
                    of: derEditor(),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .map((c) => c.painter)
                .whereType<CustomPainter>()
                .single
            as dynamic;
    final form = zeichnung.shape as RectangleShape;
    // Im Ausschnitt liegt die Mitte bei (0,2 | 0,75); nach der
    // Vierteldrehung bei (1 - 0,75 | 0,2).
    expect(form.centerX, closeTo(0.25, 1e-9));
    expect(form.centerY, closeTo(0.2, 1e-9));
    // Die Halbachsen tauschen mit der Drehung: Die halbe Höhe (20 Punkte)
    // wird zur halben Breite, 20 von 200 angezeigten; die halbe Breite
    // (40 Punkte) zur halben Höhe, 40 von 300.
    expect(form.halfWidth, closeTo(0.1, 1e-9));
    expect(form.halfHeight, closeTo(40 / 300, 1e-9));
    final rahmen = zeichnung.displayRect as Rect;
    expect(rahmen.width / rahmen.height, closeTo(2 / 3, 0.01));
    await abbauen(tester);
  });

  testWidgets('die Helligkeitsauswahl liegt im Ausschnitt über dem Bild', (
    tester,
  ) async {
    await zeige(tester, hochkant);
    await tester.tap(find.byIcon(Icons.auto_fix_high_outlined));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Helligkeit'));
    await warte(tester, 30);
    final bilder = tester
        .widgetList<Image>(
          find.descendant(of: derEditor(), matching: find.byType(Image)),
        )
        .map((b) => b.image)
        .whereType<MemoryImage>()
        .toList();
    expect(bilder, hasLength(2), reason: 'Vorschau und Auswahl');
    final ueberlagerung = img.decodePng(bilder.last.bytes)!;
    // Im Format der Anzeige (2:3), nicht in dem des Originals (2:1).
    expect(ueberlagerung.width / ueberlagerung.height, closeTo(2 / 3, 0.02));
    await abbauen(tester);
  });

  testWidgets('der Graupunkt trifft im zugeschnittenen Bild die Stelle', (
    tester,
  ) async {
    // Die Mitte des Fotos, quadratisch: oben die blaue Hälfte, unten die
    // rote. Im Querformat des Originals gerechnet läge das obere Viertel
    // ausserhalb des Bildes.
    await zeige(tester, Bildzuschnitt(links: 0.25, breite: 0.5));
    await tester.ensureVisible(find.text('Graupunkt wählen'));
    await tester.pump();
    await tester.tap(find.text('Graupunkt wählen'));
    await tester.pump();
    final pipette = find.byWidgetPredicate(
      (w) => w is MouseRegion && w.cursor == SystemMouseCursors.precise,
    );
    final bild = bildbereich(tester.getRect(pipette), 1);
    await tester.runAsync(() async {
      await tester.tapAt(an(bild, 0.5, 0.15));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 25));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    final temperatur = tester
        .widgetList<Slider>(find.byType(Slider))
        .firstWhere((s) => s.min == 2000);
    // Bläulich getroffen: Ausgeglichen wird eine kalte Lichtfarbe, der
    // Regler steht also über 6500 K (höher ist wärmer, #466). Die rote
    // Hälfte ergäbe einen Wert darunter.
    expect(temperatur.value, greaterThan(6500));
    await abbauen(tester);
  });

  group('Vorher und Nachher im selben Ausschnitt (#465)', () {
    double seitenverhaeltnis(Uint8List bytes) {
      final b = img.decodeImage(bytes)!;
      return b.width / b.height;
    }

    testWidgets('gedrückt halten zeigt das Original im Zuschnitt', (
      tester,
    ) async {
      await zeige(tester, hochkant);
      final bild = find.descendant(
        of: find.byType(DevelopScreen),
        matching: find.byType(Image),
      );
      final griff = await tester.startGesture(tester.getCenter(bild.first));
      await tester.pump(const Duration(milliseconds: 600));
      // Rendern und Zuschneiden des Vorher-Bildes, noch gedrückt.
      await warte(tester, 40);
      expect(find.text('Original'), findsOneWidget);
      final gezeigt =
          (tester.widget<Image>(bild.first).image as MemoryImage).bytes;
      // Hochformat 2:3 wie die Vorschau, nicht das Querformat 2:1 des
      // ganzen Fotos.
      expect(seitenverhaeltnis(gezeigt), closeTo(2 / 3, 0.02));
      await griff.up();
      await tester.pump();
      await abbauen(tester);
    });

    testWidgets('der Trennstrich vergleicht denselben Ausschnitt', (
      tester,
    ) async {
      await zeige(tester, hochkant);
      await tester.tap(
        find.byTooltip('Vorher/Nachher nebeneinander (Strich zum Ziehen)'),
      );
      await warte(tester, 40);
      final vergleich = tester.widget<VorherNachherVergleich>(
        find.byType(VorherNachherVergleich),
      );
      expect(seitenverhaeltnis(vergleich.original), closeTo(2 / 3, 0.02));
      expect(
        seitenverhaeltnis(vergleich.original),
        closeTo(seitenverhaeltnis(vergleich.bearbeitet), 0.01),
      );
      await abbauen(tester);
    });
  });
}
