import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/exif_camera.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Prüft, dass jede neue `countX...()`-Zählmethode (siehe
/// BackgroundTasksScreen) exakt mit `.length` der bereits bestehenden,
/// gleichnamigen Listen-Methode übereinstimmt – die Zählmethoden sind
/// bewusst als eigenständige SQL-COUNT-Queries geschrieben (nicht als
/// `.length` auf der Liste), damit sich das WHERE genau einmal tippen ließe
/// wäre riskant: dieser Test stellt sicher, dass keine der beiden Kopien
/// vom WHERE der jeweils anderen abweicht.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late ImportService import;
  var nextByte = 0;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('photo_vault_bg_task_counts_test_');
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

  /// Vergleicht jede count-Methode mit der .length ihrer Listen-Schwester –
  /// beide MÜSSEN in jedem Zustand exakt übereinstimmen.
  Future<void> expectCountsMatchLists() async {
    expect(await db.countLocationBackfill(), (await db.assetsForLocationBackfill()).length);
    expect(await db.countCameraMetadataBackfill(), (await db.assetsForCameraMetadataBackfill()).length);
    expect(await db.countOcrBackfill(), (await db.assetsForOcrBackfill()).length);
    expect(await db.countCaptionBackfill(), (await db.assetsForCaptionBackfill()).length);
    expect(await db.countCaptionTranslation(),
        (await db.assetsForCaptionTranslation()).length);
    expect(await db.countBlurBackfill(), (await db.assetsForBlurBackfill()).length);
    expect(await db.countXmpExport(), (await db.assetsForXmpExport()).length);
    expect(await db.countLocationNameBackfill(), (await db.assetsForLocationNameBackfill()).length);
    expect(await db.countUnlinkedAssetsOfType('IMAGE'), (await db.unlinkedAssetsOfType('IMAGE')).length);
    expect(await db.countThumbnailRegen(onlyMissing: true),
        (await db.assetsForThumbnailRegen(onlyMissing: true)).length);
    expect(await db.countThumbnailRegen(onlyMissing: false),
        (await db.assetsForThumbnailRegen(onlyMissing: false)).length);
    expect(await db.countFaceScan(onlyNew: true), (await db.assetsForFaceScan(onlyNew: true)).length);
    expect(await db.countFaceScan(onlyNew: false), (await db.assetsForFaceScan(onlyNew: false)).length);
    expect(await db.countAssetsWithDevelopSettings(), (await db.assetsWithDevelopSettings()).length);
    expect(await db.countEmbeddingBackfill(), (await db.assetsForEmbeddingBackfill()).length);
    expect(await db.countAiTagging(onlyUntagged: true), (await db.assetsForAiTagging(onlyUntagged: true)).length);
    expect(await db.countAiTagging(onlyUntagged: false), (await db.assetsForAiTagging(onlyUntagged: false)).length);
  }

  test('alle count-Methoden stimmen mit ihren Listen-Methoden überein – vor jeder Auswertung', () async {
    await importPhoto('a.jpg');
    await importPhoto('b.jpg');
    await expectCountsMatchLists();
  });

  test('alle count-Methoden stimmen mit ihren Listen-Methoden überein – nach jeder Auswertung', () async {
    final a = await importPhoto('a.jpg');
    await importPhoto('b.jpg');

    await db.setLocation(a.id, 52.5, 13.4);
    await db.setLocationNames(a.id, country: 'Deutschland', city: 'Berlin');
    await db.setCameraMetadata(a.id, const CameraInfo(make: 'Canon', model: 'EOS R5'));
    await db.setOcrResult(a.id, 'Hallo Welt');
    await db.setAiCaption(a.id, 'a cat sitting on a table');
    await db.setSharpnessScore(a.id, 42.0);
    await db.updateThumbnailInfo(a.id, thumbnailRelativePath: 'thumb/a.jpg');
    await db.markFacesScanned([a.id]);
    await db.saveEmbedding(a.id, Float32List.fromList(List.filled(512, 0.1)));
    await db.tagAsset(a.id, 'Urlaub');
    await db.saveDevelopResult(
      a.id,
      settings: DevelopSettingsCompanion.insert(assetId: a.id, updatedAt: DateTime.now()),
      developedRelativePath: 'developed/${a.id}.jpg',
    );

    await expectCountsMatchLists();
  });

  test('Live-Photo-Verknüpfung ändert countUnlinkedAssetsOfType wie erwartet', () async {
    final image = await importPhoto('c.jpg');
    final video = await importPhoto('c.mov');
    expect(await db.countUnlinkedAssetsOfType('IMAGE'), 1);
    await db.linkAssets(image.id, video.id);
    expect(await db.countUnlinkedAssetsOfType('IMAGE'), 0);
    await expectCountsMatchLists();
  });
}
