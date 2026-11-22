import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/vault_crypto.dart';
import 'package:path/path.dart' as p;

/// Was nach einer Wiederherstellung auf Alben und Aufnahmen zeigt, zeigt
/// auf die zurückgeholten – und ein Album, das schon da ist, kommt nicht
/// ein zweites Mal dazu.
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths pfade;
  late BackupService dienst;
  late List<String> ids;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_verweise_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'library')),
    );
    dienst = BackupService(db, pfade);
    final importe = ImportService(db, pfade);
    ids = [];
    for (var i = 0; i < 3; i++) {
      final f = File(p.join(temp.path, 'bild-$i.jpg'))
        ..writeAsBytesSync(List.filled(1024, i + 1));
      ids.add((await importe.importFile(f.path)).assetId!);
    }
    final angelegt = DateTime.utc(2026, 7, 1);
    await db.fuehreAus(AlbumAnlegen('al-sommer', 'Sommer', angelegt));
    await db.fuehreAus(AlbumFuellen('al-sommer', ids.sublist(0, 2)));
    await db.fuehreAus(AlbumAnlegen('al-leer', 'Neu vom Strand', angelegt));
    await db.fuehreAus(
      RegelSpeichern(
        AutomationRulesCompanion.insert(
          id: 'regel-1',
          name: 'Strand',
          triggerType: 'aiTag',
          aiTagTerm: const Value('beach'),
          targetAlbumId: const Value('al-leer'),
        ),
      ),
    );
    await db.fuehreAus(
      KameravorgabeSpeichern(
        CameraPresetsCompanion.insert(
          id: 'kamera-1',
          cameraMake: 'Canon',
          cameraModel: 'EOS R6',
          targetAlbumId: const Value('al-sommer'),
        ),
      ),
    );
    await db.fuehreAus(
      ReiseAnlegen(
        ReisenCompanion.insert(
          id: 'reise-1',
          name: 'Ostsee',
          von: DateTime.utc(2026, 7, 1),
          bis: DateTime.utc(2026, 7, 8),
          titelbildAssetId: Value(ids[1]),
          angelegtAm: angelegt,
        ),
        ids,
      ),
    );
    await db.fuehreAus(DuplikatgruppeIgnorieren([ids[0], ids[2]]));
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<String> automatischGesichert() async {
    final w = await VaultCrypto.createMasterKey('synthetische-passphrase');
    await db.saveBackupKey(
      kdfSalt: w.kdfSalt,
      nonce: w.nonce,
      wrapped: w.wrapped,
    );
    final ziel = Directory(p.join(temp.path, 'cloud'))..createSync();
    await dienst.performAutoBackup(ziel.path, w.masterKey).drain<void>();
    return p.join(ziel.path, BackupService.autoBackupFolderName);
  }

  Future<List<BackupProgress>> stelleHer(
    AppDatabase ziel,
    StoragePaths zielpfade,
    String wurzel,
  ) => BackupService(ziel, zielpfade)
      .restoreFromBackup(
        wurzel,
        ImportService(ziel, zielpfade),
        passphrase: 'synthetische-passphrase',
      )
      .toList();

  test('Zielalben, Titelbild und Duplikat-Ausnahmen zeigen auf das '
      'Zurückgeholte', () async {
    final wurzel = await automatischGesichert();
    final ziel = AppDatabase(NativeDatabase.memory());
    addTearDown(ziel.close);
    final zielpfade = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'ziel_lib')),
    );
    final verlauf = await stelleHer(ziel, zielpfade, wurzel);
    expect(verlauf.last.wiederherstellung?.probleme, isEmpty);

    final hier = {
      for (final a in await db.select(db.assets).get())
        a.id: (await (ziel.select(
          ziel.assets,
        )..where((t) => t.checksum.equals(a.checksum))).getSingle()).id,
    };
    final alben = {
      for (final a in await ziel.select(ziel.albums).get()) a.name: a.id,
    };
    expect(alben.keys, containsAll(['Sommer', 'Neu vom Strand']));

    final regel = await ziel.select(ziel.automationRules).getSingle();
    expect(regel.targetAlbumId, alben['Neu vom Strand']);
    final kamera = await ziel.select(ziel.cameraPresets).getSingle();
    expect(kamera.targetAlbumId, alben['Sommer']);
    final reise = await ziel.select(ziel.reisen).getSingle();
    expect(reise.titelbildAssetId, hier[ids[1]]);
    final paar = await ziel.select(ziel.duplikatAusnahmen).getSingle();
    final erwartet = [hier[ids[0]]!, hier[ids[2]]!]..sort();
    expect([paar.assetA, paar.assetB], erwartet);
  });

  test('ein vorhandenes Album kommt nicht ein zweites Mal dazu', () async {
    // Von Hand, unverschlüsselt: die Alben kommen allein aus der Beilage.
    final stick = Directory(p.join(temp.path, 'stick'))..createSync();
    await dienst.performBackup(stick.path).drain<void>();
    final wurzel = p.join(stick.path, BackupService.backupFolderName);

    // In dieselbe Bibliothek zurück, wie beim Zurückholen einzelner
    // Fotos nach einem Versehen.
    await dienst
        .restoreFromBackup(wurzel, ImportService(db, pfade))
        .drain<void>();
    final alben = await db.select(db.albums).get();
    expect(alben.where((a) => a.name == 'Sommer'), hasLength(1));
    expect(await db.assetsInAlbumOnce('al-sommer'), hasLength(2));

    // Zweimal in eine neue Bibliothek: auch dort nur einmal.
    final ziel = AppDatabase(NativeDatabase.memory());
    addTearDown(ziel.close);
    final zielpfade = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'ziel_lib')),
    );
    for (var i = 0; i < 2; i++) {
      await BackupService(
        ziel,
        zielpfade,
      ).restoreFromBackup(wurzel, ImportService(ziel, zielpfade)).drain<void>();
    }
    final dort = await ziel.select(ziel.albums).get();
    expect(dort.where((a) => a.name == 'Sommer'), hasLength(1));
  });
}
