import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:kern/services/raw_identify_parser.dart';
import 'package:kern/services/vault_crypto.dart';

class _WechselndeQuelle extends KeineBildwerkzeuge {
  _WechselndeQuelle(this.neueBytes);
  final List<int> neueBytes;
  @override
  Future<Aufnahmedaten> readCameraMetadata(File file) async {
    await file.writeAsBytes(neueBytes);
    return Aufnahmedaten.leer;
  }
}

class _ZielDb extends AppDatabase {
  _ZielDb(super.executor);
}

void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths paths;
  late ImportService importer;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_codeaudit_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory('${temp.path}/bibliothek'));
    importer = ImportService(
      db,
      paths,
      bildwerkzeuge: const KeineBildwerkzeuge(),
    );
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });
  List<int> bild(int rot) => img.encodePng(
    img.Image(width: 16, height: 16)..clear(img.ColorRgb8(rot, 80, 140)),
  );

  test(
    'Import ohne Plan erhält die Prüfsumme der tatsächlich kopierten Datei',
    () async {
      final a = bild(20), b = bild(210);
      final file = File('${temp.path}/wechsel.cr2')..writeAsBytesSync(a);
      final imp = ImportService(db, paths, bildwerkzeuge: _WechselndeQuelle(b));
      final r = await imp.importFile(file.path);
      expect(r.outcome, ImportOutcome.failed);
      expect(await db.select(db.assets).get(), isEmpty);
      expect(
        await paths.originalsDir
            .list(recursive: true)
            .where((e) => e is File)
            .toList(),
        isEmpty,
      );
    },
  );

  for (final format in [1, 2]) {
    test(
      'Generation Format $format verwendet ihre eigene Fotomenge und Metadaten',
      () async {
        final file = File('${temp.path}/alt.png')..writeAsBytesSync(bild(30));
        final id = (await importer.importFile(file.path)).assetId!;
        await db.setDescription(id, 'alter Stand');
        await db.tagAsset(id, 'altes Schlagwort');
        await db.createAlbum(
          AlbumsCompanion.insert(
            id: 'altes-album',
            name: 'Altes Album',
            createdAt: DateTime(2026),
          ),
        );
        await db.addAssetsToAlbum('altes-album', [id]);
        final key = await VaultCrypto.createMasterKey(
          'synthetische-pruefpassphrase',
        );
        await db.saveBackupKey(
          kdfSalt: key.kdfSalt,
          nonce: key.nonce,
          wrapped: key.wrapped,
        );
        final backup = BackupService(db, paths);
        await backup
            .performAutoBackup('${temp.path}/backup', key.masterKey)
            .drain<void>();
        final root =
            '${temp.path}/backup/${BackupService.autoBackupFolderName}';
        final generation = (await backup.autoBackupGenerations(root)).single;
        if (format == 1) {
          final ordner = File(generation.snapshotPath).parent;
          await File('${ordner.path}/metadata.json').delete();
          await File('${ordner.path}/generation.json').writeAsString(
            jsonEncode({
              'format': 1,
              'createdAt': generation.createdAt.toUtc().toIso8601String(),
            }),
          );
        }
        await db.setDescription(id, 'neuer Stand');
        await db.tagAsset(id, 'neues Schlagwort');
        await db.createAlbum(
          AlbumsCompanion.insert(
            id: 'neues-album',
            name: 'Neues Album',
            createdAt: DateTime(2026),
          ),
        );
        await db.addAssetsToAlbum('neues-album', [id]);
        final neu = File('${temp.path}/neu.png')..writeAsBytesSync(bild(200));
        await importer.importFile(neu.path);
        await backup
            .performAutoBackup('${temp.path}/backup', key.masterKey)
            .drain<void>();
        final zielDb = _ZielDb(NativeDatabase.memory());
        final zielPaths = await StoragePaths.forTesting(
          Directory('${temp.path}/ziel'),
        );
        try {
          await BackupService(zielDb, zielPaths)
              .restoreFromBackup(
                root,
                ImportService(
                  zielDb,
                  zielPaths,
                  bildwerkzeuge: const KeineBildwerkzeuge(),
                ),
                passphrase: 'synthetische-pruefpassphrase',
                generationSnapshotPath: generation.snapshotPath,
              )
              .drain<void>();
          final fotos = await zielDb.select(zielDb.assets).get();
          expect(
            fotos
                .singleWhere((a) => a.originalFileName == 'alt.png')
                .description,
            'alter Stand',
            reason:
                'Der gewählte Datenbankstand muss seine eigene Beschreibung wiederherstellen.',
          );
          expect(
            fotos,
            hasLength(1),
            reason:
                'Später hinzugefügte Fotos gehören nicht zum alten Wiederherstellungspunkt.',
          );
          expect(
            (await zielDb.tagsForAsset(fotos.single.id)).map((t) => t.name),
            ['altes Schlagwort'],
          );
          expect(
            (await zielDb.select(zielDb.albums).get()).map((a) => a.name),
            ['Altes Album'],
          );
        } finally {
          await zielDb.close();
        }
      },
    );
  }

  test('Wiederherstellung meldet fehlgeschlagene Importe sichtbar', () async {
    final root = Directory('${temp.path}/backup/originals')
      ..createSync(recursive: true);
    File('${root.path}/foto.png').writeAsBytesSync(bild(50));
    await paths.originalsDir.delete(recursive: true);
    File(paths.originalsDir.path).writeAsStringSync('Ablage blockiert');
    final progress = await BackupService(
      db,
      paths,
    ).restoreFromBackup('${temp.path}/backup', importer).toList();
    final anzahl = (await db.select(db.assets).get()).length;
    expect(anzahl, 0);
    expect(progress.last.wiederherstellung!.importiert, 0);
    expect(progress.last.wiederherstellung!.erfolgreich, isFalse);
    expect(
      progress.any((p) => (p.fehlgeschlagen ?? 0) > 0),
      isTrue,
      reason:
          'Eine gescheiterte Wiederherstellung darf keinen vollständigen Erfolg melden.',
    );
  });
}
