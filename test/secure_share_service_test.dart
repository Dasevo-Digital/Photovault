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
}
