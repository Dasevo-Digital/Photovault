import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// Prüft [LibraryState.deleteAssetFilesFromDisk] – die seit dem
/// Sicherheits-Audit zentrale Stelle für "endgültig löschen", die alle drei
/// Aufrufstellen (normaler Papierkorb, automatisches Ablaufen, gesperrter
/// Papierkorb) jetzt gemeinsam nutzen, statt jeweils eine eigene, leicht
/// auseinanderlaufende Kopie der Dateiliste zu pflegen (genau das führte
/// vorher dazu, dass previewRelativePath/developedRelativePath beim
/// automatischen Ablaufen vergessen wurden).
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late StoragePaths paths;
  late LibraryState library;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('photo_vault_delete_asset_files_test_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
    library = LibraryState()
      ..db = db
      ..paths = paths;
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  test(
      'löscht Original, Thumbnail, Vorschau, entwickeltes Bild, Video-Zuschnitt, '
      'KI-Objektmasken und Gesichts-Crops', () async {
    const assetId = 'a';
    final original = paths.absolute('originals/$assetId.jpg')..parent.createSync(recursive: true);
    final thumbnail = paths.absolute('thumbnails/$assetId.jpg')..parent.createSync(recursive: true);
    final preview = paths.absolute('previews/$assetId.jpg')..parent.createSync(recursive: true);
    final developed = paths.absolute('developed/$assetId.jpg')..parent.createSync(recursive: true);
    final trimmed = paths.absolute('trimmed/$assetId.mp4')..parent.createSync(recursive: true);
    final mask = paths.absolute('masks/mask1.png')..parent.createSync(recursive: true);
    final faceCrop = paths.absolute('faces/face1.jpg')..parent.createSync(recursive: true);
    for (final f in [original, thumbnail, preview, developed, trimmed, mask, faceCrop]) {
      f.writeAsBytesSync([1, 2, 3]);
    }

    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: assetId,
          originalFileName: '$assetId.jpg',
          relativePath: 'originals/$assetId.jpg',
          checksum: 'checksum',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2024, 1, 1),
          importedAt: DateTime(2024, 1, 1),
          thumbnailRelativePath: const Value('thumbnails/a.jpg'),
          previewRelativePath: const Value('previews/a.jpg'),
          developedRelativePath: const Value('developed/a.jpg'),
          trimmedRelativePath: const Value('trimmed/a.mp4'),
        ));
    await db.insertFace(FacesCompanion.insert(
      id: 'face1',
      assetId: assetId,
      boxX: 0,
      boxY: 0,
      boxW: 1,
      boxH: 1,
      cropRelativePath: const Value('faces/face1.jpg'),
    ));
    await db.createDevelopMask(DevelopMasksCompanion.insert(
      assetId: assetId,
      maskRelativePath: 'masks/mask1.png',
      label: 'Maske 1',
      createdAt: DateTime(2024, 1, 1),
    ));

    final asset = (await db.assetById(assetId))!;
    await library.deleteAssetFilesFromDisk(asset);

    for (final f in [original, thumbnail, preview, developed, trimmed, mask, faceCrop]) {
      expect(f.existsSync(), isFalse, reason: '${f.path} sollte gelöscht sein.');
    }
    // Die DB-Zeile selbst bleibt bestehen – das ist Sache des Aufrufers.
    expect(await db.assetById(assetId), isNotNull);
  });

  test('funktioniert auch, wenn Vorschau/entwickeltes Bild/Gesichts-Crop nie existiert haben', () async {
    const assetId = 'minimal';
    paths.absolute('originals/$assetId.jpg')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1]);
    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: assetId,
          originalFileName: '$assetId.jpg',
          relativePath: 'originals/$assetId.jpg',
          checksum: 'checksum',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2024, 1, 1),
          importedAt: DateTime(2024, 1, 1),
        ));

    final asset = (await db.assetById(assetId))!;
    await library.deleteAssetFilesFromDisk(asset); // darf nicht werfen
    expect(paths.absolute('originals/$assetId.jpg').existsSync(), isFalse);
  });
}
