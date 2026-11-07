import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/bildnachlauf.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:kern/services/dateikopf.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;

/// Wandelt, was der Nachlauf verlangt, und merkt sich die Aufrufe.
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
    aufrufe.add(p.basename(file.path));
    if (scheitert) return null;
    return img.encodeJpg(
      img.Image(width: maxDimension!, height: maxDimension * 3 ~/ 4),
    );
  }
}

/// Vorschauen wachsen auf 3000 Punkte (#332): unter neuem Namen, damit die
/// Geräte sie holen, und in Etappen, damit neue Fotos nicht warten.
void main() {
  late Directory ordner;
  late AppDatabase db;
  late StoragePaths paths;
  late _Wandler wandler;
  late ImportService importe;

  setUp(() async {
    ordner = Directory.systemTemp.createTempSync('pv_vorschau_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(ordner);
    wandler = _Wandler();
    importe = ImportService(db, paths, bildwerkzeuge: wandler);
  });

  tearDown(() async {
    await db.close();
    await ordner.delete(recursive: true);
  });

  /// Eine Aufnahme mit [breite] × [hoehe] und einer Vorschau mit [lang]
  /// Punkten an der langen Seite.
  Future<void> aufnahme(
    String id,
    int breite,
    int hoehe,
    int lang, {
    bool gesperrt = false,
    String type = 'IMAGE',
    bool original = true,
  }) async {
    final vorschau = 'previews/$id.jpg';
    await db.insertAsset(
      AssetsCompanion.insert(
        id: id,
        originalFileName: '$id.heic',
        relativePath: 'originals/$id.heic',
        thumbnailRelativePath: Value('thumbnails/$id.jpg'),
        previewRelativePath: Value(vorschau),
        type: type,
        widthPx: Value(breite),
        heightPx: Value(hoehe),
        isLocked: Value(gesperrt),
        fileCreatedAt: DateTime(2026),
        checksum: id,
        importedAt: DateTime(2026),
      ),
    );
    final o = paths.absolute('originals/$id.heic');
    await o.parent.create(recursive: true);
    if (original) await o.writeAsBytes([1, 2, 3]);
    final v = paths.absolute(vorschau);
    await v.parent.create(recursive: true);
    await v.writeAsBytes(
      img.encodeJpg(img.Image(width: lang, height: lang * 3 ~/ 4)),
    );
  }

  Future<AssetData> zeile(String id) async => (await db.assetById(id))!;

  test('neue Vorschau unter neuem Namen, die alte geht', () async {
    await aufnahme('a', 8064, 6048, 2048);
    final r = await vergroessereVorschauen(db, paths, importe);
    expect(r.neu, 1);
    expect(r.weiter, isNull);
    final a = await zeile('a');
    expect(a.previewRelativePath, 'previews/a-2.jpg');
    expect(a.thumbnailRelativePath, 'thumbnails/a.jpg', reason: 'bleibt');
    expect(paths.absolute('previews/a.jpg').existsSync(), isFalse);
    final masse = jpegMasse(
      await paths.absolute('previews/a-2.jpg').readAsBytes(),
    );
    expect(masse?.$1, vorschauKante);
  });

  test('lässt stehen, was nicht wachsen kann', () async {
    await aufnahme('klein', 2000, 1500, 2000);
    await aufnahme('passt', 2600, 1950, 2600);
    await aufnahme('fertig', 8064, 6048, 3000);
    await aufnahme('gesperrt', 8064, 6048, 2048, gesperrt: true);
    await aufnahme('video', 3840, 2160, 2048, type: 'VIDEO');
    await aufnahme('fehlt', 8064, 6048, 2048, original: false);
    final r = await vergroessereVorschauen(db, paths, importe);
    expect(r.neu, 0);
    expect(r.weiter, isNull);
    expect(wandler.aufrufe, isEmpty);
    expect((await zeile('fertig')).previewRelativePath, 'previews/fertig.jpg');
  });

  test('läuft in Etappen und schafft je Etappe mindestens eine', () async {
    for (final id in ['a', 'b', 'c']) {
      await aufnahme(id, 8064, 6048, 2048);
    }
    final erste = await vergroessereVorschauen(
      db,
      paths,
      importe,
      frist: Duration.zero,
    );
    expect(erste.neu, 1);
    expect(erste.weiter, 'a');
    final zweite = await vergroessereVorschauen(
      db,
      paths,
      importe,
      ab: erste.weiter,
      frist: Duration.zero,
    );
    expect(zweite.neu, 1);
    expect(zweite.weiter, 'b');
    final dritte = await vergroessereVorschauen(
      db,
      paths,
      importe,
      ab: zweite.weiter,
      frist: Duration.zero,
    );
    expect(dritte.neu, 1);
    expect(dritte.weiter, isNull);
    expect(wandler.aufrufe, ['a.heic', 'b.heic', 'c.heic']);
  });

  test('nach einem Neustart: was schon gross ist, wird übersprungen', () async {
    for (final id in ['a', 'b']) {
      await aufnahme(id, 8064, 6048, 2048);
    }
    await vergroessereVorschauen(db, paths, importe, frist: Duration.zero);
    wandler.aufrufe.clear();
    final r = await vergroessereVorschauen(db, paths, importe);
    expect(r.neu, 1);
    expect(wandler.aufrufe, ['b.heic']);
  });

  test('ohne Wandler bleibt die alte Vorschau', () async {
    wandler.scheitert = true;
    await aufnahme('a', 8064, 6048, 2048);
    final r = await vergroessereVorschauen(db, paths, importe);
    expect(r.neu, 0);
    expect(r.weiter, isNull);
    expect((await zeile('a')).previewRelativePath, 'previews/a.jpg');
    expect(paths.absolute('previews/a.jpg').existsSync(), isTrue);
  });

  test(
    'abbrechen hält an, und es geht bei derselben Aufnahme weiter',
    () async {
      await aufnahme('a', 8064, 6048, 2048);
      final r = await vergroessereVorschauen(
        db,
        paths,
        importe,
        abbrechen: () => true,
      );
      expect(r.neu, 0);
      expect(r.weiter, '');
      final weiter = await vergroessereVorschauen(
        db,
        paths,
        importe,
        ab: r.weiter,
      );
      expect(weiter.neu, 1);
    },
  );
}
