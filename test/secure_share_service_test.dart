import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/export_service.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/secure_share_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

void main() {
  test('Austauschpaket enthält weder Klartextdateiname noch Klartextinhalt',
      () async {
    final temp = Directory.systemTemp.createTempSync('pv_share_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final paths =
        await StoragePaths.forTesting(Directory(p.join(temp.path, 'library')));
    final rel = p.join('originals', '2026', 'geheim.jpg');
    await paths.absolute(rel).parent.create(recursive: true);
    final originalBytes = 'SEHR_GEHEIMER_INHALT'.codeUnits;
    await paths.absolute(rel).writeAsBytes(originalBytes);
    final asset = AssetData(
      id: 'a1',
      originalFileName: 'Urlaub-geheim.jpg',
      relativePath: rel,
      checksum: sha256.convert(originalBytes).toString(),
      type: 'IMAGE',
      fileCreatedAt: DateTime(2026),
      importedAt: DateTime(2026),
      isFavorite: false,
      isTrashed: false,
      isLocked: false,
      faceScanExcluded: false,
      gpsGeprueft: false,
      datumGeschaetzt: false,
      datumGeprueft: false,
      ortGeerbt: false,
      videobilderGeprueft: false,
      fileSizeBytes: 22,
      backedUp: false,
      autoBackedUp: false,
      facesScanned: false,
      rating: 0,
      ocrScanned: false,
      aiCaptionScanned: false,
      aiCaptionEdited: false,
      aiTagsScanned: false,
      isStackCover: false,
    );
    final target = File(p.join(temp.path, 'paket.pvshare'));
    await SecureShareService(ExportService(paths))
        .createPackage([asset], target, 'eine-lange-passphrase');

    final bytes = await target.readAsBytes();
    final printable = String.fromCharCodes(bytes);
    expect(printable, isNot(contains('Urlaub-geheim.jpg')));
    expect(printable, isNot(contains('SEHR_GEHEIMER_INHALT')));
    expect(bytes.length, greaterThan(100));

    final zielDb = AppDatabase(NativeDatabase.memory());
    addTearDown(zielDb.close);
    final zielPaths = await StoragePaths.forTesting(
        Directory(p.join(temp.path, 'zielbibliothek')));
    final result = await SecureShareService(ExportService(paths)).importPackage(
      target,
      'eine-lange-passphrase',
      ImportService(zielDb, zielPaths),
    );
    expect(result.imported, 1);
    expect(result.duplicates, 0);
    final imported = (await zielDb.watchTimeline().first).single;
    expect(imported.originalFileName, 'Urlaub-geheim.jpg');
    expect(await zielPaths.absolute(imported.relativePath).readAsBytes(),
        originalBytes);
  });

  test('Austauschpaket kann eine künftige Ablaufzeit verschlüsselt tragen',
      () async {
    final temp = Directory.systemTemp.createTempSync('pv_share_expiry_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final paths =
        await StoragePaths.forTesting(Directory(p.join(temp.path, 'library')));
    const originalBytes = [7, 8, 9];
    const rel = 'originals/ablauf.jpg';
    await paths.absolute(rel).parent.create(recursive: true);
    await paths.absolute(rel).writeAsBytes(originalBytes);
    final asset = AssetData(
      id: 'expiry',
      originalFileName: 'ablauf.jpg',
      relativePath: rel,
      checksum: sha256.convert(originalBytes).toString(),
      type: 'IMAGE',
      fileCreatedAt: DateTime(2026),
      importedAt: DateTime(2026),
      isFavorite: false,
      isTrashed: false,
      isLocked: false,
      faceScanExcluded: false,
      gpsGeprueft: false,
      datumGeschaetzt: false,
      datumGeprueft: false,
      ortGeerbt: false,
      videobilderGeprueft: false,
      fileSizeBytes: 3,
      backedUp: false,
      autoBackedUp: false,
      facesScanned: false,
      rating: 0,
      ocrScanned: false,
      aiCaptionScanned: false,
      aiCaptionEdited: false,
      aiTagsScanned: false,
      isStackCover: false,
    );
    final service = SecureShareService(ExportService(paths));
    final target = File(p.join(temp.path, 'ablauf.pvshare'));
    await service.createPackage([asset], target, 'eine-lange-passphrase',
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)));

    await expectLater(
      service.createPackage([asset], File(p.join(temp.path, 'alt.pvshare')),
          'eine-lange-passphrase',
          expiresAt: DateTime.now().toUtc().subtract(const Duration(days: 1))),
      throwsArgumentError,
    );
    final targetDb = AppDatabase(NativeDatabase.memory());
    addTearDown(targetDb.close);
    final targetPaths = await StoragePaths.forTesting(
        Directory(p.join(temp.path, 'target-library')));
    final result = await service.importPackage(
        target, 'eine-lange-passphrase', ImportService(targetDb, targetPaths));
    expect(result.imported, 1);
  });

  test('abgelaufenes Austauschpaket wird vor dem Import abgewiesen', () async {
    final temp = Directory.systemTemp.createTempSync('pv_share_expired_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final paths =
        await StoragePaths.forTesting(Directory(p.join(temp.path, 'library')));
    const bytes = [4, 5, 6];
    const rel = 'originals/alt.jpg';
    await paths.absolute(rel).parent.create(recursive: true);
    await paths.absolute(rel).writeAsBytes(bytes);
    final asset = AssetData(
      id: 'expired',
      originalFileName: 'alt.jpg',
      relativePath: rel,
      checksum: sha256.convert(bytes).toString(),
      type: 'IMAGE',
      fileCreatedAt: DateTime(2026),
      importedAt: DateTime(2026),
      isFavorite: false,
      isTrashed: false,
      isLocked: false,
      faceScanExcluded: false,
      gpsGeprueft: false,
      datumGeschaetzt: false,
      datumGeprueft: false,
      ortGeerbt: false,
      videobilderGeprueft: false,
      fileSizeBytes: 3,
      backedUp: false,
      autoBackedUp: false,
      facesScanned: false,
      rating: 0,
      ocrScanned: false,
      aiCaptionScanned: false,
      aiCaptionEdited: false,
      aiTagsScanned: false,
      isStackCover: false,
    );
    final issuedAt = DateTime.utc(2040, 1, 1);
    final package = File(p.join(temp.path, 'abgelaufen.pvshare'));
    await SecureShareService(ExportService(paths), now: () => issuedAt)
        .createPackage([asset], package, 'eine-lange-passphrase',
            expiresAt: issuedAt.add(const Duration(days: 1)));

    final targetDb = AppDatabase(NativeDatabase.memory());
    addTearDown(targetDb.close);
    final targetPaths = await StoragePaths.forTesting(
        Directory(p.join(temp.path, 'target-library')));
    await expectLater(
      SecureShareService(ExportService(paths),
              now: () => issuedAt.add(const Duration(days: 2)))
          .importPackage(package, 'eine-lange-passphrase',
              ImportService(targetDb, targetPaths)),
      throwsA(isA<SharePackageExpired>()),
    );
    expect(await targetDb.select(targetDb.assets).get(), isEmpty);
  });
}
