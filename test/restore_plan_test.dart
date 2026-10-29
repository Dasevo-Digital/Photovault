import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_manifest.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/vault_crypto.dart';

void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths paths;
  late ImportService importe;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_restore_plan_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory('${temp.path}/bibliothek'));
    importe = ImportService(
      db,
      paths,
      bildwerkzeuge: const KeineBildwerkzeuge(),
    );
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });
  Map<String, Object?> aufnahme(String name, List<int> bytes) => {
    'checksum': sha256.convert(bytes).toString(),
    'originalFileName': name,
    'backupRelativePath': 'originals/$name',
  };

  test('Manifest bilanziert defekte und doppelte Einträge einzeln', () {
    final row = aufnahme('foto.jpg', [1, 2, 3]);
    final text = jsonEncode({
      'format': 1,
      'assets': [
        row,
        row,
        {'checksum': 7},
      ],
      'albums': [
        {
          'assetChecksums': [4],
        },
      ],
    });
    final manifest = BackupManifest.ausText(text);
    expect(manifest.aufnahmen, hasLength(1));
    expect(manifest.probleme, hasLength(3));
    expect(
      () => BackupManifest.ausText(text, streng: true),
      throwsA(isA<FormatException>()),
    );
    expect(() => manifest.aufnahmen.clear(), throwsUnsupportedError);
  });
  test('Unbekannte Manifestversionen werden ausdrücklich abgelehnt', () {
    expect(
      () => BackupManifest.ausText('{"format": 99}'),
      throwsFormatException,
    );
  });
  test('Manifest-Rundlauf erhält Zeitstempel und zusätzliche Metadaten', () {
    final row = {
      ...aufnahme('foto.jpg', [1]),
      'spaeteresFeld': 42,
    };
    final text = jsonEncode({
      'format': 1,
      'exportedAt': '2026-10-29T10:00:00Z',
      'assets': [row],
    });
    final einmal = BackupManifest.ausText(text);
    final zweimal = BackupManifest.ausText(jsonEncode(einmal.alsJson()));
    expect(zweimal.aufnahmen.single.werte, row);
    expect(zweimal.exportiertAm, DateTime.utc(2026, 10, 29, 10));
  });
  test(
    'Vorhandene und fehlende Originale haben getrennte Ergebniszähler',
    () async {
      final original = File('${temp.path}/backup/originals/foto.jpg');
      await original.parent.create(recursive: true);
      await original.writeAsBytes([1, 2, 3]);
      await importe.importFile(original.path);
      await File('${temp.path}/backup/metadata.json').writeAsString(
        jsonEncode({
          'format': 1,
          'assets': [
            aufnahme('foto.jpg', [1, 2, 3]),
            aufnahme('fehlt.jpg', [4, 5, 6]),
          ],
        }),
      );
      final lauf = await BackupService(
        db,
        paths,
      ).restoreFromBackup('${temp.path}/backup', importe).toList();
      final r = lauf.last.wiederherstellung!;
      expect(r.geplant, 2);
      expect(r.vorhanden, 1);
      expect(r.importiert, 0);
      expect(r.fehlend, 1);
      expect(r.gescheitert, 0);
      expect(r.erfolgreich, isFalse);
      expect(lauf.last.done, 2);
    },
  );
  test(
    'Fehlerhafte Metadaten werden trotz erfolgreichem Dateiimport bilanziert',
    () async {
      final original = File('${temp.path}/backup/originals/foto.jpg');
      await original.parent.create(recursive: true);
      await original.writeAsBytes([1, 2, 3]);
      await File('${temp.path}/backup/metadata.json').writeAsString(
        jsonEncode({
          'format': 1,
          'assets': [
            {
              ...aufnahme('foto.jpg', [1, 2, 3]),
              'tags': 7,
            },
          ],
        }),
      );
      final lauf = await BackupService(
        db,
        paths,
      ).restoreFromBackup('${temp.path}/backup', importe).toList();
      expect(lauf.last.wiederherstellung!.importiert, 1);
      expect(lauf.last.wiederherstellung!.probleme, isNotEmpty);
      expect(lauf.last.wiederherstellung!.erfolgreich, isFalse);
    },
  );
  test('Ein ausgewählter fremder Snapshot importiert keine Dateien', () async {
    final original = File('${temp.path}/backup/originals/foto.jpg');
    await original.parent.create(recursive: true);
    await original.writeAsBytes([1, 2, 3]);
    final fremd = File('${temp.path}/library.sqlite.enc')
      ..writeAsStringSync('fremd');
    await expectLater(
      BackupService(db, paths)
          .restoreFromBackup(
            '${temp.path}/backup',
            importe,
            generationSnapshotPath: fremd.path,
          )
          .drain<void>(),
      throwsFormatException,
    );
    expect(await db.select(db.assets).get(), isEmpty);
  });
  for (final datei in ['library.sqlite.enc', 'metadata.json']) {
    test(
      'Eine beschädigte Generation ($datei) fällt vor dem Import auf',
      () async {
        final original = File('${temp.path}/foto.jpg')
          ..writeAsBytesSync([1, 2, 3]);
        await importe.importFile(original.path);
        final key = await VaultCrypto.createMasterKey(
          'synthetische-plan-passphrase',
        );
        await db.saveBackupKey(
          kdfSalt: key.kdfSalt,
          nonce: key.nonce,
          wrapped: key.wrapped,
        );
        final service = BackupService(db, paths);
        await service
            .performAutoBackup('${temp.path}/backup', key.masterKey)
            .drain<void>();
        final root =
            '${temp.path}/backup/${BackupService.autoBackupFolderName}';
        final generation = (await service.autoBackupGenerations(root)).single;
        await File(
          '${File(generation.snapshotPath).parent.path}/$datei',
        ).writeAsBytes([7]);
        final zielDb = AppDatabase(NativeDatabase.memory());
        try {
          final zielPaths = await StoragePaths.forTesting(
            Directory('${temp.path}/ziel'),
          );
          final zielImport = ImportService(
            zielDb,
            zielPaths,
            bildwerkzeuge: const KeineBildwerkzeuge(),
          );
          await expectLater(
            BackupService(zielDb, zielPaths)
                .restoreFromBackup(
                  root,
                  zielImport,
                  generationSnapshotPath: generation.snapshotPath,
                  entschluesselungsschluessel: key.masterKey,
                )
                .drain<void>(),
            throwsFormatException,
          );
          expect(await zielDb.select(zielDb.assets).get(), isEmpty);
        } finally {
          await zielDb.close();
        }
      },
    );
  }
  test(
    'Abbruch des Restore-Streams entfernt sein privates Zwischenlager',
    () async {
      final original = File('${temp.path}/backup/originals/foto.jpg');
      await original.parent.create(recursive: true);
      await original.writeAsBytes([1, 2, 3]);
      final lager = Directory('${temp.path}/zwischenlager')..createSync();
      await BackupService(db, paths)
          .restoreFromBackup(
            '${temp.path}/backup',
            importe,
            zwischenlager: lager,
          )
          .first;
      expect(lager.listSync(), isEmpty);
      expect(await db.select(db.assets).get(), isEmpty);
    },
  );
}
