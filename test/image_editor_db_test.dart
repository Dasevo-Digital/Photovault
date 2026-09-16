import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Prüft die DB-Seite der Bildbearbeitung (Zuschneiden/Drehen/Spiegeln,
/// siehe ImageEditorScreen): [AppDatabase.setEditedAssetFile] ersetzt Pfad
/// und Prüfsumme und löscht eine ggf. vorhandene konvertierte Vorschau, da
/// die neue Originaldatei nach dem Bearbeiten bereits ein direkt
/// darstellbares JPEG ist.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late ImportService import;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('photo_vault_image_editor_test_');
    db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
    import = ImportService(db, paths);
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<String> importPhoto(String name) async {
    final incoming = Directory(p.join(tempRoot.path, 'incoming'))..createSync(recursive: true);
    final file = File(p.join(incoming.path, name))..writeAsBytesSync([1, 2, 3]);
    final result = await import.importFile(file.path);
    expect(result.outcome, ImportOutcome.imported);
    return result.assetId!;
  }

  test('setEditedAssetFile ersetzt Pfad/Prüfsumme und löscht die konvertierte Vorschau', () async {
    final assetId = await importPhoto('foto.heic');
    // Simuliert eine bei HEIC/RAW-Importen vorhandene konvertierte Vorschau.
    await db.updateThumbnailInfo(assetId, previewRelativePath: 'previews/$assetId.jpg');

    await db.setEditedAssetFile(assetId, relativePath: 'originals/2026/01/$assetId.jpg', checksum: 'new-checksum');

    final updated = await db.assetById(assetId);
    expect(updated!.relativePath, 'originals/2026/01/$assetId.jpg');
    expect(updated.checksum, 'new-checksum');
    expect(updated.previewRelativePath, isNull);
  });
}
