import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// Ein verschlüsseltes Backup soll im Zielordner nichts über den Inhalt
/// verraten – auch nicht über Ordnernamen, Dateiendungen oder Prüfsummen
/// im Dateinamen. Zugleich muss es sich vollständig wiederherstellen
/// lassen, sonst wäre die Verschlüsselung wertlos.
void main() {
  late Directory tempRoot;

  setUp(() => tempRoot = Directory.systemTemp.createTempSync('pv_encnames_'));
  tearDown(() => tempRoot.deleteSync(recursive: true));

  Future<LibraryState> bibliothek(String name) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, name)));
    return LibraryState()
      ..db = db
      ..paths = paths
      ..backupService = BackupService(db, paths);
  }

  test('verschlüsseltes Backup verrät weder Endung noch Ordnerstruktur', () async {
    final lib = await bibliothek('quelle');
    final importService = ImportService(lib.db, lib.paths);

    final incoming = Directory(p.join(tempRoot.path, 'incoming'))..createSync();
    final foto = File(p.join(incoming.path, 'urlaub.jpg'))..writeAsBytesSync([9, 8, 7, 6, 5]);
    await importService.importFile(foto.path);

    await lib.setupBackupPassphrase('geheim-123');
    final ziel = Directory(p.join(tempRoot.path, 'ziel'))..createSync();
    await lib.runManualBackup(ziel.path, encrypt: true).drain<void>();

    final backupRoot = Directory(p.join(ziel.path, 'PhotoVault-Backup'));
    final dateien = backupRoot
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => p.relative(f.path, from: backupRoot.path))
        .toList();

    // Erwartet: vault.key, metadata.json und genau eine namenlose Datendatei.
    expect(dateien.any((f) => f.startsWith('data${Platform.pathSeparator}')), isTrue,
        reason: 'Fotos müssen flach unter data/ liegen');

    final datenDateien = dateien
        .where((f) => f.startsWith('data${Platform.pathSeparator}'))
        .toList();
    expect(datenDateien, hasLength(1));

    final name = p.basename(datenDateien.single);
    expect(p.extension(name), isEmpty, reason: 'keine Dateiendung');
    expect(name, isNot(contains('urlaub')), reason: 'kein Originalname');

    // Auch die Prüfsumme darf nicht im Namen stehen – sonst ließe sich
    // prüfen, ob eine bekannte Datei enthalten ist.
    final assets = await lib.db.select(lib.db.assets).get();
    expect(name, isNot(equals(assets.single.checksum)));

    // Und kein Jahres-/Monatsordner mehr.
    expect(dateien.any((f) => f.contains('originals')), isFalse,
        reason: 'keine Ordnerstruktur nach Aufnahmedatum');
  });

  test('lässt sich vollständig wiederherstellen', () async {
    final quelle = await bibliothek('quelle');
    final quellImport = ImportService(quelle.db, quelle.paths);

    final incoming = Directory(p.join(tempRoot.path, 'incoming'))..createSync();
    for (final n in ['a.jpg', 'b.png']) {
      final f = File(p.join(incoming.path, n))
        ..writeAsBytesSync(List.filled(64, n.codeUnitAt(0)));
      await quellImport.importFile(f.path);
    }
    // Ein Metadatum, das die Wiederherstellung mitbringen muss.
    final ersteId = (await quelle.db.select(quelle.db.assets).get()).first.id;
    await quelle.db.setFavorite(ersteId, true);

    await quelle.setupBackupPassphrase('geheim-123');
    final ziel = Directory(p.join(tempRoot.path, 'ziel'))..createSync();
    await quelle.runManualBackup(ziel.path, encrypt: true).drain<void>();

    // Frische Bibliothek, nur mit Passphrase und Backup-Ordner.
    final neu = await bibliothek('wiederhergestellt');
    final neuImport = ImportService(neu.db, neu.paths);
    await neu.backupService
        .restoreFromBackup(p.join(ziel.path, 'PhotoVault-Backup'), neuImport,
            passphrase: 'geheim-123')
        .drain<void>();

    final wieder = await neu.db.select(neu.db.assets).get();
    expect(wieder, hasLength(2), reason: 'beide Fotos müssen zurückkommen');
    expect(wieder.map((a) => a.originalFileName), unorderedEquals(['a.jpg', 'b.png']),
        reason: 'Originalnamen kommen aus den Metadaten zurück');
    expect(wieder.where((a) => a.isFavorite), hasLength(1),
        reason: 'Metadaten müssen mitkommen');
  });

  test('unverschlüsseltes Backup bleibt lesbar strukturiert', () async {
    final lib = await bibliothek('quelle2');
    final importService = ImportService(lib.db, lib.paths);
    final incoming = Directory(p.join(tempRoot.path, 'incoming2'))..createSync();
    final foto = File(p.join(incoming.path, 'sichtbar.jpg'))..writeAsBytesSync([1, 2, 3]);
    await importService.importFile(foto.path);

    final ziel = Directory(p.join(tempRoot.path, 'ziel2'))..createSync();
    await lib.runManualBackup(ziel.path, encrypt: false).drain<void>();

    final backupRoot = Directory(p.join(ziel.path, 'PhotoVault-Backup'));
    final dateien = backupRoot
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => p.relative(f.path, from: backupRoot.path))
        .toList();

    // Ohne Verschlüsselung ist die durchsuchbare Struktur ein Vorteil und
    // bleibt bewusst erhalten.
    expect(dateien.any((f) => f.contains('originals')), isTrue);
    expect(dateien.any((f) => f.endsWith('.jpg')), isTrue);
    expect(dateien.any((f) => f.startsWith('data${Platform.pathSeparator}')), isFalse);
  });

  test('ein Backup im ALTEN Format bleibt wiederherstellbar', () async {
    final quelle = await bibliothek('alt_quelle');
    final quellImport = ImportService(quelle.db, quelle.paths);

    final incoming = Directory(p.join(tempRoot.path, 'incoming_alt'))..createSync();
    final foto = File(p.join(incoming.path, 'alt.jpg'))..writeAsBytesSync([4, 5, 6, 7]);
    await quellImport.importFile(foto.path);

    await quelle.setupBackupPassphrase('altes-passwort');
    final ziel = Directory(p.join(tempRoot.path, 'ziel_alt'))..createSync();
    await quelle.runManualBackup(ziel.path, encrypt: true).drain<void>();

    // Aus dem neuen Format das alte nachbauen: dieselbe verschlüsselte
    // Datei, aber unter originals/<Jahr>/<Monat>/<uuid>.jpg wie früher.
    // vault.key und metadata.json bleiben unverändert – ihr Format hat sich
    // nicht geändert.
    final backupRoot = Directory(p.join(ziel.path, 'PhotoVault-Backup'));
    final asset = (await quelle.db.select(quelle.db.assets).get()).single;
    final datenDatei = Directory(p.join(backupRoot.path, 'data'))
        .listSync()
        .whereType<File>()
        .single;
    final altesZiel = File(p.join(
        backupRoot.path, asset.relativePath.replaceFirst('originals/', 'originals/')));
    await altesZiel.parent.create(recursive: true);
    await datenDatei.rename(altesZiel.path);
    Directory(p.join(backupRoot.path, 'data')).deleteSync(recursive: true);

    // Wiederherstellen wie von einem älteren Backup.
    final neu = await bibliothek('alt_wiederhergestellt');
    final neuImport = ImportService(neu.db, neu.paths);
    await neu.backupService
        .restoreFromBackup(backupRoot.path, neuImport, passphrase: 'altes-passwort')
        .drain<void>();

    final wieder = await neu.db.select(neu.db.assets).get();
    expect(wieder, hasLength(1), reason: 'altes Format muss weiterhin lesbar sein');
    expect(wieder.single.originalFileName, 'alt.jpg');
  });
}
