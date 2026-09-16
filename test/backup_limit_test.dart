import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Die Portionsgrenze soll einen Cloud-Sync-Ordner davor bewahren, in einem
/// Rutsch mit der gesamten Bibliothek geflutet zu werden. Entscheidend ist
/// dabei: Was nicht geschrieben wurde, darf auch nicht als gesichert
/// markiert werden – sonst ginge es beim nächsten Lauf verloren.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late StoragePaths paths;
  late ImportService importService;
  late BackupService backupService;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_backup_limit_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
    importService = ImportService(db, paths);
    backupService = BackupService(db, paths);
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  /// Legt [anzahl] Fotos mit je [bytes] Nutzdaten an.
  Future<void> importiere(int anzahl, {int bytes = 100 * 1024}) async {
    final incoming = Directory(p.join(tempRoot.path, 'incoming'))..createSync(recursive: true);
    for (var i = 0; i < anzahl; i++) {
      final f = File(p.join(incoming.path, 'foto_$i.jpg'));
      await f.writeAsBytes(List.filled(bytes, i % 256));
      await importService.importFile(f.path);
    }
  }

  int dateienImZiel(Directory ziel) {
    final originals = Directory(p.join(ziel.path, 'PhotoVault-Backup', 'originals'));
    if (!originals.existsSync()) return 0;
    return originals
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => !f.path.endsWith('.xmp'))
        .length;
  }

  test('ohne Grenze wird alles in einem Lauf gesichert', () async {
    await importiere(5);
    final ziel = Directory(p.join(tempRoot.path, 'ziel'))..createSync();

    await backupService.performBackup(ziel.path).drain<void>();

    expect(dateienImZiel(ziel), 5);
    expect(await db.assetsNotBackedUp(), isEmpty);
  });

  test('mit Grenze wird nur ein Teil gesichert, der Rest bleibt offen', () async {
    // 5 Fotos à 100 KB, Grenze 250 KB -> nach 3 Dateien ist die Grenze
    // überschritten, die vierte startet nicht mehr.
    await importiere(5, bytes: 100 * 1024);
    final ziel = Directory(p.join(tempRoot.path, 'ziel'))..createSync();

    await backupService
        .performBackup(ziel.path, maxBytesPerRun: 250 * 1024)
        .drain<void>();

    final geschrieben = dateienImZiel(ziel);
    expect(geschrieben, lessThan(5), reason: 'die Grenze muss greifen');
    expect(geschrieben, greaterThan(0), reason: 'etwas muss gesichert werden');

    final offen = await db.assetsNotBackedUp();
    expect(offen, hasLength(5 - geschrieben),
        reason: 'nicht Gesichertes darf NICHT als gesichert markiert sein');
  });

  test('der nächste Lauf holt den Rest nach', () async {
    await importiere(5, bytes: 100 * 1024);
    final ziel = Directory(p.join(tempRoot.path, 'ziel'))..createSync();

    await backupService.performBackup(ziel.path, maxBytesPerRun: 250 * 1024).drain<void>();
    final nachErstem = dateienImZiel(ziel);

    // Zweiter Lauf ohne Grenze: alles Übrige.
    await backupService.performBackup(ziel.path).drain<void>();

    expect(dateienImZiel(ziel), 5);
    expect(await db.assetsNotBackedUp(), isEmpty);
    expect(nachErstem, lessThan(5), reason: 'sonst prüft der Test nichts');
  });

  test('der Sicherungsbericht zählt nur tatsächlich Gesichertes', () async {
    await importiere(5, bytes: 100 * 1024);
    final ziel = Directory(p.join(tempRoot.path, 'ziel'))..createSync();

    await backupService.performBackup(ziel.path, maxBytesPerRun: 250 * 1024).drain<void>();

    final bericht = await db.lastBackupRecord();
    expect(bericht!.fileCount, dateienImZiel(ziel),
        reason: 'der Bericht darf nicht mehr behaupten, als geschafft wurde');
  });

  test('im Ziel bleiben keine Zwischendateien liegen', () async {
    await importiere(3);
    final ziel = Directory(p.join(tempRoot.path, 'ziel'))..createSync();

    await backupService.performBackup(ziel.path).drain<void>();

    final reste = Directory(p.join(ziel.path, 'PhotoVault-Backup'))
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => p.basename(f.path) == 'teil' || f.path.endsWith('.part'))
        .toList();
    expect(reste, isEmpty);
  });
}
