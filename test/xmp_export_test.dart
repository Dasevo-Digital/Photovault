import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/export_service.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:xml/xml.dart';

/// Prüft die drei Schreib-Orte für XMP-Sidecars (siehe xmp_writer.dart):
/// Bulk-Werkzeug (LibraryState.writeXmpSidecars), Export (ExportService)
/// und unverschlüsseltes Backup (BackupService) – insbesondere, dass
/// gesperrte Assets bzw. verschlüsselte Backups korrekt ausgeschlossen
/// werden (siehe AppDatabase.assetsForXmpExport).
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late StoragePaths paths;
  late ImportService import;
  var nextByte = 0;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('photo_vault_xmp_test_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
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

  group('LibraryState.writeXmpSidecars (Bulk-Werkzeug)', () {
    late LibraryState library;

    setUp(() {
      library = LibraryState()
        ..db = db
        ..paths = paths;
    });

    test('schreibt eine .xmp-Datei neben jedes (nicht gesperrte) Original', () async {
      final a = await importPhoto('a.jpg');
      await db.setRating(a.id, 5);
      await db.tagAsset(a.id, 'urlaub');

      await library.writeXmpSidecars().drain<void>();

      final sidecar = paths.absolute(paths.xmpSidecarPath(a.relativePath));
      expect(await sidecar.exists(), isTrue);
      final doc = XmlDocument.parse(await sidecar.readAsString());
      expect(doc.findAllElements('rdf:Description').single.getAttribute('xmp:Rating'), '5');
    });

    test('überspringt gesperrte Assets (kein Klartext-Sidecar neben verschlüsseltem Original)', () async {
      final locked = await importPhoto('locked.jpg');
      await db.setAssetsLocked([locked.id], true);

      await library.writeXmpSidecars().drain<void>();

      final sidecar = paths.absolute(paths.xmpSidecarPath(locked.relativePath));
      expect(await sidecar.exists(), isFalse);
    });
  });

  group('ExportService.exportAsset', () {
    test('legt eine .xmp-Sidecar-Datei neben die exportierte Datei', () async {
      final a = await importPhoto('urlaub.jpg');
      await db.setDescription(a.id, 'Am Strand');
      await db.tagAsset(a.id, 'strand');

      final exporter = ExportService(paths, library: LibraryState()..db = db..paths = paths);
      final destination = Directory(p.join(tempRoot.path, 'export'))..createSync();
      final exportedName = await exporter.exportAsset(a, destination.path);

      final sidecar = File(p.join(destination.path, p.setExtension(exportedName, '.xmp')));
      expect(await sidecar.exists(), isTrue);
      final doc = XmlDocument.parse(await sidecar.readAsString());
      final tags = doc.findAllElements('dc:subject').single.findAllElements('rdf:li').map((e) => e.innerText);
      expect(tags, ['strand']);
    });

    test('exportiert auch für gesperrte Assets eine Sidecar-Datei (Nutzer hat Export aktiv angestoßen)',
        () async {
      final a = await importPhoto('geheim.jpg');
      await db.setAssetsLocked([a.id], true);
      final locked = (await db.assetById(a.id))!;

      // Ohne `library:` (kein Entschlüsseln nötig, da die Originaldatei im
      // Test-Setup ohnehin nicht tatsächlich verschlüsselt wird) – die
      // Sidecar-Erzeugung selbst hängt nicht am Sperrstatus.
      final exporter = ExportService(paths);
      final destination = Directory(p.join(tempRoot.path, 'export'))..createSync();
      final exportedName = await exporter.exportAsset(locked, destination.path);

      final sidecar = File(p.join(destination.path, p.setExtension(exportedName, '.xmp')));
      expect(await sidecar.exists(), isTrue);
    });
  });

  group('BackupService.performBackup', () {
    test('schreibt Sidecars bei einem unverschlüsselten Backup', () async {
      final a = await importPhoto('a.jpg');
      await db.setRating(a.id, 3);
      final backup = BackupService(db, paths);
      final destination = Directory(p.join(tempRoot.path, 'backup_target'));

      await backup.performBackup(destination.path).drain<void>();

      final backupRoot = p.join(destination.path, 'PhotoVault-Backup');
      final copiedOriginal = File(p.join(backupRoot, a.relativePath));
      expect(await copiedOriginal.exists(), isTrue);
      final sidecar = File(p.setExtension(copiedOriginal.path, '.xmp'));
      expect(await sidecar.exists(), isTrue);
    });

    test('schreibt KEINE Sidecars bei einem verschlüsselten Backup', () async {
      await importPhoto('a.jpg');
      final backup = BackupService(db, paths);
      final destination = Directory(p.join(tempRoot.path, 'backup_target'));

      // Die genaue Herkunft des Schlüssels (Passphrase-Ableitung) spielt
      // hier keine Rolle – ein beliebiger 32-Byte-Schlüssel genügt, um den
      // verschlüsselten Zweig auszulösen.
      final key = SecretKey(List<int>.generate(32, (i) => i));
      await backup.performBackup(destination.path, encryptionKey: key).drain<void>();

      // Verschlüsselte Backups liegen flach unter data/ mit abgeleiteten
      // Namen (siehe VerschluesselteNamen) – deshalb nicht mehr über den
      // ursprünglichen relativen Pfad gesucht, sondern über den Ordner.
      final backupRoot = Directory(p.join(destination.path, 'PhotoVault-Backup'));
      final alleDateien = backupRoot.listSync(recursive: true).whereType<File>().toList();

      expect(alleDateien.where((f) => p.dirname(f.path).endsWith('data')), hasLength(1),
          reason: 'die verschlüsselte Datei muss vorhanden sein');
      // Der eigentliche Zweck dieses Tests: nirgends ein Klartext-Sidecar,
      // das die Vertraulichkeit der Verschlüsselung unterlaufen würde.
      expect(alleDateien.where((f) => f.path.endsWith('.xmp')), isEmpty);
    });
  });
}
