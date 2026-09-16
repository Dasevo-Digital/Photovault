import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// Integrationstest des gesperrten Ordners: Sperren/Entsperren verändert
/// tatsächlich den Dateiinhalt auf der Platte (AES-256, nicht nur ein
/// Sichtbarkeits-Flag), gesperrte Fotos verschwinden aus der Timeline, ein
/// PIN-Wechsel erfordert keine Neuverschlüsselung, und das Entfernen des
/// PIN-Schutzes gibt automatisch alles wieder frei.
///
/// [LibraryState] wird hier bewusst NICHT über [LibraryState.initialize]
/// aufgebaut (das würde die echte Bibliothek des Nutzers öffnen und
/// versuchen, ONNX-Modelle zu laden) – die Vault-Methoden brauchen nur `db`
/// und `paths`, beide werden direkt auf eine temporäre Test-Bibliothek
/// gesetzt.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late StoragePaths paths;
  late ImportService import;
  late LibraryState library;

  setUp(() async {
    tempRoot =
        Directory.systemTemp.createTempSync('photo_vault_locked_folder_test_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(
        Directory(p.join(tempRoot.path, 'library')));
    import = ImportService(db, paths);
    library = LibraryState()
      ..db = db
      ..paths = paths;
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<AssetData> importPhoto(String name, List<int> bytes) async {
    final incoming = Directory(p.join(tempRoot.path, 'incoming'))
      ..createSync(recursive: true);
    final file = File(p.join(incoming.path, name))..writeAsBytesSync(bytes);
    final result = await import.importFile(file.path);
    expect(result.outcome, ImportOutcome.imported);
    return (await db.assetById(result.assetId!))!;
  }

  test(
      'Sperren verschlüsselt die Originaldatei auf der Platte, Entsperren stellt sie exakt wieder her',
      () async {
    final originalBytes = List<int>.generate(
        500000, (i) => i % 256); // > 2 Verschlüsselungs-Chunks
    final asset = await importPhoto('geheim.jpg', originalBytes);
    final originalFile = paths.absolute(asset.relativePath);
    expect(await originalFile.readAsBytes(), equals(originalBytes));

    await library.setupVaultPin('1234');
    expect(library.vaultUnlockedThisSession, isTrue);
    expect(await db.hasPinSet(), isTrue);

    await library.lockAsset(asset);

    final lockedAsset = (await db.assetById(asset.id))!;
    expect(lockedAsset.isLocked, isTrue);
    expect(await originalFile.readAsBytes(), isNot(equals(originalBytes)));
    expect((await db.watchTimeline().first).map((a) => a.id),
        isNot(contains(asset.id)));
    expect((await db.watchLockedAssets().first).map((a) => a.id),
        contains(asset.id));

    // Anzeige-Entschlüsselung liefert die Originaldaten, ohne die Datei in
    // der Bibliothek selbst anzurühren.
    final viewingCopy = await library.decryptForViewing(asset.relativePath);
    expect(await viewingCopy.readAsBytes(), equals(originalBytes));
    expect(await originalFile.readAsBytes(), isNot(equals(originalBytes)));

    await library.unlockAsset(lockedAsset);

    final unlockedAsset = (await db.assetById(asset.id))!;
    expect(unlockedAsset.isLocked, isFalse);
    expect(await originalFile.readAsBytes(), equals(originalBytes));
    expect(
        (await db.watchTimeline().first).map((a) => a.id), contains(asset.id));
  });

  test(
      'Sperren verschlüsselt auch Video-Zuschnitt und KI-Objektmasken, Entsperren stellt sie '
      'exakt wieder her (Audit-Fund: fehlten hier ursprünglich)', () async {
    final originalBytes = List<int>.generate(1000, (i) => i % 256);
    final asset = await importPhoto('video.jpg',
        originalBytes); // Typ egal, nur Datei-Handling wird geprüft

    final trimBytes = List<int>.generate(2000, (i) => (i * 3) % 256);
    final trimmedRelPath = 'trimmed/${asset.id}.mp4';
    paths.absolute(trimmedRelPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(trimBytes);
    await db.saveVideoTrim(asset.id,
        startSeconds: 0, endSeconds: 1, trimmedRelativePath: trimmedRelPath);

    final maskBytes = List<int>.generate(1500, (i) => (i * 7) % 256);
    const maskRelPath = 'masks/mask1.png';
    paths.absolute(maskRelPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(maskBytes);
    await db.createDevelopMask(DevelopMasksCompanion.insert(
      assetId: asset.id,
      maskRelativePath: maskRelPath,
      label: 'Maske 1',
      createdAt: DateTime(2024, 1, 1),
    ));

    await library.setupVaultPin('1234');
    final lockedAsset = (await db.assetById(asset.id))!;
    await library.lockAsset(lockedAsset);

    final trimmedFile = paths.absolute(trimmedRelPath);
    final maskFile = paths.absolute(maskRelPath);
    expect(await trimmedFile.readAsBytes(), isNot(equals(trimBytes)),
        reason: 'Video-Zuschnitt muss beim Sperren verschlüsselt werden.');
    expect(await maskFile.readAsBytes(), isNot(equals(maskBytes)),
        reason: 'KI-Objektmaske muss beim Sperren verschlüsselt werden.');

    final relockedAsset = (await db.assetById(asset.id))!;
    await library.unlockAsset(relockedAsset);

    expect(await trimmedFile.readAsBytes(), equals(trimBytes));
    expect(await maskFile.readAsBytes(), equals(maskBytes));
  });

  test('Falscher PIN entsperrt den Vault nicht', () async {
    await library.setupVaultPin('1234');
    library.lockVaultSession();
    expect(library.vaultUnlockedThisSession, isFalse);

    await expectLater(library.unlockVaultWithPin('0000'), throwsA(anything));
    expect(library.vaultUnlockedThisSession, isFalse);

    await library.unlockVaultWithPin('1234');
    expect(library.vaultUnlockedThisSession, isTrue);
  });

  test(
      'private Metadaten verschwinden aus SQLite und kehren verlustfrei zurück',
      () async {
    final asset = await importPhoto('Geburtstag in Berlin.jpg', [1, 2, 3]);
    await db.setDescriptionBulk([asset.id], 'Überraschung für Anna');
    await db.setLocation(asset.id, 52.52, 13.405);
    await db.tagAsset(asset.id, 'Familie');
    await db.createAlbum(AlbumsCompanion.insert(
        id: 'album-privat', name: 'Private Feier', createdAt: DateTime(2024)));
    await db.addAssetsToAlbum('album-privat', [asset.id]);
    final vorDemSperren = (await db.assetById(asset.id))!;

    await library.setupVaultPin('1234');
    await library.lockAsset(vorDemSperren);

    final gesperrt = (await db.assetById(asset.id))!;
    expect(gesperrt.originalFileName, 'Private Aufnahme');
    expect(gesperrt.description, isNull);
    expect(gesperrt.latitude, isNull);
    expect(await db.tagsForAsset(asset.id), isEmpty);
    expect((await db.privateRelationsForAsset(asset.id))['albums'], isEmpty);
    final metadata = paths.absolute(paths.vaultMetadataRelativePath(asset.id));
    final chiffriert = await metadata.readAsBytes();
    expect(String.fromCharCodes(chiffriert), isNot(contains('Geburtstag')));
    expect(String.fromCharCodes(chiffriert), isNot(contains('Anna')));

    await library.unlockAsset(gesperrt);

    final wiederhergestellt = (await db.assetById(asset.id))!;
    expect(wiederhergestellt.originalFileName, 'Geburtstag in Berlin.jpg');
    expect(wiederhergestellt.description, 'Überraschung für Anna');
    expect(wiederhergestellt.latitude, 52.52);
    expect((await db.tagsForAsset(asset.id)).single.name, 'Familie');
    expect((await db.privateRelationsForAsset(asset.id))['albums'],
        contains('album-privat'));
    expect(await metadata.exists(), isFalse);
  });

  test(
      'PIN-Wechsel erfordert keine Neuverschlüsselung – Dateien bleiben mit dem alten Master-Key lesbar',
      () async {
    final originalBytes = [1, 2, 3, 4, 5];
    final asset = await importPhoto('foto.jpg', originalBytes);

    await library.setupVaultPin('1234');
    await library.lockAsset(asset);
    await library.changeVaultPin('5678');

    library.lockVaultSession();
    await expectLater(library.unlockVaultWithPin('1234'), throwsA(anything));
    await library.unlockVaultWithPin('5678');

    final lockedAsset = (await db.assetById(asset.id))!;
    await library.unlockAsset(lockedAsset);
    expect(await paths.absolute(asset.relativePath).readAsBytes(),
        equals(originalBytes));
  });

  test(
      'removeVaultPin entschlüsselt alle gesperrten Fotos automatisch und entfernt den PIN',
      () async {
    final originalBytes = [9, 9, 9, 9];
    final asset = await importPhoto('foto2.jpg', originalBytes);

    await library.setupVaultPin('1234');
    await library.lockAsset(asset);

    await library.removeVaultPin();

    expect(await db.hasPinSet(), isFalse);
    expect(library.vaultUnlockedThisSession, isFalse);
    final restoredAsset = (await db.assetById(asset.id))!;
    expect(restoredAsset.isLocked, isFalse);
    expect(await paths.absolute(asset.relativePath).readAsBytes(),
        equals(originalBytes));
  });

  test(
      'ein bereits vor dem Sperren gescanntes Gesichts-Crop wird mitverschlüsselt und -entschlüsselt',
      () async {
    final asset = await importPhoto('mit_gesicht.jpg', [1, 2, 3]);
    final faceCropBytes = [42, 42, 42, 42];
    final cropRelativePath = paths.faceRelativePath('face-1');
    final faceCropFile = paths.absolute(cropRelativePath);
    await faceCropFile.create(recursive: true);
    await faceCropFile.writeAsBytes(faceCropBytes);
    await db.insertFace(FacesCompanion.insert(
      id: 'face-1',
      assetId: asset.id,
      boxX: 0,
      boxY: 0,
      boxW: 0.5,
      boxH: 0.5,
      cropRelativePath: Value(cropRelativePath),
    ));

    await library.setupVaultPin('1234');
    await library.lockAsset(asset);
    expect(await faceCropFile.readAsBytes(), isNot(equals(faceCropBytes)));

    final lockedAsset = (await db.assetById(asset.id))!;
    await library.unlockAsset(lockedAsset);
    expect(await faceCropFile.readAsBytes(), equals(faceCropBytes));
  });

  test(
      'gesperrte, gelöschte Fotos landen im eigenen Papierkorb statt im normalen',
      () async {
    final asset = await importPhoto('geloescht.jpg', [1, 2, 3]);
    await library.setupVaultPin('1234');
    await library.lockAsset(asset);

    await db.moveToTrash([asset.id]);

    expect((await db.watchTrash().first).map((a) => a.id),
        isNot(contains(asset.id)));
    expect((await db.watchLockedTrash().first).map((a) => a.id),
        contains(asset.id));
    expect((await db.watchLockedAssets().first).map((a) => a.id),
        isNot(contains(asset.id)));

    // Wiederherstellen bringt es zurück in den gesperrten Ordner, nicht in
    // die normale Timeline.
    await db.restoreFromTrash([asset.id]);
    final restored = (await db.assetById(asset.id))!;
    expect(restored.isLocked, isTrue);
    expect(restored.isTrashed, isFalse);
    expect((await db.watchLockedAssets().first).map((a) => a.id),
        contains(asset.id));
    expect((await db.watchTimeline().first).map((a) => a.id),
        isNot(contains(asset.id)));
  });

  test(
      'endgültiges Löschen aus dem gesperrten Papierkorb entfernt Originaldatei, Thumbnail und DB-Zeile',
      () async {
    final asset = await importPhoto('endgueltig.jpg', [1, 2, 3]);
    await library.setupVaultPin('1234');
    await library.lockAsset(asset);
    await db.moveToTrash([asset.id]);

    final lockedAsset = (await db.assetById(asset.id))!;
    final originalFile = paths.absolute(lockedAsset.relativePath);
    expect(await originalFile.exists(), isTrue);

    // Entspricht LockedFolderScreen._permanentlyDelete.
    await paths.deletePermanently(lockedAsset.relativePath);
    if (lockedAsset.thumbnailRelativePath != null) {
      await paths.deletePermanently(lockedAsset.thumbnailRelativePath!);
    }
    await db.deleteAssetRows([lockedAsset.id]);

    expect(await originalFile.exists(), isFalse);
    expect(await db.assetById(asset.id), isNull);
    expect((await db.watchLockedTrash().first).map((a) => a.id),
        isNot(contains(asset.id)));
  });
}
