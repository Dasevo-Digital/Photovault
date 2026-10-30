import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/abgleich/protokoll.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/bearbeitung_speichern.dart';

/// Speichern aus dem Editor verliert kein Original mehr (#248) und lässt
/// in einer verbundenen Kopie nichts kaputt zurück (#250).
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths pfade;
  late ImportService importe;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_bearbeitung_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'library')),
    );
    importe = ImportService(db, pfade);
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Uint8List bild(int breite, int hoehe, int farbe, {bool png = false}) {
    final b = img.Image(width: breite, height: hoehe);
    img.fill(b, color: img.ColorRgb8(farbe, 100, 200));
    return png ? img.encodePng(b) : img.encodeJpg(b);
  }

  /// Importiert wie der Rechner und gibt die Aufnahme zurück.
  Future<AssetData> aufnahme(String name, Uint8List bytes) async {
    final quelle = File(p.join(temp.path, 'eingang', name))
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    final r = await importe.importFile(quelle.path);
    expect(r.outcome, ImportOutcome.imported);
    return (await db.assetById(r.assetId!))!;
  }

  Future<List<String>> restImArbeitsordner() async {
    final d = Directory(p.join(pfade.root.path, '.bearbeitung'));
    if (!await d.exists()) return const [];
    return [
      for (final e in await d.list(recursive: true).toList())
        if (e is File) e.path,
    ];
  }

  test('JPEG: die Aufnahme trägt die Bearbeitung, das Original bleibt als '
      'Variante', () async {
    final altBytes = bild(300, 200, 10);
    final a = await aufnahme('IMG_0001.JPG', altBytes);
    final neu = bild(200, 300, 220);

    final e = await speichereBearbeitung(
      db: db,
      paths: pfade,
      asset: a,
      jpeg: neu,
    );

    final nachher = (await db.assetById(a.id))!;
    expect(nachher.checksum, sha256.convert(neu).toString());
    expect(await pfade.absolute(nachher.relativePath).readAsBytes(), neu);
    expect((nachher.widthPx, nachher.heightPx), (200, 300));
    expect(nachher.fileSizeBytes, neu.length);

    final original = (await db.assetById(e.original!))!;
    expect(original.checksum, a.checksum);
    expect(await pfade.absolute(original.relativePath).readAsBytes(), altBytes);
    expect(original.originalFileName, 'IMG_0001.JPG');
    expect(original.faceScanExcluded, isTrue);

    expect(istVariantenstapel(nachher.stackId), isTrue);
    expect(original.stackId, nachher.stackId);
    expect(nachher.isStackCover, isTrue);
    expect(original.isStackCover, isFalse);
    expect(await restImArbeitsordner(), isEmpty);
  });

  test('PNG: neue .jpg, das PNG bleibt unverändert als Variante', () async {
    final altBytes = bild(300, 200, 40, png: true);
    final a = await aufnahme('scan.png', altBytes);
    final neu = bild(300, 200, 90);

    final e = await speichereBearbeitung(
      db: db,
      paths: pfade,
      asset: a,
      jpeg: neu,
    );

    final nachher = (await db.assetById(a.id))!;
    expect(p.extension(nachher.relativePath), '.jpg');
    expect(await pfade.absolute(a.relativePath).exists(), isFalse);
    final original = (await db.assetById(e.original!))!;
    expect(p.extension(original.relativePath), '.png');
    expect(await pfade.absolute(original.relativePath).readAsBytes(), altBytes);
    expect(original.originalFileName, 'scan.png');
  });

  test('schon in einem Variantenstapel: das Original kommt dazu, die '
      'Hauptversion bleibt', () async {
    final a = await aufnahme('a.jpg', bild(300, 200, 1));
    final b = await aufnahme('b.jpg', bild(300, 200, 2));
    await db.fuehreAus(VariantenBilden('v1', [a.id, b.id], b.id));

    final e = await speichereBearbeitung(
      db: db,
      paths: pfade,
      asset: (await db.assetById(a.id))!,
      jpeg: bild(200, 300, 3),
    );

    final stapel = await db.assetsInStack(variantenstapelId('v1'));
    expect(stapel.map((x) => x.id), unorderedEquals([a.id, b.id, e.original]));
    expect(stapel.where((x) => x.isStackCover).single.id, b.id);
  });

  test('verbunden (#250): abgelehnt, und alles steht wie vorher', () async {
    final altBytes = bild(300, 200, 50, png: true);
    final a = await aufnahme('IMG_0002.PNG', altBytes);
    final vorher = await db.select(db.assets).get();
    final prot = Protokoll(db);
    await prot.richteEin(mitschreiben: 0);
    await prot.richteSchutzEin();

    await expectLater(
      speichereBearbeitung(
        db: db,
        paths: pfade,
        asset: a,
        jpeg: bild(300, 200, 60),
      ),
      throwsA(predicate((e) => '$e'.contains('pv_nur_ueber_server'))),
    );

    expect(await pfade.absolute(a.relativePath).readAsBytes(), altBytes);
    final neuPfad = pfade.originalRelativePath(a.fileCreatedAt, a.id, '.jpg');
    expect(await pfade.absolute(neuPfad).exists(), isFalse);
    expect(
      await File('${pfade.absolute(neuPfad).path}.pv-neu').exists(),
      isFalse,
    );
    expect(await db.select(db.assets).get(), vorher);
    expect(await restImArbeitsordner(), isEmpty);
  });

  test(
    'scheitert der Import des alten Originals, wird zurückgedreht',
    () async {
      final altBytes = bild(300, 200, 70);
      final a = await aufnahme('IMG_0003.JPG', altBytes);

      await expectLater(
        speichereBearbeitung(
          db: db,
          paths: pfade,
          asset: a,
          jpeg: bild(200, 300, 80),
          importe: _ScheiterndeImporte(db, pfade),
        ),
        throwsA(isA<StateError>()),
      );

      final nachher = (await db.assetById(a.id))!;
      expect(nachher, a);
      expect(await pfade.absolute(a.relativePath).readAsBytes(), altBytes);
      expect(await db.select(db.assets).get(), hasLength(1));
      expect(await restImArbeitsordner(), isEmpty);
    },
  );
}

class _ScheiterndeImporte extends ImportService {
  _ScheiterndeImporte(super.db, super.paths);

  @override
  Future<ImportResult> importFile(
    String filePath, {
    String? erwartetePruefsumme,
    ImportDateiangaben? erwarteteAngaben,
    Future<void> Function(String assetId)? beiEintrag,
  }) async => ImportResult(filePath, ImportOutcome.failed, error: 'Probe');
}
