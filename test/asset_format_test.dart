import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/asset_format.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Prüft die reine Formatierungs-/Parsing-Logik für Belichtungszeit sowie
/// [assetFormatLabel]/[assetHasLocation] (siehe MetadataEditorDialog,
/// AssetInfoSheet, AssetThumbnailTile).
void main() {
  group('formatExposureTime / parseExposureTimeInput', () {
    test('formatiert Sekunden >= 1s als Dezimalzahl, darunter als Bruch', () {
      expect(formatExposureTime(2), '2 s');
      expect(formatExposureTime(0.5), '1/2 s');
      expect(formatExposureTime(1 / 125), '1/125 s');
    });

    test('parst Brüche ("1/125") und Dezimalwerte (Punkt oder Komma)', () {
      expect(parseExposureTimeInput('1/125'), closeTo(0.008, 0.0001));
      expect(parseExposureTimeInput('0.5'), 0.5);
      expect(parseExposureTimeInput('0,5'), 0.5);
      expect(parseExposureTimeInput(''), isNull);
      expect(parseExposureTimeInput('1/0'), isNull);
      expect(parseExposureTimeInput('unsinn'), isNull);
    });
  });

  group('assetFormatLabel / assetHasLocation', () {
    late Directory tempRoot;
    late AppDatabase db;
    late ImportService import;
    var nextByte = 0;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('photo_vault_asset_format_test_');
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

    test('leitet das Kürzel aus der tatsächlichen Dateiendung ab', () async {
      expect(assetFormatLabel(await importPhoto('foto.jpg')), 'JPG');
      expect(assetFormatLabel(await importPhoto('foto.png')), 'PNG');
      expect(assetFormatLabel(await importPhoto('foto.dng')), 'DNG');
      expect(assetFormatLabel(await importPhoto('foto.heic')), 'HEIC');
    });

    test('liefert ein leeres Kürzel für Videos (eigenes Icon zeigt das schon)', () async {
      expect(assetFormatLabel(await importPhoto('clip.mp4')), '');
    });

    test('assetHasLocation prüft auf gesetzte Koordinaten', () async {
      final withoutGps = await importPhoto('foto.jpg');
      expect(assetHasLocation(withoutGps), isFalse);

      await db.setLocation(withoutGps.id, 48.85, 2.35);
      final withGps = (await db.assetById(withoutGps.id))!;
      expect(assetHasLocation(withGps), isTrue);
    });

    test('isPanorama erkennt sehr breite Seitenverhältnisse ab 2.5:1', () async {
      final asset = await importPhoto('foto.jpg');

      await db.updateThumbnailInfo(asset.id, widthPx: 1200, heightPx: 800);
      expect(isPanorama((await db.assetById(asset.id))!), isFalse);

      await db.updateThumbnailInfo(asset.id, widthPx: 6000, heightPx: 2000);
      expect(isPanorama((await db.assetById(asset.id))!), isTrue);
    });

    test('isPanorama ist false ohne gespeicherte Maße (alte Assets)', () async {
      final asset = await importPhoto('foto.jpg');
      expect(isPanorama(asset), isFalse);
    });

    test('isEquirectangular360 erkennt nur Seitenverhältnisse nahe 2:1', () async {
      final asset = await importPhoto('foto.jpg');

      await db.updateThumbnailInfo(asset.id, widthPx: 4000, heightPx: 2000);
      expect(isEquirectangular360((await db.assetById(asset.id))!), isTrue);

      // Genau an der 2.5:1-Schwelle von isPanorama liegt AUSSERHALB des
      // 360°-Fensters – die beiden Erkennungen überschneiden sich bewusst
      // (fast) nicht.
      await db.updateThumbnailInfo(asset.id, widthPx: 5000, heightPx: 2000);
      expect(isEquirectangular360((await db.assetById(asset.id))!), isFalse);

      await db.updateThumbnailInfo(asset.id, widthPx: 1800, heightPx: 1200);
      expect(isEquirectangular360((await db.assetById(asset.id))!), isFalse);
    });

    test('isEquirectangular360 ist false ohne gespeicherte Maße (alte Assets)', () async {
      final asset = await importPhoto('foto.jpg');
      expect(isEquirectangular360(asset), isFalse);
    });
  });
}
