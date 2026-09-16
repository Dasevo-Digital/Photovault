import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Prüft den vollen Backup->Restore-Rundtrip in eine frische, leere
/// "zweite Bibliothek" (simuliert einen neuen Rechner) sowie die
/// Fehlertoleranz von [BackupService.restoreFromBackup]/
/// [BackupService._applyMetadataExport] gegenüber defekten metadata.json-
/// Inhalten (z.B. aus einem von Hand bearbeiteten oder älteren Backup).
void main() {
  test('Backup und anschließender Restore in eine leere Bibliothek stellen Metadaten korrekt wieder her', () async {
    final tempRoot = Directory.systemTemp.createTempSync('photo_vault_backup_test_');
    addTearDown(() => tempRoot.deleteSync(recursive: true));

    // --- Quell-Bibliothek befüllen ---
    final sourceDb = AppDatabase(NativeDatabase.memory());
    addTearDown(sourceDb.close);
    final sourcePaths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'source_library')));
    final sourceImport = ImportService(sourceDb, sourcePaths);
    final sourceBackup = BackupService(sourceDb, sourcePaths);

    final incoming = Directory(p.join(tempRoot.path, 'incoming'))..createSync();
    final photo1 = File(p.join(incoming.path, 'urlaub.jpg'))..writeAsBytesSync([1, 2, 3]);
    final photo2 = File(p.join(incoming.path, 'geburtstag.jpg'))..writeAsBytesSync([4, 5, 6]);

    final r1 = await sourceImport.importFile(photo1.path);
    final r2 = await sourceImport.importFile(photo2.path);
    expect(r1.outcome, ImportOutcome.imported);
    expect(r2.outcome, ImportOutcome.imported);

    await sourceDb.setFavorite(r1.assetId!, true);
    await sourceDb.setDescription(r1.assetId!, 'Am Strand');
    await sourceDb.tagAsset(r1.assetId!, 'strand');
    await sourceDb.tagAsset(r1.assetId!, 'urlaub');

    const albumId = 'album-1';
    await sourceDb.createAlbum(
      AlbumsCompanion.insert(id: albumId, name: 'Urlaub 2026', createdAt: DateTime.now()),
    );
    await sourceDb.addAssetsToAlbum(albumId, [r1.assetId!, r2.assetId!]);

    // --- Backup in einen Zielordner ---
    final backupDestination = Directory(p.join(tempRoot.path, 'backup_target'));
    await sourceBackup.performBackup(backupDestination.path).drain<void>();

    final backupRoot = p.join(backupDestination.path, 'PhotoVault-Backup');
    expect(await File(p.join(backupRoot, 'metadata.json')).exists(), isTrue);

    // --- Restore in eine zweite, komplett leere Bibliothek ---
    final targetDb = AppDatabase(NativeDatabase.memory());
    addTearDown(targetDb.close);
    final targetPaths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'target_library')));
    final targetImport = ImportService(targetDb, targetPaths);
    final targetBackup = BackupService(targetDb, targetPaths);

    await targetBackup.restoreFromBackup(backupRoot, targetImport).drain<void>();

    // --- Assets wiederhergestellt ---
    final restoredAssets = await targetDb.select(targetDb.assets).get();
    expect(restoredAssets, hasLength(2));

    final restoredFavorite = restoredAssets.firstWhere((a) => a.originalFileName == 'urlaub.jpg');
    expect(restoredFavorite.isFavorite, isTrue);
    expect(restoredFavorite.description, 'Am Strand');

    final restoredOther = restoredAssets.firstWhere((a) => a.originalFileName == 'geburtstag.jpg');
    expect(restoredOther.isFavorite, isFalse);

    // --- Tags wiederhergestellt ---
    final restoredTags = await targetDb.tagsForAsset(restoredFavorite.id);
    expect(restoredTags.map((t) => t.name).toSet(), {'strand', 'urlaub'});

    // --- Album wiederhergestellt, inkl. beider Fotos ---
    final restoredAlbums = await targetDb.select(targetDb.albums).get();
    expect(restoredAlbums, hasLength(1));
    expect(restoredAlbums.single.name, 'Urlaub 2026');

    final assetsInAlbum = await targetDb.assetsInAlbumOnce(restoredAlbums.single.id);
    expect(assetsInAlbum.map((a) => a.originalFileName).toSet(), {'urlaub.jpg', 'geburtstag.jpg'});
  });

  test('komplett unlesbare metadata.json bricht den Restore nicht ab – Originaldateien werden trotzdem importiert', () async {
    final tempRoot = Directory.systemTemp.createTempSync('photo_vault_backup_brokenjson_test_');
    addTearDown(() => tempRoot.deleteSync(recursive: true));

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
    final importService = ImportService(db, paths);
    final backupService = BackupService(db, paths);

    final backupRoot = Directory(p.join(tempRoot.path, 'PhotoVault-Backup'));
    final originalsDir = Directory(p.join(backupRoot.path, 'originals'))..createSync(recursive: true);
    File(p.join(originalsDir.path, 'foto.jpg')).writeAsBytesSync([7, 8, 9]);
    // Kaputtes JSON, z.B. durch einen abgebrochenen Kopiervorgang.
    File(p.join(backupRoot.path, 'metadata.json')).writeAsStringSync('{ "assets": [ this is not json');

    await backupService.restoreFromBackup(backupRoot.path, importService).drain<void>();

    final assets = await db.select(db.assets).get();
    expect(assets, hasLength(1));
    expect(assets.single.originalFileName, 'foto.jpg');
  });

  test('ein defekter Asset-Eintrag in metadata.json überspringt nur diesen Eintrag, nicht die restlichen', () async {
    final tempRoot = Directory.systemTemp.createTempSync('photo_vault_backup_brokenentry_test_');
    addTearDown(() => tempRoot.deleteSync(recursive: true));

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
    final importService = ImportService(db, paths);
    final backupService = BackupService(db, paths);

    final backupRoot = Directory(p.join(tempRoot.path, 'PhotoVault-Backup'));
    final originalsDir = Directory(p.join(backupRoot.path, 'originals'))..createSync(recursive: true);

    final brokenBytes = [7, 8, 9];
    final okBytes = [10, 11, 12];
    File(p.join(originalsDir.path, 'foto1.jpg')).writeAsBytesSync(brokenBytes);
    File(p.join(originalsDir.path, 'foto2.jpg')).writeAsBytesSync(okBytes);
    final brokenChecksum = sha256.convert(brokenBytes).toString();
    final okChecksum = sha256.convert(okBytes).toString();

    final metadata = {
      'exportedAt': DateTime.now().toIso8601String(),
      'assets': [
        {
          'checksum': brokenChecksum,
          'originalFileName': 'foto1.jpg',
          'isFavorite': true,
          'description': 'kaputt',
          // 'tags' ist fälschlich ein String statt einer Liste (z.B. durch
          // eine von Hand bearbeitete Datei) -> der Cast schlägt fehl.
          'tags': 'nicht-eine-liste',
        },
        {
          'checksum': okChecksum,
          'originalFileName': 'foto2.jpg',
          'isFavorite': true,
          'description': 'ok',
          'tags': ['urlaub'],
        },
      ],
      'albums': <dynamic>[],
    };
    File(p.join(backupRoot.path, 'metadata.json')).writeAsStringSync(jsonEncode(metadata));

    await backupService.restoreFromBackup(backupRoot.path, importService).drain<void>();

    // Beide Dateien werden unabhängig von metadata.json importiert.
    final assets = await db.select(db.assets).get();
    expect(assets, hasLength(2));

    final broken = assets.firstWhere((a) => a.originalFileName == 'foto1.jpg');
    final ok = assets.firstWhere((a) => a.originalFileName == 'foto2.jpg');

    // Für den kaputten Eintrag greifen isFavorite/description noch (laufen
    // vor dem Tags-Cast), der Tags-Schritt selbst schlägt fehl und wird
    // übersprungen, statt den kompletten Restore abzubrechen.
    expect(broken.isFavorite, isTrue);
    expect(broken.description, 'kaputt');
    expect(await db.tagsForAsset(broken.id), isEmpty);

    // Der nachfolgende, valide Eintrag wird trotz des vorherigen Fehlers
    // vollständig angewendet.
    expect(ok.isFavorite, isTrue);
    expect(ok.description, 'ok');
    expect((await db.tagsForAsset(ok.id)).map((t) => t.name), contains('urlaub'));
  });

  test(
      'ein originalFileName mit Pfad-Traversal in metadata.json wird auf den Basisnamen reduziert '
      '(schützt einen späteren Export vor einem Ziel außerhalb des gewählten Ordners)', () async {
    final tempRoot = Directory.systemTemp.createTempSync('photo_vault_backup_traversal_test_');
    addTearDown(() => tempRoot.deleteSync(recursive: true));

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
    final importService = ImportService(db, paths);
    final backupService = BackupService(db, paths);

    final backupRoot = Directory(p.join(tempRoot.path, 'PhotoVault-Backup'));
    final originalsDir = Directory(p.join(backupRoot.path, 'originals'))..createSync(recursive: true);

    final bytes = [1, 2, 3];
    File(p.join(originalsDir.path, 'foto.jpg')).writeAsBytesSync(bytes);
    final checksum = sha256.convert(bytes).toString();

    final metadata = {
      'exportedAt': DateTime.now().toIso8601String(),
      'assets': [
        {
          'checksum': checksum,
          // Präpariert, z.B. aus einem fremden/geteilten Backup-Ordner.
          'originalFileName': '../../../Library/LaunchAgents/evil.jpg',
        },
      ],
      'albums': <dynamic>[],
    };
    File(p.join(backupRoot.path, 'metadata.json')).writeAsStringSync(jsonEncode(metadata));

    await backupService.restoreFromBackup(backupRoot.path, importService).drain<void>();

    final asset = (await db.select(db.assets).get()).single;
    expect(asset.originalFileName, 'evil.jpg');
  });
}
