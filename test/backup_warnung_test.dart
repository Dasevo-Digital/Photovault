import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/state/library_state.dart';

/// Das automatische Backup bleibt nicht mehr wortlos aus (#207): Fällig,
/// aber ohne Passphrase in dieser Sitzung, steht eine Warnung bereit –
/// mit dem Alter des letzten Laufs. Läuft es, verschwindet sie.
void main() {
  late Directory temp;
  late AppDatabase db;
  late LibraryState bib;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pv_backupwarnung_');
    db = AppDatabase(NativeDatabase.memory());
    final pfade = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'lib')),
    );
    bib = LibraryState()
      ..db = db
      ..paths = pfade
      ..backupService = BackupService(db, pfade);
  });

  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  test(
    'fällig ohne Passphrase: Warnung; mit Passphrase: Lauf, keine',
    () async {
      final ziel = Directory(p.join(temp.path, 'ziel'))..createSync();
      await db.setAutoBackupConfig(
        enabled: true,
        destination: ziel.path,
        intervalHours: 24 * 7,
      );
      // Auf die Sekunde – so speichert die Datenbank.
      final jetzt = DateTime.now();
      final vorWochen = DateTime(
        jetzt.year,
        jetzt.month,
        jetzt.day - 23,
        jetzt.hour,
        jetzt.minute,
        jetzt.second,
      );
      await db.setLastAutoBackupAt(vorWochen);

      await bib.runAutoBackupIfDue();
      final w = bib.backupwarnung.value;
      expect(w?.grund, Backuphindernis.passphrase);
      expect(w!.letzterLauf, vorWochen);

      await bib.setupBackupPassphrase('eine lange passphrase');
      await bib.runAutoBackupIfDue();
      expect(bib.backupwarnung.value, isNull);
      expect(
        (await db.backupSettingsRow())!.lastAutoBackupAt!.isAfter(vorWochen),
        isTrue,
      );
    },
  );

  test('nicht fällig: keine Warnung, auch ohne Passphrase', () async {
    await db.setAutoBackupConfig(
      enabled: true,
      destination: temp.path,
      intervalHours: 24 * 7,
    );
    await db.setLastAutoBackupAt(
      DateTime.now().subtract(const Duration(days: 2)),
    );
    await bib.runAutoBackupIfDue();
    expect(bib.backupwarnung.value, isNull);
  });
}
