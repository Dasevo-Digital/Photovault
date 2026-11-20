import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/bildzuschnitt.dart';
import 'package:kern/services/entwicklungsvariante.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/varianten_sicherung.dart';
import 'package:kern/services/vault_crypto.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/entwicklungsvarianten_dienst.dart';
import 'package:photo_vault/services/integrity_check_service.dart';
import 'package:photo_vault/state/library_state.dart';

void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths paths;
  late AssetData a;
  late Uint8List jpeg;
  late EntwicklungsvariantenDienst dienst;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_varianten_test_');
    paths = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'library')),
    );
    db = AppDatabase(NativeDatabase.memory());
    jpeg = Uint8List.fromList(
      img.encodeJpg(
        img.Image(width: 40, height: 30)..clear(img.ColorRgb8(120, 40, 60)),
      ),
    );
    final f = await File(p.join(temp.path, 'foto.jpg')).writeAsBytes(jpeg);
    final r = await ImportService(db, paths).importFile(f.path);
    a = (await db.assetById(r.assetId!))!;
    dienst = EntwicklungsvariantenDienst(db, paths);
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });
  DevelopSettingsData werte(double ev, {String? crop}) => DevelopSettingsData(
    assetId: a.id,
    cropJson: crop,
    exposure: ev,
    temperature: null,
    tint: null,
    contrast: 0,
    shadows: 0,
    highlights: 0,
    sharpness: 0,
    noiseReduction: 0,
    lensCorrectionEnabled: true,
    clarity: 0,
    vignette: 0,
    lutPath: null,
    lutStrength: 1,
    toneCurveJson: null,
    colorMixerJson: null,
    updatedAt: DateTime.now(),
  );

  test(
    'zwei eigenständige Varianten ändern weder Original noch aktive Entwicklung',
    () async {
      final vor = await paths.absolute(a.relativePath).readAsBytes();
      await dienst.speichern(
        asset: a,
        name: 'Farbe',
        einstellungen: werte(1),
        masken: [],
        jpeg: jpeg,
      );
      await dienst.speichern(
        asset: a,
        name: 'Druck',
        einstellungen: werte(-1, crop: Bildzuschnitt(breite: .5).json),
        masken: [],
        jpeg: jpeg,
      );
      final v = await db.variantenFuer(a.id);
      expect(v.length, 2);
      expect(await db.developSettingsForAsset(a.id), isNull);
      expect(await paths.absolute(a.relativePath).readAsBytes(), vor);
      expect(
        Entwicklungsstand.decode(
          v.firstWhere((v) => v.name == 'Druck').stateJson,
        ).einstellungen.cropJson,
        isNotNull,
      );
      expect(await db.assetsWithDevelopSettings(), isEmpty);
    },
  );

  test(
    'Aktivierung und Befehlsserialisierung übernehmen den vollständigen Stand',
    () async {
      await dienst.speichern(
        asset: a,
        name: 'Druck',
        einstellungen: werte(1, crop: Bildzuschnitt(breite: .5).json),
        masken: [],
        jpeg: jpeg,
      );
      final v = (await db.variantenFuer(a.id)).single;
      final b = Befehl.ausJson(
        EntwicklungsvarianteAktivieren(a.id, v.id).alsJson(),
      );
      await db.fuehreAus(b);
      expect((await db.developSettingsForAsset(a.id))!.exposure, 1);
      expect(
        (await db.assetById(a.id))!.developedRelativePath,
        v.previewRelativePath,
      );
      expect(await db.varianteVerwendetDatei(v.previewRelativePath), isTrue);
      await dienst.umbenennen(v, 'Papier');
      expect((await db.variantenFuer(a.id)).single.name, 'Papier');
      await dienst.entfernen(v);
      expect(await db.variantenFuer(a.id), isEmpty);
      expect(await paths.absolute(v.previewRelativePath).exists(), isTrue);
      expect(await paths.absolute(a.relativePath).exists(), isTrue);
    },
  );

  test(
    'Masken werden eingefroren und bleiben bei späterem Ändern unabhängig',
    () async {
      final png = Uint8List.fromList(
        img.encodePng(
          img.Image(width: 40, height: 30)..clear(img.ColorRgb8(255, 255, 255)),
        ),
      );
      await paths.absolute('masks/maske.png').writeAsBytes(png);
      await db.createDevelopMask(
        DevelopMasksCompanion.insert(
          assetId: a.id,
          maskRelativePath: 'masks/maske.png',
          label: 'Oben',
          createdAt: DateTime.now(),
        ),
      );
      final masken = await db.masksForAsset(a.id);
      await dienst.speichern(
        asset: a,
        name: 'Maske',
        einstellungen: werte(.5),
        masken: masken,
        jpeg: jpeg,
      );
      final v = (await db.variantenFuer(a.id)).single;
      final s = Entwicklungsstand.decode(v.stateJson);
      expect(s.masken.single.maskRelativePath, isNot('masks/maske.png'));
      await paths.absolute('masks/maske.png').writeAsBytes([1, 2, 3]);
      await dienst.aktivieren(v);
      final aktiv = (await db.masksForAsset(a.id)).single;
      expect(await paths.absolute(aktiv.maskRelativePath).readAsBytes(), png);
      expect(
        sha256
            .convert(await paths.absolute(aktiv.maskRelativePath).readAsBytes())
            .toString(),
        s.dateien[aktiv.maskRelativePath],
      );
    },
  );

  test(
    'gesperrte Aufnahme behält keine lesbaren Variantennamen und erhält sie zurück',
    () async {
      await dienst.speichern(
        asset: a,
        name: 'Privater Stand',
        einstellungen: werte(1),
        masken: [],
        jpeg: jpeg,
      );
      final privat = await db.privateRelationsForAsset(a.id);
      await db.hidePrivateMetadata(a.id);
      expect(await db.variantenFuer(a.id), isEmpty);
      expect(
        (await db.select(db.developVariantFiles).get()).every(
          (f) => f.sha256.isEmpty,
        ),
        isTrue,
      );
      await db.restorePrivateMetadata(
        a.id,
        const AssetsCompanion(),
        tags: [],
        albumIds: [],
        entwicklungsvarianten: privat['entwicklungsvarianten']!,
      );
      expect((await db.variantenFuer(a.id)).single.name, 'Privater Stand');
    },
  );

  test(
    'falsche Originalbindung und beschädigte Vorschau werden abgewiesen',
    () async {
      await dienst.speichern(
        asset: a,
        name: 'Stand',
        einstellungen: werte(1),
        masken: [],
        jpeg: jpeg,
      );
      final v = (await db.variantenFuer(a.id)).single;
      await paths.absolute(v.previewRelativePath).writeAsBytes([1, 2, 3]);
      await expectLater(dienst.aktivieren(v), throwsFormatException);
      expect(await db.developSettingsForAsset(a.id), isNull);
      await db.customStatement('UPDATE assets SET checksum=? WHERE id=?', [
        'b' * 64,
        a.id,
      ]);
      await expectLater(db.varianteAktivieren(a.id, v.id), throwsStateError);
      expect(await db.developSettingsForAsset(a.id), isNull);
    },
  );

  test(
    'Zuschnitt und Vierteldrehung rendern echte Pixelmaße ohne Originaländerung',
    () async {
      final z = Bildzuschnitt(links: .25, breite: .5, hoehe: .5, drehungen: 1);
      final aus = await schneideEntwicklung(jpeg, z);
      final bild = img.decodeJpg(aus)!;
      expect((bild.width, bild.height), (15, 20));
      expect(img.decodeJpg(jpeg)!.width, 40);
      expect(() => Bildzuschnitt(links: .8, breite: .5), throwsFormatException);
      expect(() => Bildzuschnitt(breite: double.nan), throwsFormatException);
    },
  );

  for (final verschluesselt in [false, true]) {
    test(
      'vollständige Wiederherstellung erhält Varianten und Dateien, verschlüsselt=$verschluesselt',
      () async {
        await dienst.speichern(
          asset: a,
          name: 'Druck',
          einstellungen: werte(1, crop: Bildzuschnitt(breite: .5).json),
          masken: [],
          jpeg: jpeg,
        );
        final key = verschluesselt
            ? SecretKey(List<int>.generate(32, (i) => i))
            : null;
        if (key != null) {
          final verpackt = await VaultCrypto.wrapMasterKey(
            key,
            'sicherungs-passwort',
          );
          await db.saveBackupKey(
            kdfSalt: verpackt.kdfSalt,
            nonce: verpackt.nonce,
            wrapped: verpackt.wrapped,
          );
        }
        final ziel = Directory(p.join(temp.path, 'sicherung'));
        final backup = BackupService(db, paths);
        final lauf = await backup
            .performBackup(ziel.path, encryptionKey: key)
            .toList();
        expect(
          lauf.last.wiederherstellungsprobe?.erfolgreich,
          isTrue,
          reason: lauf.last.wiederherstellungsprobe?.alsJson().toString(),
        );
        final neuDb = AppDatabase(NativeDatabase.memory());
        addTearDown(neuDb.close);
        final neuPaths = await StoragePaths.forTesting(
          Directory(p.join(temp.path, 'neu')),
        );
        final restore = await BackupService(neuDb, neuPaths)
            .restoreFromBackup(
              p.join(ziel.path, 'PhotoVault-Backup'),
              ImportService(neuDb, neuPaths),
              entschluesselungsschluessel: key,
              streng: true,
            )
            .toList();
        expect(restore.last.wiederherstellung?.erfolgreich, isTrue);
        final asset = (await neuDb.allAssetsForIntegrityCheck()).single;
        final v = (await neuDb.variantenFuer(asset.id)).single;
        expect(v.name, 'Druck');
        expect(
          await neuPaths.absolute(v.previewRelativePath).readAsBytes(),
          jpeg,
        );
        await EntwicklungsvariantenDienst(neuDb, neuPaths).aktivieren(v);
        expect(
          (await neuDb.developSettingsForAsset(asset.id))!.cropJson,
          isNotNull,
        );
      },
    );
  }

  test(
    'fehlendes Variantenobjekt kann keine erfolgreiche Wiederherstellung ergeben',
    () async {
      await dienst.speichern(
        asset: a,
        name: 'Druck',
        einstellungen: werte(1),
        masken: [],
        jpeg: jpeg,
      );
      final ziel = Directory(p.join(temp.path, 'sicherung'));
      final backup = BackupService(db, paths);
      await backup.performBackup(ziel.path).drain<void>();
      final objekte = Directory(
        p.join(ziel.path, 'PhotoVault-Backup', 'varianten'),
      );
      await (await objekte.list().toList()).single.delete();
      final neuDb = AppDatabase(NativeDatabase.memory());
      addTearDown(neuDb.close);
      final neuPaths = await StoragePaths.forTesting(
        Directory(p.join(temp.path, 'neu')),
      );
      final lauf = await BackupService(neuDb, neuPaths)
          .restoreFromBackup(
            p.join(ziel.path, 'PhotoVault-Backup'),
            ImportService(neuDb, neuPaths),
          )
          .toList();
      expect(lauf.last.wiederherstellung?.erfolgreich, isFalse);
    },
  );
  test(
    'ältere verschlüsselte Generation bewahrt Masken, LUT und damalige Varianten',
    () async {
      final png = img.encodePng(
        img.Image(width: 16, height: 12)..clear(img.ColorRgb8(255, 255, 255)),
      );
      await paths.absolute('masks/test.png').writeAsBytes(png);
      await paths
          .absolute('luts/test.cube')
          .writeAsString('LUT_1D_SIZE 2\n0 0 0\n1 1 1\n');
      await db.createDevelopMask(
        DevelopMasksCompanion.insert(
          assetId: a.id,
          maskRelativePath: 'masks/test.png',
          label: 'Maske',
          createdAt: DateTime.now(),
        ),
      );
      await dienst.speichern(
        asset: a,
        name: 'Damals',
        einstellungen: werte(
          1,
        ).copyWith(lutPath: const Value('luts/test.cube')),
        masken: await db.masksForAsset(a.id),
        jpeg: jpeg,
      );
      final key = await VaultCrypto.createMasterKey('synthetische-sicherung');
      await db.saveBackupKey(
        kdfSalt: key.kdfSalt,
        nonce: key.nonce,
        wrapped: key.wrapped,
      );
      final ziel = '${temp.path}/auto';
      final backup = BackupService(db, paths);
      await backup.performAutoBackup(ziel, key.masterKey).drain<void>();
      final root = '$ziel/${BackupService.autoBackupFolderName}';
      final alt = (await backup.autoBackupGenerations(root)).single;
      await dienst.speichern(
        asset: a,
        name: 'Später',
        einstellungen: werte(-1),
        masken: [],
        jpeg: jpeg,
      );
      await backup.performAutoBackup(ziel, key.masterKey).drain<void>();
      final neuDb = AppDatabase(NativeDatabase.memory());
      addTearDown(neuDb.close);
      final neuPaths = await StoragePaths.forTesting(
        Directory('${temp.path}/historisch'),
      );
      final r = await BackupService(neuDb, neuPaths)
          .restoreFromBackup(
            root,
            ImportService(neuDb, neuPaths),
            entschluesselungsschluessel: key.masterKey,
            generationSnapshotPath: alt.snapshotPath,
            streng: true,
          )
          .toList();
      expect(r.last.wiederherstellung?.erfolgreich, isTrue);
      final foto = (await neuDb.allAssetsForIntegrityCheck()).single;
      final v = (await neuDb.variantenFuer(foto.id)).single;
      expect(v.name, 'Damals');
      await EntwicklungsvariantenDienst(neuDb, neuPaths).aktivieren(v);
      final stand = Entwicklungsstand.decode(v.stateJson);
      expect(
        await neuPaths
            .absolute(stand.masken.single.maskRelativePath)
            .readAsBytes(),
        png,
      );
      expect(
        await neuPaths.absolute(stand.einstellungen.lutPath!).readAsString(),
        contains('LUT_1D_SIZE'),
      );
    },
  );
  test(
    'Zusatzbudget, beschädigte Kopie und Pfadausbruch werden geprüft',
    () async {
      await paths
          .absolute('luts/test.cube')
          .writeAsString('LUT_1D_SIZE 2\n0 0 0\n1 1 1\n');
      await dienst.speichern(
        asset: a,
        name: 'Druck',
        einstellungen: werte(
          1,
        ).copyWith(lutPath: const Value('luts/test.cube')),
        masken: [],
        jpeg: jpeg,
      );
      final ziel = await Directory('${temp.path}/objekte').create();
      var s = await VariantenSicherung.ohneSchnappschuss(
        db,
        paths,
        ziel,
        maxBytes: 1,
      );
      expect(s.offen, greaterThan(0));
      expect(s.geschriebenBytes, greaterThan(0));
      s = await VariantenSicherung.ohneSchnappschuss(
        db,
        paths,
        ziel,
        maxBytes: 1,
      );
      expect(s.offen, 0);
      final datei = (await Directory(
        '${ziel.path}/varianten',
      ).list().toList()).whereType<File>().first;
      await datei.writeAsBytes([0]);
      s = await VariantenSicherung.ohneSchnappschuss(db, paths, ziel);
      expect(s.geschriebenBytes, greaterThan(0));
      final ausserhalb = await Directory('${temp.path}/ausserhalb').create();
      await Directory('${ziel.path}/varianten').rename('${ziel.path}/vorher');
      await Link('${ziel.path}/varianten').create(ausserhalb.path);
      await expectLater(
        VariantenSicherung.ohneSchnappschuss(db, paths, ziel),
        throwsFormatException,
      );
      expect(await ausserhalb.list().length, 0);
    },
  );
  test(
    'PIN-Rundlauf und Integritätsbereinigung behalten auch inaktive Varianten',
    () async {
      await dienst.speichern(
        asset: a,
        name: 'Privat',
        einstellungen: werte(1),
        masken: [],
        jpeg: jpeg,
      );
      final v = (await db.variantenFuer(a.id)).single;
      final f = paths.absolute(v.previewRelativePath);
      await f.setLastModified(DateTime(2020));
      Future<IntegrityCheckReport> pruefen() async => runIntegrityCheck(
        IntegrityCheckParams(
          libraryRootPath: paths.root.path,
          assets: [],
          faceCrops: [],
          masks: [],
          verifyChecksums: true,
          varianten: [
            for (final x in await db.select(db.developVariantFiles).get())
              VariantenDateiSnapshot(x.assetId, x.relativePath, x.sha256),
          ],
        ),
      );
      expect(
        (await pruefen()).orphanedFiles.where(
          (x) => x.relativePath == v.previewRelativePath,
        ),
        isEmpty,
      );
      final lib = LibraryState()
        ..db = db
        ..paths = paths
        ..importService = ImportService(db, paths)
        ..backupService = BackupService(db, paths)
        ..klartextOrdnerFuerTests = Directory('${temp.path}/klartext');
      await lib.setupVaultPin('1234');
      await lib.lockAsset(a);
      expect(await VaultCrypto.hasValidEncryptedHeader(f), isTrue);
      expect(await db.variantenFuer(a.id), isEmpty);
      expect(
        (await pruefen()).orphanedFiles.where(
          (x) => x.relativePath == v.previewRelativePath,
        ),
        isEmpty,
      );
      await lib.unlockAsset((await db.assetById(a.id))!);
      expect(await f.readAsBytes(), jpeg);
      await dienst.aktivieren((await db.variantenFuer(a.id)).single);
      await f.delete();
      expect(
        (await pruefen()).missingFiles.single.kind,
        MissingFileKind.variante,
      );
    },
  );
}
