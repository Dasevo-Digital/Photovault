import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/abgleich/protokoll.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/image_editor_screen.dart';
import 'package:photo_vault/services/meldungsdienst.dart';

/// Der Editor bearbeitet das Original, nie die Vorschau (#248).
///
/// Bis 3.49.6 las er bei HEIC, RAW, PSD und Dateien über 32 MB die
/// Vorschau mit höchstens 2048 Pixeln und schrieb sie als neues Original
/// zurück; das alte wurde endgültig gelöscht.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths pfade;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_editor_voll_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(wurzel.path, 'lib')),
    );
  });
  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Uint8List bild(int breite, int hoehe, {bool png = false}) {
    final b = img.Image(width: breite, height: hoehe);
    img.fill(b, color: img.ColorRgb8(90, 140, 200));
    return png ? img.encodePng(b) : img.encodeJpg(b);
  }

  /// Ein „HEIC“, das `package:image` so wenig liest wie ein echtes – nur
  /// der Wandler dieser Tests ([_Wandler]).
  Uint8List heic(int breite, int hoehe) =>
      Uint8List.fromList([..._Wandler.kopf, ...bild(breite, hoehe, png: true)]);

  Future<AssetData> importiere(
    String name,
    Uint8List bytes, {
    Bildwerkzeuge? werkzeuge,
  }) async {
    final quelle = File(p.join(wurzel.path, 'eingang', name))
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    final r = await ImportService(
      db,
      pfade,
      bildwerkzeuge: werkzeuge,
    ).importFile(quelle.path);
    expect(r.outcome, ImportOutcome.imported);
    return (await db.assetById(r.assetId!))!;
  }

  Future<void> warte(WidgetTester tester, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  Future<void> zeige(
    WidgetTester tester,
    AssetData asset, {
    Bildwerkzeuge? werkzeuge,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(melde.verlaufLeeren);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: ImageEditorScreen(
          asset: asset,
          db: db,
          paths: pfade,
          bildwerkzeuge: werkzeuge,
        ),
      ),
    );
    await warte(tester, 20);
  }

  IconButton speichern(WidgetTester tester) => tester.widget<IconButton>(
    find.ancestor(
      of: find.byIcon(Icons.check),
      matching: find.byType(IconButton),
    ),
  );

  Future<void> dreheUndSpeichere(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.rotate_right));
    await warte(tester, 40);
    await tester.tap(find.byTooltip('Speichern'));
    await warte(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await warte(tester, 60);
  }

  Future<void> abbauen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('HEIC: gedreht wird das volle Bild, das HEIC bleibt', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const wandler = _Wandler();
      // Steht für ein HEIC mit 2400 × 1800; die Vorschau des Imports hat
      // 2048 × 1536.
      final a = await importiere(
        'IMG_0001.HEIC',
        heic(2400, 1800),
        werkzeuge: wandler,
      );
      expect(a.previewRelativePath, isNotNull);
      await zeige(tester, a, werkzeuge: wandler);
      expect(speichern(tester).onPressed, isNull, reason: 'noch nichts getan');

      await dreheUndSpeichere(tester);

      final nachher = (await db.assetById(a.id))!;
      final datei = img.decodeJpg(
        await pfade.absolute(nachher.relativePath).readAsBytes(),
      )!;
      expect((datei.width, datei.height), (1800, 2400));
      expect((nachher.widthPx, nachher.heightPx), (1800, 2400));
      final varianten = await db.assetsInStack(nachher.stackId!);
      final alt = varianten.singleWhere((x) => x.id != a.id);
      expect(alt.checksum, a.checksum);
      expect(p.extension(alt.relativePath), '.heic');
      expect(await pfade.absolute(alt.relativePath).exists(), isTrue);
      expect(alt.originalFileName, 'IMG_0001.HEIC');
      await abbauen(tester);
    });
  });

  testWidgets('HEIC ohne Wandler: „nicht lesbar“ statt der Vorschau', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final a = await importiere(
        'IMG_0002.HEIC',
        heic(2400, 1800),
        werkzeuge: const _Wandler(),
      );
      await zeige(tester, a);
      expect(find.byIcon(Icons.rotate_right), findsNothing);
      expect(speichern(tester).onPressed, isNull);
      expect(await db.assetById(a.id), a);
      await abbauen(tester);
    });
  });

  testWidgets('grosses JPEG mit Vorschau: bearbeitet wird das Original', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final a = await importiere('gross.jpg', bild(3000, 2000));
      // Wie nach dem Import einer Datei über 32 MB: eine Vorschau mit
      // 2048 Pixeln steht in der Zeile.
      final vorschau = pfade.previewRelativePath(a.id);
      await pfade.absolute(vorschau).writeAsBytes(bild(2048, 1365));
      await (db.update(db.assets)..where((t) => t.id.equals(a.id))).write(
        AssetsCompanion(previewRelativePath: Value(vorschau)),
      );
      await zeige(tester, (await db.assetById(a.id))!);

      await dreheUndSpeichere(tester);

      final nachher = (await db.assetById(a.id))!;
      expect((nachher.widthPx, nachher.heightPx), (2000, 3000));
      expect(nachher.previewRelativePath, isNull);
      expect(await pfade.absolute(vorschau).exists(), isFalse);
      await abbauen(tester);
    });
  });

  testWidgets('verbunden (#250): der bekannte Hinweis, nichts verloren', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final bytes = bild(300, 200, png: true);
      final a = await importiere('scan.png', bytes);
      final prot = Protokoll(db);
      await prot.richteEin(mitschreiben: 0);
      await prot.richteSchutzEin();
      await zeige(tester, a);

      await dreheUndSpeichere(tester);

      expect(melde.sichtbare.single.text, contains('verbundenen Bibliothek'));
      expect(await pfade.absolute(a.relativePath).readAsBytes(), bytes);
      expect(await db.select(db.assets).get(), [a]);
      await abbauen(tester);
    });
  });
}

/// Wandelt wie das System: Die „HEIC“-Dateien dieser Tests tragen PNG
/// hinter einem Kopf, an dem jeder andere Leser scheitert.
class _Wandler extends KeineBildwerkzeuge {
  const _Wandler();

  static final kopf = 'ftypheic-probe!!'.codeUnits;

  @override
  Future<Uint8List?> convertToJpegBytes(
    File file, {
    int? maxDimension = 2048,
    double quality = 0.9,
    bool objektivkorrektur = true,
  }) async {
    final bytes = await file.readAsBytes();
    if (bytes.length < kopf.length) return null;
    var b = img.decodePng(bytes.sublist(kopf.length));
    if (b == null) return null;
    final kante = b.width > b.height ? b.width : b.height;
    if (maxDimension != null && kante > maxDimension) {
      b = b.width >= b.height
          ? img.copyResize(b, width: maxDimension)
          : img.copyResize(b, height: maxDimension);
    }
    return img.encodeJpg(b, quality: (quality * 100).round());
  }
}
