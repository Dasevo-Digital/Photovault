import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/exif_camera.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Prüft die DB-Seite der Kamera-Metadaten: [AppDatabase.setCameraMetadata]
/// speichert alle Felder korrekt, und
/// [AppDatabase.assetsForCameraMetadataBackfill] findet nur Fotos, die noch
/// keine Kamera-Angaben haben (das Backfill-Werkzeug in den Werkzeugen).
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late ImportService import;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('photo_vault_camera_metadata_test_');
    db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
    import = ImportService(db, paths);
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  var nextByte = 0;

  Future<String> importPhoto(String name) async {
    final incoming = Directory(p.join(tempRoot.path, 'incoming'))..createSync(recursive: true);
    final file = File(p.join(incoming.path, name))..writeAsBytesSync([1, 2, 3, nextByte++]);
    final result = await import.importFile(file.path);
    expect(result.outcome, ImportOutcome.imported);
    return result.assetId!;
  }

  test('setCameraMetadata speichert alle Felder, assetsForCameraMetadataBackfill findet nur Unbearbeitetes', () async {
    final withoutId = await importPhoto('ohne_kamera.jpg');
    final withId = await importPhoto('mit_kamera.jpg');

    // Vor dem Setzen tauchen beide Fotos im Backfill auf.
    final beforeIds = (await db.assetsForCameraMetadataBackfill()).map((a) => a.id);
    expect(beforeIds, containsAll([withoutId, withId]));

    const info = CameraInfo(
      make: 'FUJIFILM',
      model: 'FUJIFILM X-T5',
      lensModel: 'XF35mmF1.4 R',
      focalLengthMm: 35.0,
      fNumber: 1.4,
      iso: 200,
      exposureTimeSeconds: 1 / 250,
    );
    await db.setCameraMetadata(withId, info);

    final updated = (await db.assetById(withId))!;
    expect(updated.cameraMake, 'FUJIFILM');
    expect(updated.cameraModel, 'FUJIFILM X-T5');
    expect(updated.lensModel, 'XF35mmF1.4 R');
    expect(updated.focalLengthMm, closeTo(35.0, 1e-9));
    expect(updated.fNumber, closeTo(1.4, 1e-9));
    expect(updated.iso, 200);
    expect(updated.exposureTimeSeconds, closeTo(1 / 250, 1e-9));

    // Nach dem Setzen taucht nur noch das unbearbeitete Foto im Backfill auf.
    final afterIds = (await db.assetsForCameraMetadataBackfill()).map((a) => a.id).toList();
    expect(afterIds, contains(withoutId));
    expect(afterIds, isNot(contains(withId)));
  });

  test('gelöschte Fotos tauchen nie im Kamera-Backfill auf', () async {
    // Gesperrte Fotos werden bewusst NICHT ausgeschlossen (anders als z.B.
    // beim Gesichts-Scan): die Kamera-Angaben sind reiner Text ohne
    // Bild-Vorschau und sind nur sichtbar, wenn man das Foto im bereits
    // entsperrten gesperrten Ordner ohnehin öffnet – kein Leak-Risiko.
    final lockedId = await importPhoto('locked.jpg');
    final trashedId = await importPhoto('trashed.jpg');
    await db.setAssetsLocked([lockedId], true);
    await db.moveToTrash([trashedId]);

    final ids = (await db.assetsForCameraMetadataBackfill()).map((a) => a.id);
    expect(ids, contains(lockedId));
    expect(ids, isNot(contains(trashedId)));
  });
}
