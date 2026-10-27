import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault/services/tresor_dateiwechsel.dart';
import 'package:photo_vault/state/library_state.dart';

void main() {
  late Directory root;
  late AppDatabase db;
  late StoragePaths paths;
  late LibraryState library;
  late AssetData asset;
  final original = List<int>.generate(200, (i) => i);
  const mini = 'thumbnails/abbruch.jpg';

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pv_tresor_abbruch_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory('${root.path}/library'));
    final eingang = File('${root.path}/probe.jpg')..writeAsBytesSync(original);
    final ergebnis = await ImportService(db, paths).importFile(eingang.path);
    paths.absolute(mini).writeAsBytesSync([4, 5, 6]);
    await db.customStatement(
      'UPDATE assets SET thumbnail_relative_path = ?, description = ? WHERE id = ?',
      [mini, 'Private Beschreibung', ergebnis.assetId],
    );
    asset = (await db.assetById(ergebnis.assetId!))!;
    library = LibraryState()
      ..db = db
      ..paths = paths;
    await library.setupVaultPin('synthetische testpassphrase');
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  void keineReste() {
    expect(
      paths.root
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) =>
                f.path.endsWith('.vaulttmp') ||
                f.path.endsWith('.vaultalt') ||
                f.path.endsWith('vault_dateiwechsel.json'),
          ),
      isEmpty,
    );
  }

  test(
    'Fehler beim Vorbereiten verändert kein Original; Wiederholung ist verlustfrei',
    () async {
      final blocker = Directory('${paths.absolute(mini).path}.vaulttmp')
        ..createSync();
      await expectLater(
        library.lockAsset(asset),
        throwsA(isA<FileSystemException>()),
      );
      expect((await db.assetById(asset.id))!.isLocked, isFalse);
      expect(await paths.absolute(asset.relativePath).readAsBytes(), original);
      await blocker.delete();
      await library.lockAsset(asset);
      await library.unlockAsset((await db.assetById(asset.id))!);
      expect(await paths.absolute(asset.relativePath).readAsBytes(), original);
      expect((await db.assetById(asset.id))!.description, asset.description);
      keineReste();
    },
  );

  test(
    'gescheiterte Entschlüsselung lässt alle verschlüsselten Dateien unverändert',
    () async {
      await library.lockAsset(asset);
      final vorher = await paths.absolute(asset.relativePath).readAsBytes();
      final blocker = Directory('${paths.absolute(mini).path}.vaulttmp')
        ..createSync();
      await expectLater(
        library.unlockAsset((await db.assetById(asset.id))!),
        throwsA(isA<FileSystemException>()),
      );
      expect((await db.assetById(asset.id))!.isLocked, isTrue);
      expect(await paths.absolute(asset.relativePath).readAsBytes(), vorher);
      await blocker.delete();
      await library.unlockAsset((await db.assetById(asset.id))!);
      expect(await paths.absolute(asset.relativePath).readAsBytes(), original);
      keineReste();
    },
  );

  test(
    'Live-Photo-Partner wechseln nur gemeinsam und bleiben wiederholbar',
    () async {
      final eingang = File('${root.path}/partner.jpg')
        ..writeAsBytesSync(original.reversed.toList());
      final import = await ImportService(db, paths).importFile(eingang.path);
      final partner = (await db.assetById(import.assetId!))!;
      await db.customStatement(
        'UPDATE assets SET linked_asset_id = ? WHERE id = ?',
        [partner.id, asset.id],
      );
      await db.customStatement(
        'UPDATE assets SET linked_asset_id = ? WHERE id = ?',
        [asset.id, partner.id],
      );
      final blocker = Directory(
        '${paths.absolute(partner.relativePath).path}.vaulttmp',
      )..createSync();
      await expectLater(
        library.lockAsset(asset),
        throwsA(isA<FileSystemException>()),
      );
      expect((await db.assetById(asset.id))!.isLocked, isFalse);
      expect((await db.assetById(partner.id))!.isLocked, isFalse);
      expect(await paths.absolute(asset.relativePath).readAsBytes(), original);
      expect(
        await paths.absolute(partner.relativePath).readAsBytes(),
        original.reversed.toList(),
      );
      await blocker.delete();
      await library.lockAsset(asset);
      expect((await db.assetById(partner.id))!.isLocked, isTrue);
      await library.unlockAsset(partner);
      expect((await db.assetById(asset.id))!.isLocked, isFalse);
      expect((await db.assetById(partner.id))!.isLocked, isFalse);
      expect(await paths.absolute(asset.relativePath).readAsBytes(), original);
      expect(
        await paths.absolute(partner.relativePath).readAsBytes(),
        original.reversed.toList(),
      );
      keineReste();
    },
  );

  test(
    'Abbruch beim Vorbereiten entfernt Teilkopien ohne Originalwechsel',
    () async {
      final wechsel = TresorDateiwechsel(paths);
      await wechsel.zwischen(asset.relativePath).writeAsBytes([9, 8]);
      await paths
          .absolute('vault_dateiwechsel.json')
          .writeAsString(
            jsonEncode({
              'fassung': 1,
              'phase': 'vorbereiten',
              'sperren': false,
              'ids': [asset.id],
              'dateien': [asset.relativePath],
              'entfernen': [],
            }),
          );
      await wechsel.erhole(
        abgeschlossen: (_, _) async => fail('Noch keine Datenbankänderung'),
        datenbank: (_, _) async => fail('Noch kein Dateiwechsel'),
      );
      expect(await paths.absolute(asset.relativePath).readAsBytes(), original);
      keineReste();
    },
  );

  test(
    'unterbrochenes Sperren wird nach neuem Start ohne PIN fertiggestellt',
    () async {
      await db.customStatement(
        "CREATE TRIGGER sperrfehler BEFORE UPDATE OF is_locked ON assets WHEN NEW.is_locked = 1 BEGIN SELECT RAISE(ABORT, 'probe'); END",
      );
      await expectLater(library.lockAsset(asset), throwsA(anything));
      expect((await db.assetById(asset.id))!.isLocked, isFalse);
      expect(
        String.fromCharCodes(
          (await paths.absolute(asset.relativePath).readAsBytes()).take(4),
        ),
        'PVE3',
      );
      await db.customStatement('DROP TRIGGER sperrfehler');
      final neu = LibraryState()
        ..db = db
        ..paths = paths;
      await neu.erholeTresorDateiwechsel();
      expect((await db.assetById(asset.id))!.isLocked, isTrue);
      expect((await db.assetById(asset.id))!.description, isNull);
      await library.unlockAsset((await db.assetById(asset.id))!);
      expect(await paths.absolute(asset.relativePath).readAsBytes(), original);
      expect((await db.assetById(asset.id))!.description, asset.description);
      keineReste();
    },
  );

  test(
    'Datenbankfehler beim Entsperren nimmt Dateien und Metadaten zurück',
    () async {
      await library.lockAsset(asset);
      final vorher = await paths.absolute(asset.relativePath).readAsBytes();
      await db.customStatement(
        "CREATE TRIGGER entsperrfehler BEFORE UPDATE OF is_locked ON assets WHEN NEW.is_locked = 0 BEGIN SELECT RAISE(ABORT, 'probe'); END",
      );
      await expectLater(
        library.unlockAsset((await db.assetById(asset.id))!),
        throwsA(anything),
      );
      expect((await db.assetById(asset.id))!.isLocked, isTrue);
      expect((await db.assetById(asset.id))!.description, isNull);
      expect(await paths.absolute(asset.relativePath).readAsBytes(), vorher);
      expect(
        await paths
            .absolute(paths.vaultMetadataRelativePath(asset.id))
            .exists(),
        isTrue,
      );
      await db.customStatement('DROP TRIGGER entsperrfehler');
      await library.unlockAsset((await db.assetById(asset.id))!);
      expect(await paths.absolute(asset.relativePath).readAsBytes(), original);
      expect((await db.assetById(asset.id))!.description, asset.description);
      keineReste();
    },
  );

  test(
    'zwei parallele Sperrversuche verschlüsseln das Original nur einmal',
    () async {
      await Future.wait([library.lockAsset(asset), library.lockAsset(asset)]);
      await library.unlockAsset((await db.assetById(asset.id))!);
      expect(await paths.absolute(asset.relativePath).readAsBytes(), original);
      keineReste();
    },
  );

  test(
    'Start nach Prozessabbruch mitten im Entsperren stellt Chiffretext wieder her',
    () async {
      await library.lockAsset(asset);
      final originalRel = asset.relativePath;
      final originalCipher = await paths.absolute(originalRel).readAsBytes();
      final miniCipher = await paths.absolute(mini).readAsBytes();
      // Abbruch nach dem ersten Dateitausch und vor dem zweiten: Das erste
      // Ziel ist bereits Klartext; beim zweiten fehlt vorübergehend das Ziel.
      await paths
          .absolute(originalRel)
          .rename('${paths.absolute(originalRel).path}.vaultalt');
      await paths.absolute(originalRel).writeAsBytes(original);
      await paths
          .absolute(mini)
          .rename('${paths.absolute(mini).path}.vaultalt');
      await paths.absolute('$mini.vaulttmp').writeAsBytes([4, 5, 6]);
      await paths
          .absolute('vault_dateiwechsel.json')
          .writeAsString(
            jsonEncode({
              'fassung': 1,
              'phase': 'uebernehmen',
              'sperren': false,
              'ids': [asset.id],
              'dateien': [originalRel, mini],
              'entfernen': [paths.vaultMetadataRelativePath(asset.id)],
            }),
            flush: true,
          );
      final neu = LibraryState()
        ..db = db
        ..paths = paths;
      await neu.erholeTresorDateiwechsel();
      expect((await db.assetById(asset.id))!.isLocked, isTrue);
      expect(await paths.absolute(originalRel).readAsBytes(), originalCipher);
      expect(await paths.absolute(mini).readAsBytes(), miniCipher);
      await library.unlockAsset((await db.assetById(asset.id))!);
      expect(await paths.absolute(originalRel).readAsBytes(), original);
      keineReste();
    },
  );

  test(
    'Start nach Prozessabbruch mitten im Sperren übernimmt vorbereitete Dateien',
    () async {
      final wechsel = TresorDateiwechsel(paths);
      const zweites = 'previews/zweites.jpg';
      paths.absolute(zweites).writeAsBytesSync([2]);
      final zielA = asset.relativePath;
      await wechsel.zwischen(zielA).writeAsBytes([8]);
      await wechsel.zwischen(zweites).writeAsBytes([9]);
      await wechsel.zwischen(zielA).rename(paths.absolute(zielA).path);
      await paths
          .absolute('vault_dateiwechsel.json')
          .writeAsString(
            jsonEncode({
              'fassung': 1,
              'phase': 'uebernehmen',
              'sperren': true,
              'ids': [asset.id],
              'dateien': [zielA, zweites],
              'entfernen': [],
            }),
            flush: true,
          );
      var abgeschlossen = false;
      await wechsel.erhole(
        abgeschlossen: (_, _) async => abgeschlossen,
        datenbank: (_, _) async {
          abgeschlossen = true;
        },
      );
      expect(abgeschlossen, isTrue);
      expect(await paths.absolute(zielA).readAsBytes(), [8]);
      expect(await paths.absolute(zweites).readAsBytes(), [9]);
      keineReste();
    },
  );
}
