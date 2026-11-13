import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/asset_display_path.dart';
import 'package:kern/services/bildnachlauf.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:kern/services/dateikopf.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/platform/desktop_image_tools.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;

/// Wandelt jede Datei in ein kleines rotes JPEG und merkt sich, was
/// verlangt wurde. Rot, damit sich zeigt, was aus dem Ansichtsbild kommt
/// (#379): Die Originale der Tests sind schwarz.
class _Wandler extends KeineBildwerkzeuge {
  final aufrufe = <String>[];
  var scheitert = false;

  @override
  Future<Uint8List?> convertToJpegBytes(
    File file, {
    int? maxDimension = 2048,
    double quality = 0.9,
    bool objektivkorrektur = true,
  }) async {
    aufrufe.add('${p.basename(file.path)}@$maxDimension');
    if (scheitert) return null;
    final rot = img.fill(
      img.Image(width: 300, height: 20),
      color: img.ColorRgb8(255, 0, 0),
    );
    return Uint8List.fromList(img.encodeJpg(rot));
  }
}

/// Ein JPEG von [breite] × [hoehe] Punkten, mit Nullen hinter seinem Ende
/// auf [bytes] gebracht: so gross wie ein Kamerafoto, ohne dessen
/// Rechenzeit.
Uint8List _jpeg(int breite, int hoehe, {int bytes = 0, img.Image? bild}) {
  final roh = img.encodeJpg(bild ?? img.Image(width: breite, height: hoehe));
  if (roh.length >= bytes) return roh;
  return Uint8List(bytes)..setRange(0, roh.length, roh);
}

/// [jpeg] mit [anhaenge] leeren APP15-Abschnitten zu je 64 KB vor allem
/// anderen, auf [bytes] gebracht wie bei [_jpeg]. So weit hinten stehen die
/// Masse sonst nur bei Telefonen, die eine Tiefenkarte im XMP ablegen.
Uint8List _mitAnhaengen(Uint8List jpeg, int anhaenge, {required int bytes}) {
  final roh = [
    ...jpeg.sublist(0, 2),
    for (var i = 0; i < anhaenge; i++) ...[
      0xFF, 0xEF, 0xFF, 0xFF, ...Uint8List(0xFFFD), //
    ],
    ...jpeg.sublist(2),
  ];
  return Uint8List(bytes)..setRange(0, roh.length, roh);
}

/// Der Anfang einer HEIC-Datei – das, woran der Import ihren Inhalt
/// erkennt.
Uint8List _heic(int bytes) =>
    Uint8List(bytes)..setRange(0, 12, [0, 0, 0, 24, ...'ftypheic'.codeUnits]);

const _gross = 5 * 1024 * 1024;

