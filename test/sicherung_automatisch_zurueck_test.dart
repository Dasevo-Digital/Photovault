import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/state/library_state.dart';

/// Eine automatische Sicherung bringt die Fotos zurück – nicht nur Namen
/// und Stammbaum.
///
/// Bis 3.32 schrieb die automatische Sicherung keine `metadata.json`, und
/// die Wiederherstellung fand die namenlos abgelegten Dateien nur über
/// diese Liste: Zurück kamen die Zeilen aus dem Schnappschuss, aber kein
/// Foto. Jetzt schreibt sie die Liste mit – und fehlt sie (jede ältere
/// Sicherung), nimmt die Wiederherstellung die Fotos aus dem Schnappschuss.
void main() {
  late Directory ordner;

  Future<({AppDatabase db, StoragePaths paths})> bibliothek(String n) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final paths = await StoragePaths.forTesting(
      Directory(p.join(ordner.path, n)),
    );
    return (db: db, paths: paths);
  }

  setUp(() {
    ordner = Directory.systemTemp.createTempSync('pv_auto_zurueck_');
    addTearDown(() => ordner.deleteSync(recursive: true));
  });

  Future<Directory> sichere() async {
    final q = await bibliothek('quelle');
    final import = ImportService(q.db, q.paths);
    final eingang = Directory(p.join(ordner.path, 'eingang'))..createSync();
    for (final (name, inhalt) in [
      ('a.jpg', [1, 2, 3]),
      ('b.jpg', [4, 5, 6, 7]),
    ]) {
      final f = File(p.join(eingang.path, name))..writeAsBytesSync(inhalt);
      await import.importFile(f.path);
    }
    final library = LibraryState()
      ..db = q.db
      ..paths = q.paths
      ..backupService = BackupService(q.db, q.paths);
    await library.setupBackupPassphrase('auto-backup-passwort');
    final ziel = Directory(p.join(ordner.path, 'ziel'));
    await library.runAutoBackupNow(ziel.path).drain<void>();
    return Directory(p.join(ziel.path, 'PhotoVault-AutoBackup'));
  }

  Future<List<AssetData>> holeZurueck(Directory sicherung, String n) async {
    final z = await bibliothek(n);
    await BackupService(z.db, z.paths)
        .restoreFromBackup(
          sicherung.path,
          ImportService(z.db, z.paths),
          passphrase: 'auto-backup-passwort',
        )
        .drain<void>();
    final assets = await z.db.select(z.db.assets).get();
    for (final a in assets) {
      expect(z.paths.absolute(a.relativePath).existsSync(), isTrue);
    }
    return assets;
  }

  test('mit metadata.json', () async {
    final sicherung = await sichere();
    expect(File(p.join(sicherung.path, 'metadata.json')).existsSync(), isTrue);
    final zurueck = await holeZurueck(sicherung, 'neu');
    expect({for (final a in zurueck) a.originalFileName}, {'a.jpg', 'b.jpg'});
  });

  test(
    'eine ältere Sicherung ohne metadata.json: aus dem Schnappschuss',
    () async {
      final sicherung = await sichere();
      File(p.join(sicherung.path, 'metadata.json')).deleteSync();
      final zurueck = await holeZurueck(sicherung, 'alt');
      expect(zurueck, hasLength(2));
    },
  );
}
