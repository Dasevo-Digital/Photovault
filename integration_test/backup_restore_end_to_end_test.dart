import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Prüft den vollständigen, plattformneutralen Weg auf echten Dateien und
/// SQLite-Dateien: ein neuer Rechner bekommt nur das Sicherungsverzeichnis
/// und erhält daraus Dateien, Metadaten, Tags und Albumzuordnungen zurück.
///
/// Der Test benötigt keine KI-Modelle, kein Netzwerk und keine private
/// Bibliothek. Er kann unverändert auf macOS, Linux und Windows laufen.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
      'Backup und Restore ergeben auf einem frischen Bibliotheksort denselben Bestand',
      () async {
    final root = await Directory.systemTemp.createTemp('pv_restore_e2e_');
    final sourceDb =
        AppDatabase(NativeDatabase(File(p.join(root.path, 'source.sqlite'))));
    final targetDb =
        AppDatabase(NativeDatabase(File(p.join(root.path, 'target.sqlite'))));
    try {
      final sourcePaths = await StoragePaths.forTesting(
          Directory(p.join(root.path, 'source_library')));
      final targetPaths = await StoragePaths.forTesting(
          Directory(p.join(root.path, 'target_library')));
      final incoming = Directory(p.join(root.path, 'incoming'))..createSync();
      final sourceImport = ImportService(sourceDb, sourcePaths);
      final targetImport = ImportService(targetDb, targetPaths);

      final originalBytes = List<int>.generate(1024, (i) => i % 251);
      final incomingFile = File(p.join(incoming.path, 'reise.jpg'))
        ..writeAsBytesSync(originalBytes);
      final imported = await sourceImport.importFile(incomingFile.path);
      expect(imported.outcome, ImportOutcome.imported);
      final assetId = imported.assetId!;
      await sourceDb.setFavorite(assetId, true);
      await sourceDb.setRating(assetId, 4);
      await sourceDb.setDescription(assetId, 'Wanderung am See');
      await sourceDb.tagAsset(assetId, 'wandern');
      await sourceDb.tagAsset(assetId, 'see');
      await sourceDb.createAlbum(AlbumsCompanion.insert(
          id: 'album-e2e', name: 'Ausflüge', createdAt: DateTime.now()));
      await sourceDb.addAssetsToAlbum('album-e2e', [assetId]);

      final backupTarget = Directory(p.join(root.path, 'backup_target'));
      final sourceBackup = BackupService(sourceDb, sourcePaths);
      await sourceBackup.performBackup(backupTarget.path).drain<void>();

      final backupRoot = p.join(backupTarget.path, 'PhotoVault-Backup');
      await BackupService(targetDb, targetPaths)
          .restoreFromBackup(backupRoot, targetImport)
          .drain<void>();

      final restored = (await targetDb.select(targetDb.assets).get()).single;
      expect(restored.originalFileName, 'reise.jpg');
      expect(restored.isFavorite, isTrue);
      expect(restored.rating, 4);
      expect(restored.description, 'Wanderung am See');
      expect(await targetPaths.absolute(restored.relativePath).readAsBytes(),
          originalBytes);
      expect(
          (await targetDb.tagsForAsset(restored.id)).map((t) => t.name).toSet(),
          {'wandern', 'see'});
      final album = (await targetDb.select(targetDb.albums).get()).single;
      expect(album.name, 'Ausflüge');
      expect(
          (await targetDb.assetsInAlbumOnce(album.id)).single.id, restored.id);
    } finally {
      await sourceDb.close();
      await targetDb.close();
      await root.delete(recursive: true);
    }
  });
}
