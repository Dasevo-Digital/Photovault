import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:kern/db/database.dart';
import 'package:photo_vault/services/contact_sheet_service.dart';
import 'package:photo_vault/services/export_service.dart';
import 'package:kern/services/storage_paths.dart';

void main() {
  test('Kontaktblatt enthält lokal gerenderte Bildkacheln als PDF', () async {
    final temp = Directory.systemTemp.createTempSync('pv_contact_sheet_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final paths = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'library')),
    );
    const relativePath = 'originals/test.jpg';
    final bytes = img.encodeJpg(img.Image(width: 20, height: 10));
    await paths.absolute(relativePath).parent.create(recursive: true);
    await paths.absolute(relativePath).writeAsBytes(bytes);
    final asset = AssetData(
      id: 'test',
      originalFileName: 'test.jpg',
      relativePath: relativePath,
      checksum: sha256.convert(bytes).toString(),
      type: 'IMAGE',
      fileCreatedAt: DateTime(2026, 9, 19),
      importedAt: DateTime(2026, 9, 19),
      isFavorite: false,
      isArchived: false,
      isTrashed: false,
      isLocked: false,
      faceScanExcluded: false,
      gpsGeprueft: false,
      datumGeschaetzt: false,
      datumGeprueft: false,
      ortGeerbt: false,
      videobilderGeprueft: false,
      fileSizeBytes: bytes.length,
      backedUp: false,
      autoBackedUp: false,
      facesScanned: false,
      rating: 0,
      ocrScanned: false,
      aiCaptionScanned: false,
      aiCaptionEdited: false,
      aiTagsScanned: false,
      transkriptGeprueft: false,
      isStackCover: false,
    );

    final result = await ContactSheetService(
      paths,
      ExportService(paths),
    ).create([asset]);
    expect(result.included, 1);
    expect(result.skipped, 0);
    expect(String.fromCharCodes(result.bytes.take(4)), '%PDF');
  });

  test('ein Video gilt als ausgelassen, auch mit Vorschaubild '
      '(BEA-118, BEA-120)', () async {
    final temp = Directory.systemTemp.createTempSync('pv_contact_sheet_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final paths = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'library')),
    );
    Future<AssetData> aufnahme(String id, String type) async {
      final bytes = img.encodeJpg(img.Image(width: 20, height: 10));
      final rel = 'originals/$id.jpg';
      final vorschau = 'thumbs/$id.jpg';
      for (final r in [rel, vorschau]) {
        await paths.absolute(r).parent.create(recursive: true);
        await paths.absolute(r).writeAsBytes(bytes);
      }
      return AssetData(
        id: id,
        originalFileName: '$id.jpg',
        relativePath: rel,
        thumbnailRelativePath: vorschau,
        checksum: sha256.convert(bytes).toString(),
        type: type,
        fileCreatedAt: DateTime(2026, 9, 19),
        importedAt: DateTime(2026, 9, 19),
        isFavorite: false,
        isArchived: false,
        isTrashed: false,
        isLocked: false,
        faceScanExcluded: false,
        gpsGeprueft: false,
        datumGeschaetzt: false,
        datumGeprueft: false,
        ortGeerbt: false,
        videobilderGeprueft: false,
        fileSizeBytes: bytes.length,
        backedUp: false,
        autoBackedUp: false,
        facesScanned: false,
        rating: 0,
        ocrScanned: false,
        aiCaptionScanned: false,
        aiCaptionEdited: false,
        aiTagsScanned: false,
        transkriptGeprueft: false,
        isStackCover: false,
      );
    }

    final dienst = ContactSheetService(paths, ExportService(paths));
    final foto = await aufnahme('foto', 'IMAGE');
    final video = await aufnahme('video', 'VIDEO');

    final gemischt = await dienst.create([foto, video]);
    expect(gemischt.included, 1);
    expect(gemischt.skipped, 1);

    final nurVideo = await dienst.create([video]);
    expect(nurVideo.included, 0, reason: 'sonst kommt keine Warnung');
    expect(nurVideo.skipped, 1);
  });
}
