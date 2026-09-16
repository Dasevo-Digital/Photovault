import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Prüft die Einzel-/Bulk-Setter für Bewertung, Farbmarkierung und die
/// Sammelbearbeitungs-Felder (Beschreibung/Datum/Ort) sowie die OCR-/
/// Unschärfe-Backfill-Abfragen – insbesondere, dass die Bulk-Varianten
/// tatsächlich ALLE übergebenen Assets in einem Write treffen und andere
/// Assets unangetastet lassen.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late ImportService import;
  var nextByte = 0;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('photo_vault_bulk_test_');
    db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
    import = ImportService(db, paths);
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<AssetData> importPhoto(String name) async {
    final incoming = Directory(p.join(tempRoot.path, 'incoming'))..createSync(recursive: true);
    final file = File(p.join(incoming.path, name))..writeAsBytesSync([1, 2, 3, nextByte++]);
    final result = await import.importFile(file.path);
    expect(result.outcome, ImportOutcome.imported);
    return (await db.assetById(result.assetId!))!;
  }

  test('setRating/setColorLabel setzen einzelne Assets, ohne andere zu verändern', () async {
    final a = await importPhoto('a.jpg');
    final b = await importPhoto('b.jpg');

    await db.setRating(a.id, 4);
    await db.setColorLabel(a.id, 'red');

    expect((await db.assetById(a.id))!.rating, 4);
    expect((await db.assetById(a.id))!.colorLabel, 'red');
    expect((await db.assetById(b.id))!.rating, 0);
    expect((await db.assetById(b.id))!.colorLabel, isNull);
  });

  test('setRating mit 0 setzt die Bewertung zurück', () async {
    final a = await importPhoto('a.jpg');
    await db.setRating(a.id, 5);
    await db.setRating(a.id, 0);
    expect((await db.assetById(a.id))!.rating, 0);
  });

  test('setRatingBulk/setColorLabelBulk treffen alle übergebenen Assets in einem Write', () async {
    final a = await importPhoto('a.jpg');
    final b = await importPhoto('b.jpg');
    final untouched = await importPhoto('c.jpg');

    await db.setRatingBulk([a.id, b.id], 3);
    await db.setColorLabelBulk([a.id, b.id], 'blue');

    expect((await db.assetById(a.id))!.rating, 3);
    expect((await db.assetById(b.id))!.rating, 3);
    expect((await db.assetById(a.id))!.colorLabel, 'blue');
    expect((await db.assetById(b.id))!.colorLabel, 'blue');
    expect((await db.assetById(untouched.id))!.rating, 0);
    expect((await db.assetById(untouched.id))!.colorLabel, isNull);
  });

  test('setDescriptionBulk/setFileCreatedAtBulk/setLocationBulk wirken auf alle übergebenen Assets', () async {
    final a = await importPhoto('a.jpg');
    final b = await importPhoto('b.jpg');
    final untouched = await importPhoto('c.jpg');
    final date = DateTime(2026, 1, 1, 12);

    await db.setDescriptionBulk([a.id, b.id], 'Urlaub');
    await db.setFileCreatedAtBulk([a.id, b.id], date);
    await db.setLocationBulk([a.id, b.id], 48.85, 2.35);

    for (final id in [a.id, b.id]) {
      final asset = (await db.assetById(id))!;
      expect(asset.description, 'Urlaub');
      expect(asset.fileCreatedAt, date);
      expect(asset.latitude, 48.85);
      expect(asset.longitude, 2.35);
    }
    final untouchedAsset = (await db.assetById(untouched.id))!;
    expect(untouchedAsset.description, isNull);
    expect(untouchedAsset.latitude, isNull);
  });

  test('setOcrResult setzt Text + ocrScanned in einem Write, assetsForOcrBackfill findet nur ungescannte',
      () async {
    final scanned = await importPhoto('a.jpg');
    final unscanned = await importPhoto('b.jpg');

    // Seit Schema 60 gehören die Stellen im Bild dazu. Ohne sie gilt das
    // Foto als nur halb erledigt und kommt wieder dran – das ist genau der
    // Weg, auf dem die vor Schema 60 erkannten Texte ihre Kästen bekommen
    // (siehe textstellen_test.dart).
    await db.setOcrResult(scanned.id, 'Hallo Welt',
        boxen: '[{"t":"Hallo Welt","x":0.1,"y":0.1,"b":0.3,"h":0.1}]');

    final scannedAsset = (await db.assetById(scanned.id))!;
    expect(scannedAsset.ocrText, 'Hallo Welt');
    expect(scannedAsset.ocrScanned, isTrue);

    final backlog = await db.assetsForOcrBackfill();
    expect(backlog.map((a) => a.id), [unscanned.id]);
  });

  test('setOcrResult mit leerem String markiert trotzdem als gescannt (kein Text gefunden ist ein gültiges '
      'Ergebnis)', () async {
    final a = await importPhoto('a.jpg');
    await db.setOcrResult(a.id, '');

    final asset = (await db.assetById(a.id))!;
    expect(asset.ocrText, '');
    expect(asset.ocrScanned, isTrue);
    expect(await db.assetsForOcrBackfill(), isEmpty);
  });

  test(
      'setAiCaption setzt Caption + aiCaptionScanned in einem Write, '
      'assetsForCaptionBackfill findet nur ungescannte', () async {
    final captioned = await importPhoto('a.jpg');
    final uncaptioned = await importPhoto('b.jpg');

    await db.setAiCaption(captioned.id, 'a dog running on a beach');

    final captionedAsset = (await db.assetById(captioned.id))!;
    expect(captionedAsset.aiCaption, 'a dog running on a beach');
    expect(captionedAsset.aiCaptionScanned, isTrue);

    final backlog = await db.assetsForCaptionBackfill();
    expect(backlog.map((a) => a.id), [uncaptioned.id]);
  });

  test('setSharpnessScore setzt den Score, assetsForBlurBackfill findet nur Assets ohne Score', () async {
    final scored = await importPhoto('a.jpg');
    final unscored = await importPhoto('b.jpg');

    await db.setSharpnessScore(scored.id, 250.0);

    expect((await db.assetById(scored.id))!.sharpnessScore, 250.0);
    final backlog = await db.assetsForBlurBackfill();
    expect(backlog.map((a) => a.id), [unscored.id]);
  });
}
