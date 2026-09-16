import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:uuid/uuid.dart';

/// Prüft zwei Ebenen der Kamera-Presets (siehe CameraPresetsScreen):
///
/// 1. Die reine DB-Seite (AppDatabase): Anlegen/Ändern/Löschen eines
///    Presets, Tag-Zuordnung, und vor allem [AppDatabase.cameraPresetFor] –
///    das eigentliche "Kamera identifizieren"-Matching.
/// 2. Die Anwendung eines gefundenen Presets auf ein konkretes Asset
///    (LibraryState.applyCameraPreset – @visibleForTesting, siehe dort für
///    die Begründung, warum kein voller Importpfad mit echter EXIF-JPEG
///    genutzt wird, analog zu camera_metadata_test.dart).
void main() {
  group('AppDatabase Kamera-Presets', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('cameraPresetFor liefert null, wenn Hersteller oder Modell fehlen', () async {
      expect(await db.cameraPresetFor(null, null), isNull);
      expect(await db.cameraPresetFor('Canon', null), isNull);
      expect(await db.cameraPresetFor(null, 'EOS R5'), isNull);
    });

    test('cameraPresetFor liefert null ohne passendes Preset, sonst das Preset', () async {
      expect(await db.cameraPresetFor('Canon', 'EOS R5'), isNull);

      await db.upsertCameraPreset(CameraPresetsCompanion.insert(
        id: 'p1',
        cameraMake: 'Canon',
        cameraModel: 'EOS R5',
      ));

      final match = await db.cameraPresetFor('Canon', 'EOS R5');
      expect(match, isNotNull);
      expect(match!.id, 'p1');

      // Andere Kamera bleibt unbeeinflusst.
      expect(await db.cameraPresetFor('Canon', 'EOS R6'), isNull);
    });

    test('cameraPresetFor stürzt bei versehentlich doppelt angelegtem Preset nicht ab', () async {
      await db.upsertCameraPreset(CameraPresetsCompanion.insert(
        id: 'dup1',
        cameraMake: 'Apple',
        cameraModel: 'iPhone 15 Pro',
      ));
      await db.upsertCameraPreset(CameraPresetsCompanion.insert(
        id: 'dup2',
        cameraMake: 'Apple',
        cameraModel: 'iPhone 15 Pro',
      ));

      final match = await db.cameraPresetFor('Apple', 'iPhone 15 Pro');
      expect(match, isNotNull);
      expect(['dup1', 'dup2'], contains(match!.id));
    });

    test('upsertCameraPreset überschreibt ein bestehendes Preset bei gleicher ID', () async {
      await db.upsertCameraPreset(CameraPresetsCompanion.insert(
        id: 'p1',
        cameraMake: 'Canon',
        cameraModel: 'EOS R5',
        autoFavorite: const Value(false),
      ));
      await db.upsertCameraPreset(CameraPresetsCompanion.insert(
        id: 'p1',
        cameraMake: 'Canon',
        cameraModel: 'EOS R5',
        autoFavorite: const Value(true),
      ));

      final presets = await db.watchCameraPresets().first;
      expect(presets, hasLength(1));
      expect(presets.single.autoFavorite, isTrue);
    });

    test('deleteCameraPreset entfernt das Preset und alle zugeordneten Tags', () async {
      await db.upsertCameraPreset(CameraPresetsCompanion.insert(
        id: 'p1',
        cameraMake: 'Canon',
        cameraModel: 'EOS R5',
      ));
      await db.setCameraPresetTags('p1', ['tagA', 'tagB']);

      await db.deleteCameraPreset('p1');

      expect(await db.watchCameraPresets().first, isEmpty);
      expect(await db.tagIdsForCameraPreset('p1'), isEmpty);
    });

    test('setCameraPresetTags ersetzt die komplette Tag-Menge (nicht nur hinzufügen)', () async {
      await db.upsertCameraPreset(CameraPresetsCompanion.insert(
        id: 'p1',
        cameraMake: 'Canon',
        cameraModel: 'EOS R5',
      ));

      await db.setCameraPresetTags('p1', ['a', 'b']);
      expect(await db.tagIdsForCameraPreset('p1'), unorderedEquals(['a', 'b']));

      await db.setCameraPresetTags('p1', ['c']);
      expect(await db.tagIdsForCameraPreset('p1'), ['c']);

      await db.setCameraPresetTags('p1', []);
      expect(await db.tagIdsForCameraPreset('p1'), isEmpty);
    });

    test('distinctCameras liefert nur vollständige, eindeutige Kombinationen', () async {
      Future<void> insertAsset(String id, {String? make, String? model}) => db.into(db.assets).insert(
            AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.jpg',
              relativePath: 'originals/$id.jpg',
              checksum: 'checksum_$id',
              type: 'IMAGE',
              fileCreatedAt: DateTime(2020, 1, 1),
              importedAt: DateTime(2020, 1, 1),
              cameraMake: Value(make),
              cameraModel: Value(model),
            ),
          );

      await insertAsset('a', make: 'Canon', model: 'EOS R5');
      await insertAsset('b', make: 'Canon', model: 'EOS R5'); // Duplikat, soll nur einmal erscheinen
      await insertAsset('c', make: 'Apple', model: 'iPhone 15 Pro');
      await insertAsset('d'); // ohne Kamera

      final cameras = await db.distinctCameras();
      expect(cameras, unorderedEquals([('Apple', 'iPhone 15 Pro'), ('Canon', 'EOS R5')]));
    });
  });

  group('LibraryState.applyCameraPreset', () {
    late Directory tempRoot;
    late AppDatabase db;
    late ImportService import;
    late LibraryState library;
    var nextByte = 0;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('photo_vault_camera_preset_apply_test_');
      db = AppDatabase(NativeDatabase.memory());
      final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
      import = ImportService(db, paths);
      library = LibraryState()
        ..db = db
        ..paths = paths;
    });

    tearDown(() async {
      await db.close();
      tempRoot.deleteSync(recursive: true);
    });

    Future<String> importPhoto(String name) async {
      final incoming = Directory(p.join(tempRoot.path, 'incoming'))..createSync(recursive: true);
      final file = File(p.join(incoming.path, name))..writeAsBytesSync([1, 2, 3, nextByte++]);
      final result = await import.importFile(file.path);
      expect(result.outcome, ImportOutcome.imported);
      return result.assetId!;
    }

    test('fügt das Asset bei passendem Preset dem Zielalbum hinzu, favorisiert und taggt es', () async {
      const albumId = 'album1';
      await db.createAlbum(AlbumsCompanion.insert(id: albumId, name: 'Drohnenfotos', createdAt: DateTime.now()));
      final tagId = await db.ensureTag('Drohne');

      await db.upsertCameraPreset(CameraPresetsCompanion.insert(
        id: 'preset1',
        cameraMake: 'DJI',
        cameraModel: 'Mavic 3',
        targetAlbumId: const Value(albumId),
        autoFavorite: const Value(true),
      ));
      await db.setCameraPresetTags('preset1', [tagId]);

      final assetId = await importPhoto('drohne.jpg');
      await library.applyCameraPreset(assetId, cameraMake: 'DJI', cameraModel: 'Mavic 3');

      final albumAssets = await db.assetsInAlbumOnce(albumId);
      expect(albumAssets.map((a) => a.id), contains(assetId));

      final asset = (await db.assetById(assetId))!;
      expect(asset.isFavorite, isTrue);

      final tags = await db.tagsForAsset(assetId);
      expect(tags.map((t) => t.name), contains('Drohne'));
    });

    test('lässt ein Asset ohne passendes Preset komplett unverändert', () async {
      final assetId = await importPhoto('unbekannt.jpg');
      await library.applyCameraPreset(assetId, cameraMake: 'Sony', cameraModel: 'A7 IV');

      final asset = (await db.assetById(assetId))!;
      expect(asset.isFavorite, isFalse);
      expect(await db.tagsForAsset(assetId), isEmpty);
    });

    test('wendet nur das Preset der exakt passenden Kamera an, nicht das einer anderen', () async {
      const albumA = 'albumA';
      const albumB = 'albumB';
      await db.createAlbum(AlbumsCompanion.insert(id: albumA, name: 'A', createdAt: DateTime.now()));
      await db.createAlbum(AlbumsCompanion.insert(id: albumB, name: 'B', createdAt: DateTime.now()));
      await db.upsertCameraPreset(CameraPresetsCompanion.insert(
        id: const Uuid().v4(),
        cameraMake: 'Canon',
        cameraModel: 'EOS R5',
        targetAlbumId: const Value(albumA),
      ));
      await db.upsertCameraPreset(CameraPresetsCompanion.insert(
        id: const Uuid().v4(),
        cameraMake: 'Canon',
        cameraModel: 'EOS R6',
        targetAlbumId: const Value(albumB),
      ));

      final assetId = await importPhoto('r5.jpg');
      await library.applyCameraPreset(assetId, cameraMake: 'Canon', cameraModel: 'EOS R5');

      expect((await db.assetsInAlbumOnce(albumA)).map((a) => a.id), contains(assetId));
      expect((await db.assetsInAlbumOnce(albumB)).map((a) => a.id), isNot(contains(assetId)));
    });
  });
}