/// Ein grosses JPEG bekommt am Server ein Ansichtsbild (#333): Handy und
/// Browser luden bis dahin das ganze Original, aus einer Kamera oft 8 bis
/// 20 MB, ehe das Foto erschien. Auswertungen und Rechner bleiben beim
/// Original.
void main() {
  late Directory ordner;
  late AppDatabase db;
  late StoragePaths paths;
  late _Wandler wandler;
  late ImportService server;

  setUp(() async {
    ordner = Directory.systemTemp.createTempSync('pv_ansichtsbild_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(
      Directory(p.join(ordner.path, 'lib')),
    );
    wandler = _Wandler();
    server = ImportService(
      db,
      paths,
      bildwerkzeuge: wandler,
      ansichtsbilder: true,
    );
  });

  tearDown(() async {
    await db.close();
    await ordner.delete(recursive: true);
  });

  Future<AssetData> importiere(
    ImportService importe,
    String name,
    Uint8List bytes,
  ) async {
    final quelle = File(p.join(ordner.path, 'eingang', name))
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    final r = await importe.importFile(quelle.path);
    expect(r.outcome, ImportOutcome.imported, reason: r.error);
    return (await db.assetById(r.assetId!))!;
  }

  /// Ob die Miniatur von [a] aus dem roten Bild des Wandlers stammt und
  /// nicht aus dem schwarzen Original (#379).
  bool miniaturAusDemAnsichtsbild(AssetData a) {
    final m = img.decodeJpg(
      paths.absolute(a.thumbnailRelativePath!).readAsBytesSync(),
    )!;
    final punkt = m.getPixel(m.width ~/ 2, m.height ~/ 2);
    return punkt.r > 200 && punkt.g < 60;
  }

  group('beim Import', () {
    test('ein grosses JPEG bekommt ein Ansichtsbild', () async {
      final a = await importiere(
        server,
        'DSC_0001.JPG',
        _jpeg(3200, 100, bytes: _gross),
      );

      expect(a.previewRelativePath, 'previews/${a.id}-ansicht.jpg');
      expect(paths.absolute(a.previewRelativePath!).existsSync(), isTrue);
      expect(wandler.aufrufe, ['${a.id}.jpg@$vorschauKante']);
      expect(
        [a.widthPx, a.heightPx],
        [3200, 100],
        reason: 'die Masse bleiben die des Originals',
      );
      // Die Miniatur kommt aus dem Ansichtsbild, statt dass Dart dafür das
      // ganze Original dekodiert (#379).
      expect(miniaturAusDemAnsichtsbild(a), isTrue);

      // Handy und Browser zeigen das Ansichtsbild und holen zum Zoomen das
      // Original, das sie selbst lesen.
      expect(hatAnsichtsbild(a), isTrue);
      expect(displayRelativePath(a), a.previewRelativePath);
      expect(zeigtVorschau(a), isTrue);
      expect(vollbildQuelle(a), a.relativePath);
      // Rechner und Auswertungen bleiben beim Original.
      expect(displayRelativePath(a, mitAnsichtsbild: false), a.relativePath);
      expect(lesbarerPfad(a), a.relativePath);
    });

    test('am Rechner nicht: Dort liegt das Original auf der Platte', () async {
      final a = await importiere(
        ImportService(db, paths, bildwerkzeuge: wandler),
        'DSC_0002.jpg',
        _jpeg(3200, 100, bytes: _gross),
      );
      expect(a.previewRelativePath, isNull);
      expect(wandler.aufrufe, isEmpty);
    });

    test('nur, wo es sich lohnt', () async {
      final klein = await importiere(server, 'klein.jpg', _jpeg(3200, 100));
      final kurz = await importiere(
        server,
        'kurz.jpg',
        _jpeg(vorschauKante, 100, bytes: _gross),
      );
      expect(klein.previewRelativePath, isNull, reason: 'wenige Bytes');
      expect(
        kurz.previewRelativePath,
        isNull,
        reason: 'das Ansichtsbild wäre so gross wie das Original',
      );
      expect(wandler.aufrufe, isEmpty);
      expect(lohntAnsichtsbild(_gross, 100, 3001), isTrue, reason: 'hoch');
      expect(lohntAnsichtsbild(ansichtsbildAb, 6000, 4000), isFalse);
      expect(lohntAnsichtsbild(_gross, null, null), isFalse);
    });

    test('scheitert die Wandlung, kommt das Foto trotzdem herein', () async {
      wandler.scheitert = true;
      final a = await importiere(
        server,
        'DSC_0003.jpg',
        _jpeg(3200, 100, bytes: _gross),
      );
      expect(a.previewRelativePath, isNull);
      expect(a.thumbnailRelativePath, isNotNull);
      expect(displayRelativePath(a), a.relativePath);
      expect([a.widthPx, a.heightPx], [3200, 100]);
      expect(
        wandler.aufrufe,
        hasLength(1),
        reason: 'nicht ein zweites Mal für die Miniatur aus dem Original',
      );
    });

    test('die Masse kommen aus dem Kopf, nach seiner Lage (#379)', () async {
      // Quer gespeichert, laut EXIF hochkant. Das Ansichtsbild ist schon
      // gedreht und sagt nichts über die Grösse des Originals.
      final bild = img.Image(width: 3200, height: 100);
      bild.exif.imageIfd.orientation = 6;
      final a = await importiere(
        server,
        'DSC_0006.jpg',
        _jpeg(0, 0, bytes: _gross, bild: bild),
      );
      expect([a.widthPx, a.heightPx], [100, 3200]);
      expect(a.previewRelativePath, 'previews/${a.id}-ansicht.jpg');
      expect(miniaturAusDemAnsichtsbild(a), isTrue);
    });

    test('stehen die Masse nicht im Kopf, geht es wie bisher', () async {
      final a = await importiere(
        server,
        'PXL_0007.jpg',
        _mitAnhaengen(
          img.encodeJpg(img.Image(width: 3200, height: 100)),
          5,
          bytes: _gross,
        ),
      );
      expect(a.previewRelativePath, 'previews/${a.id}-ansicht.jpg');
      expect([a.widthPx, a.heightPx], [3200, 100]);
      expect(
        miniaturAusDemAnsichtsbild(a),
        isFalse,
        reason: 'aus dem Original',
      );
      expect(wandler.aufrufe, hasLength(1));
    });

    test(
      'ein HEIC unter .jpg behält seine Vorschau, und aus ihr wird gerechnet',
      () async {
        final a = await importiere(server, 'IMG_0004.jpg', _heic(_gross));

        expect(a.previewRelativePath, 'previews/${a.id}.jpg');
        expect(hatAnsichtsbild(a), isFalse);
        expect(
          lesbarerPfad(a),
          a.previewRelativePath,
          reason: 'das Original liest Dart nicht',
        );
        expect(
          displayRelativePath(a, mitAnsichtsbild: false),
          'previews/${a.id}.jpg',
        );
      },
    );
  });

  group('der Nachlauf für vorhandene Bibliotheken', () {
    /// Ein Foto ohne Vorschau, wie es vor #333 in die Bibliothek kam.
    Future<void> aufnahme(
      String id, {
      String endung = 'jpg',
      int breite = 6000,
      int hoehe = 4000,
      int bytes = _gross,
      Uint8List? inhalt,
      String? vorschau,
      bool gesperrt = false,
      bool imPapierkorb = false,
      String? entwickelt,
      String? restauriert,
      bool original = true,
    }) async {
      final relativ = 'originals/$id.$endung';
      await db.insertAsset(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.$endung',
          relativePath: relativ,
          thumbnailRelativePath: Value('thumbnails/$id.jpg'),
          previewRelativePath: Value(vorschau),
          type: 'IMAGE',
          widthPx: Value(breite),
          heightPx: Value(hoehe),
          fileSizeBytes: Value(bytes),
          isLocked: Value(gesperrt),
          isTrashed: Value(imPapierkorb),
          developedRelativePath: Value(entwickelt),
          restoredRelativePath: Value(restauriert),
          fileCreatedAt: DateTime(2026),
          checksum: id,
          importedAt: DateTime(2026),
        ),
      );
      if (!original) return;
      paths.absolute(relativ)
        ..createSync(recursive: true)
        ..writeAsBytesSync(inhalt ?? _jpeg(64, 48, bytes: bytes));
    }

    Future<AssetData> zeile(String id) async => (await db.assetById(id))!;

    test('ergänzt, was eines braucht, und lässt alles andere', () async {
      await aufnahme('a');
      await aufnahme('klein', bytes: 3 * 1024 * 1024);
      await aufnahme('kurz', breite: 3000, hoehe: 2000);
      await aufnahme('heic', endung: 'heic', vorschau: 'previews/heic.jpg');
      await aufnahme('gesperrt', gesperrt: true);
      await aufnahme('fehlt', original: false);
      await aufnahme('verkleidet', inhalt: _heic(_gross));

      final r = await ergaenzeAnsichtsbilder(db, paths, server);

      expect(r.neu, 1);
      expect(r.weiter, isNull);
      expect(wandler.aufrufe, ['a.jpg@$vorschauKante']);
      final a = await zeile('a');
      expect(a.previewRelativePath, 'previews/a-ansicht.jpg');
      expect(paths.absolute('previews/a-ansicht.jpg').existsSync(), isTrue);
      expect(a.thumbnailRelativePath, 'thumbnails/a.jpg', reason: 'bleibt');
      expect([a.widthPx, a.heightPx], [6000, 4000], reason: 'bleiben');
      expect(
        (await zeile('verkleidet')).previewRelativePath,
        isNull,
        reason: 'unter .jpg, aber kein JPEG',
      );
      expect((await zeile('heic')).previewRelativePath, 'previews/heic.jpg');

      // Ein zweiter Lauf findet nichts mehr.
      wandler.aufrufe.clear();
      final noch = await ergaenzeAnsichtsbilder(db, paths, server);
      expect(noch.neu, 0);
      expect(wandler.aufrufe, isEmpty);
    });

    test('auch im Papierkorb, entwickelt oder restauriert (#382)', () async {
      // Der Nachlauf läuft je Bibliothek nur einmal. Was er übergeht, bekäme
      // nach dem Zurückholen, Zurücksetzen oder Verwerfen der Restaurierung
      // nie ein Ansichtsbild, und Handy und Browser lüden das ganze
      // Original.
      await aufnahme('papierkorb', imPapierkorb: true);
      await aufnahme('entwickelt', entwickelt: 'developed/entwickelt.jpg');
      await aufnahme('restauriert', restauriert: 'restored/restauriert.jpg');
      await aufnahme('a');

      final r = await ergaenzeAnsichtsbilder(db, paths, server);

      expect(r.neu, 4);
      for (final id in ['a', 'papierkorb', 'entwickelt', 'restauriert']) {
        expect((await zeile(id)).previewRelativePath, isNotNull, reason: id);
      }
    });

    test('das Vergrössern alter Vorschauen lässt Ansichtsbilder', () async {
      await aufnahme('a', vorschau: 'previews/a-ansicht.jpg');
      paths.absolute('previews/a-ansicht.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync(_jpeg(64, 48));
      final r = await vergroessereVorschauen(db, paths, server);
      expect(r.neu, 0);
      expect(wandler.aufrufe, isEmpty);
      expect((await zeile('a')).previewRelativePath, 'previews/a-ansicht.jpg');
    });

    test('läuft in Etappen, und jede schafft mindestens eine', () async {
      for (final id in ['a', 'b', 'c']) {
        await aufnahme(id);
      }
      String? ab;
      final weiter = <String?>[];
      for (var i = 0; i < 3; i++) {
        final r = await ergaenzeAnsichtsbilder(
          db,
          paths,
          server,
          ab: ab,
          frist: Duration.zero,
        );
        expect(r.neu, 1);
        weiter.add(ab = r.weiter);
      }
      expect(weiter, ['a', 'b', null]);
      expect(wandler.aufrufe, [
        for (final id in ['a', 'b', 'c']) '$id.jpg@$vorschauKante',
      ]);
    });

    test('scheitert der Wandler, endet die Etappe trotzdem', () async {
      wandler.scheitert = true;
      await aufnahme('a');
      await aufnahme('b');
      final erste = await ergaenzeAnsichtsbilder(
        db,
        paths,
        server,
        frist: Duration.zero,
      );
      expect((erste.neu, erste.weiter), (0, 'a'), reason: 'nach einem Versuch');
      final zweite = await ergaenzeAnsichtsbilder(
        db,
        paths,
        server,
        ab: erste.weiter,
        frist: Duration.zero,
      );
      expect(
        (zweite.neu, zweite.weiter),
        (0, null),
        reason: 'fertig, ohne jedes Foto wieder zu versuchen',
      );
      expect(wandler.aufrufe, ['a.jpg@$vorschauKante', 'b.jpg@$vorschauKante']);
      expect((await zeile('a')).previewRelativePath, isNull);
    });

    test(
      'abbrechen hält an, und es geht bei derselben Aufnahme weiter',
      () async {
        await aufnahme('a');
        final r = await ergaenzeAnsichtsbilder(
          db,
          paths,
          server,
          abbrechen: () => true,
        );
        expect((r.neu, r.weiter), (0, ''));
        final weiter = await ergaenzeAnsichtsbilder(
          db,
          paths,
          server,
          ab: r.weiter,
        );
        expect(weiter.neu, 1);
      },
    );
  });

  group('mit dem echten Wandler', () {
    setUp(() => DesktopImageTools.stelleWerkzeuge({}));
    tearDown(DesktopImageTools.vergissWerkzeuge);

    test('gedreht nach dem EXIF und ohne Ort, wie jede Vorschau', () async {
      // Quer gespeichert, laut EXIF um 90° zu drehen, mit Aufnahmeort.
      final bild = img.Image(width: 3200, height: 100);
      bild.exif.imageIfd.orientation = 6;
      bild.exif.gpsIfd.gpsLatitude = 52.370216;
      bild.exif.gpsIfd.gpsLongitude = 9.735603;
      final original = paths.absolute('originals/o.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync(_jpeg(0, 0, bytes: _gross, bild: bild));
      final importe = ImportService(
        db,
        paths,
        bildwerkzeuge: const WerkzeugBildwerkzeuge(),
        ansichtsbilder: true,
      );

      final relativ = await importe.erzeugeAnsichtsbild(
        original,
        'o',
        breite: 100,
        hoehe: 3200,
      );

      expect(relativ, 'previews/o-ansicht.jpg');
      final ansicht = img.decodeJpg(
        paths.absolute(relativ!).readAsBytesSync(),
      )!;
      expect(ansicht.height, greaterThan(ansicht.width), reason: 'hochkant');
      expect(math.max(ansicht.width, ansicht.height), vorschauKante);
      expect(ansicht.exif.gpsIfd.gpsLatitude, isNull, reason: 'ohne Ort');
      expect(ansicht.exif.imageIfd.orientation ?? 1, 1);
    });

    test('die Miniatur aus dem Ansichtsbild ist einmal gedreht, nicht zweimal '
        '(#379)', () async {
      // Quer gespeichert, links rot und rechts blau, laut EXIF um 90° im
      // Uhrzeigersinn zu drehen: hochkant, oben rot.
      final bild = img.Image(width: 3200, height: 100);
      img.fillRect(
        bild,
        x1: 0,
        y1: 0,
        x2: 1599,
        y2: 99,
        color: img.ColorRgb8(255, 0, 0),
      );
      img.fillRect(
        bild,
        x1: 1600,
        y1: 0,
        x2: 3199,
        y2: 99,
        color: img.ColorRgb8(0, 0, 255),
      );
      bild.exif.imageIfd.orientation = 6;
      final importe = ImportService(
        db,
        paths,
        bildwerkzeuge: const WerkzeugBildwerkzeuge(),
        ansichtsbilder: true,
      );

      final a = await importiere(
        importe,
        'DSC_0008.jpg',
        _jpeg(0, 0, bytes: _gross, bild: bild),
      );

      expect(a.previewRelativePath, 'previews/${a.id}-ansicht.jpg');
      expect([a.widthPx, a.heightPx], [100, 3200]);
      final roh = paths.absolute(a.thumbnailRelativePath!).readAsBytesSync();
      expect(jpegExifLage(roh) ?? 1, 1, reason: 'kein Betrachter dreht nach');
      final miniatur = img.decodeJpg(roh)!;
      expect(miniatur.height, 400);
      expect(miniatur.width, lessThan(miniatur.height), reason: 'hochkant');
      final oben = miniatur.getPixel(miniatur.width ~/ 2, 50);
      final unten = miniatur.getPixel(miniatur.width ~/ 2, 350);
      expect([oben.r > 200, oben.b < 60], [true, true], reason: 'oben rot');
      expect([unten.b > 200, unten.r < 60], [true, true], reason: 'unten blau');
    });
  });
}
