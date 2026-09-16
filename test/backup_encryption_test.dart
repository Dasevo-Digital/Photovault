import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/services/vault_crypto.dart';
import 'package:photo_vault/state/library_state.dart';

/// Prüft die Backup-Verschlüsselung: ein verschlüsseltes manuelles Backup
/// lässt sich ausschließlich mit der Passphrase auf einem KOMPLETT anderen
/// Rechner wiederherstellen (kein Zugriff auf die Quell-Datenbank nötig),
/// und das automatische Backup sichert einen konsistenten, verschlüsselten
/// Datenbank-Schnappschuss, kopiert nur neue Dateien und löscht am Zielort
/// nie etwas.
void main() {
  test('verschlüsseltes manuelles Backup lässt sich nur mit der Passphrase wiederherstellen', () async {
    final tempRoot = Directory.systemTemp.createTempSync('photo_vault_backup_encryption_test_');
    addTearDown(() => tempRoot.deleteSync(recursive: true));

    // --- Quell-Bibliothek mit eingerichteter Backup-Passphrase ---
    final sourceDb = AppDatabase(NativeDatabase.memory());
    addTearDown(sourceDb.close);
    final sourcePaths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'source_library')));
    final sourceImport = ImportService(sourceDb, sourcePaths);
    final sourceLibrary = LibraryState()
      ..db = sourceDb
      ..paths = sourcePaths
      ..backupService = BackupService(sourceDb, sourcePaths);

    final incoming = Directory(p.join(tempRoot.path, 'incoming'))..createSync();
    final photo = File(p.join(incoming.path, 'privat.jpg'))..writeAsBytesSync(List.generate(5000, (i) => i % 256));
    final result = await sourceImport.importFile(photo.path);
    expect(result.outcome, ImportOutcome.imported);

    await sourceLibrary.setupBackupPassphrase('korrektes-passwort');

    final backupDestination = Directory(p.join(tempRoot.path, 'backup_target'));
    await sourceLibrary.runManualBackup(backupDestination.path, encrypt: true).drain<void>();

    final backupRoot = p.join(backupDestination.path, 'PhotoVault-Backup');
    final keyFile = File(p.join(backupRoot, 'vault.key'));
    expect(await keyFile.exists(), isTrue);

    // Die Originaldatei im Backup ist tatsächlich Chiffretext, kein Klartext.
    // Verschlüsselte Backups liegen flach unter data/ mit abgeleiteten,
    // endungslosen Namen (siehe VerschluesselteNamen) – gesucht wird deshalb
    // dort statt unter originals/.
    final datenDir = Directory(p.join(backupRoot, 'data'));
    final backedUpFiles = await datenDir.list(recursive: true).where((e) => e is File).toList();
    expect(backedUpFiles, hasLength(1));
    final backedUpBytes = await File(backedUpFiles.single.path).readAsBytes();
    expect(backedUpBytes, isNot(equals(await photo.readAsBytes())));
    // metadata.json ist ebenfalls kein lesbares JSON mehr.
    final metadataBytes = await File(p.join(backupRoot, 'metadata.json')).readAsBytes();
    expect(String.fromCharCodes(metadataBytes.take(1)), isNot('{'));

    // --- Restore auf einem KOMPLETT anderen "Rechner": frische, leere DB,
    // kein Zugriff auf sourceDb/sourceLibrary, nur Backup-Ordner + Passphrase.
    final targetDb = AppDatabase(NativeDatabase.memory());
    addTearDown(targetDb.close);
    final targetPaths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'target_library')));
    final targetImport = ImportService(targetDb, targetPaths);
    final targetBackup = BackupService(targetDb, targetPaths);

    // Falscher Passphrase schlägt fehl.
    await expectLater(
      targetBackup.restoreFromBackup(backupRoot, targetImport, passphrase: 'falsches-passwort').drain<void>(),
      throwsA(anything),
    );
    expect(await targetDb.select(targetDb.assets).get(), isEmpty);

    // Richtige Passphrase stellt die Originaldatei unverändert wieder her.
    await targetBackup.restoreFromBackup(backupRoot, targetImport, passphrase: 'korrektes-passwort').drain<void>();
    final restoredAssets = await targetDb.select(targetDb.assets).get();
    expect(restoredAssets, hasLength(1));
    final restoredFile = targetPaths.absolute(restoredAssets.single.relativePath);
    expect(await restoredFile.readAsBytes(), equals(await photo.readAsBytes()));
  });

  test('automatisches Backup sichert einen konsistenten DB-Schnappschuss, kopiert nur Neues und löscht nie', () async {
    final tempRoot = Directory.systemTemp.createTempSync('photo_vault_auto_backup_test_');
    addTearDown(() => tempRoot.deleteSync(recursive: true));

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
    final importService = ImportService(db, paths);
    final library = LibraryState()
      ..db = db
      ..paths = paths
      ..backupService = BackupService(db, paths);

    final incoming = Directory(p.join(tempRoot.path, 'incoming'))..createSync();
    final photo1 = File(p.join(incoming.path, 'a.jpg'))..writeAsBytesSync([1, 2, 3]);
    await importService.importFile(photo1.path);

    await library.setupBackupPassphrase('auto-backup-passwort');
    final destination = Directory(p.join(tempRoot.path, 'auto_target'));

    await library.runAutoBackupNow(destination.path).drain<void>();

    final backupRoot = Directory(p.join(destination.path, 'PhotoVault-AutoBackup'));
    final dbSnapshotEnc = File(p.join(backupRoot.path, 'library.sqlite.enc'));
    expect(await dbSnapshotEnc.exists(), isTrue);

    // Der DB-Schnappschuss ist entschlüsselt eine gültige SQLite-Datenbank
    // mit dem importierten Asset – nicht nur eine leere/kaputte Datei.
    final key = await VaultCrypto.unwrapMasterKey(
      'auto-backup-passwort',
      kdfSalt: (await db.backupSettingsRow())!.kdfSalt!,
      nonce: (await db.backupSettingsRow())!.wrappedMasterKeyNonce!,
      wrapped: (await db.backupSettingsRow())!.wrappedMasterKey!,
    );
    final decryptedSnapshot = File(p.join(tempRoot.path, 'decrypted_snapshot.sqlite'));
    await VaultCrypto.decryptFile(dbSnapshotEnc, decryptedSnapshot, key);
    final snapshotDb = AppDatabase(NativeDatabase(decryptedSnapshot));
    final snapshotAssets = await snapshotDb.select(snapshotDb.assets).get();
    expect(snapshotAssets, hasLength(1));
    expect(snapshotAssets.single.originalFileName, 'a.jpg');
    await snapshotDb.close();

    // Ein manuell in den Zielordner gelegtes Fremd-/Testfile darf durch
    // spätere automatische Backup-Läufe nie gelöscht werden.
    final canary = File(p.join(backupRoot.path, 'originals', 'canary.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('darf nicht gelöscht werden');

    // Zweiter Lauf ohne neue Fotos: nichts wird erneut kopiert.
    var secondRunFileCount = 0;
    await for (final p in library.runAutoBackupNow(destination.path)) {
      secondRunFileCount = p.total;
    }
    expect(secondRunFileCount, 0);
    expect(await canary.exists(), isTrue);

    // Ein neu importiertes Foto wird beim nächsten Lauf ergänzt, das erste
    // wird nicht erneut kopiert (eigenes Tracking-Flag: autoBackedUp).
    final photo2 = File(p.join(incoming.path, 'b.jpg'))..writeAsBytesSync([4, 5, 6]);
    await importService.importFile(photo2.path);
    var thirdRunTotal = 0;
    await for (final p in library.runAutoBackupNow(destination.path)) {
      thirdRunTotal = p.total;
    }
    expect(thirdRunTotal, 1);
    expect(await canary.exists(), isTrue);
  });

  test('manuelles und automatisches Backup stören sich nicht gegenseitig (getrennte Tracking-Flags)', () async {
    final tempRoot = Directory.systemTemp.createTempSync('photo_vault_backup_flags_test_');
    addTearDown(() => tempRoot.deleteSync(recursive: true));

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
    final importService = ImportService(db, paths);
    final backupService = BackupService(db, paths);

    final incoming = Directory(p.join(tempRoot.path, 'incoming'))..createSync();
    final photo = File(p.join(incoming.path, 'a.jpg'))..writeAsBytesSync([1, 2, 3]);
    await importService.importFile(photo.path);

    final manualDestination = Directory(p.join(tempRoot.path, 'manual_target'));
    await backupService.performBackup(manualDestination.path).drain<void>();

    // Nach dem manuellen Backup ist "backedUp" gesetzt, "autoBackedUp" aber
    // unangetastet – das automatische Backup zu einem ANDEREN Ziel darf die
    // Datei deshalb trotzdem noch kopieren.
    final assetsForAuto = await db.assetsNotAutoBackedUp();
    expect(assetsForAuto, hasLength(1));
    final assetsForManual = await db.assetsNotBackedUp();
    expect(assetsForManual, isEmpty);
  });
}
