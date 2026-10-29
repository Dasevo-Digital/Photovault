import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/import_plan.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/vault_crypto.dart';
import 'package:kern/services/aufnahmedatum.dart';
import 'package:photo_vault/state/library_state.dart';

class _ZielDb extends AppDatabase {
  _ZielDb(super.executor);
}

class _WechselImport extends ImportService {
  _WechselImport(super.db, super.paths);
  Future<void> Function()? nachKopie;
  @override
  Future<ImportResult> importFile(
    String path, {
    String? erwartetePruefsumme,
    ImportDateiangaben? erwarteteAngaben,
    Future<void> Function(String)? beiEintrag,
  }) async {
    final r = await super.importFile(
      path,
      erwartetePruefsumme: erwartetePruefsumme,
      erwarteteAngaben: erwarteteAngaben,
      beiEintrag: beiEintrag,
    );
    await nachKopie?.call();
    return r;
  }
}

void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths paths;
  late _WechselImport imp;
  late LibraryState lib;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_audit_import_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory('${temp.path}/bibliothek'));
    imp = _WechselImport(db, paths);
    lib = LibraryState()
      ..db = db
      ..paths = paths
      ..importService = imp;
    await db.fuehreAus(const AuswertenNachImportSetzen(false));
  });
  tearDown(() async {
    lib.dispose();
    await db.close();
    await temp.delete(recursive: true);
  });
  Future<File> quelle() async {
    final f = File('${temp.path}/probe.jpg');
    await f.writeAsBytes(
      img.encodeJpg(
        img.Image(width: 32, height: 24)..clear(img.ColorRgb8(30, 70, 120)),
      ),
    );
    await f.setLastModified(DateTime(2026, 6, 1, 10));
    return f;
  }

  test(
    'geänderter Dateizeitstempel wird trotz identischer Bytes abgewiesen',
    () async {
      await db.fuehreAus(
        RegelSpeichern(
          AutomationRulesCompanion.insert(
            id: 'r',
            name: 'Jahr',
            triggerType: 'dateRange',
            dateFrom: Value(DateTime(2026)),
            dateTo: Value(DateTime(2026, 12, 31)),
            autoFavorite: const Value(true),
          ),
        ),
      );
      final f = await quelle();
      final plan = await ImportPlanDienst(db, imp).erstelle([f.path]);
      await f.setLastModified(DateTime(2031, 6, 1));
      final lauf = await lib.importFiles([f.path], plan: plan).toList();
      expect(lauf.last.gescheitert, isTrue);
      expect(await db.select(db.assets).get(), isEmpty);
      expect(
        await paths.originalsDir
            .list(recursive: true)
            .where((f) => f is File)
            .toList(),
        isEmpty,
      );
    },
  );
  test(
    'später Regelwechsel verändert bereits bestätigte Importaktionen nicht',
    () async {
      await db.fuehreAus(
        RegelSpeichern(
          AutomationRulesCompanion.insert(
            id: 'r',
            name: 'Regel',
            triggerType: 'dateiendung',
            aiTagTerm: const Value('jpg'),
          ),
        ),
      );
      final f = await quelle();
      final dienst = ImportPlanDienst(db, imp);
      final plan = await dienst.erstelle([f.path]);
      imp.nachKopie = () async {
        await db.fuehreAus(
          RegelSpeichern(
            AutomationRulesCompanion.insert(
              id: 'r',
              name: 'Regel',
              triggerType: 'dateiendung',
              aiTagTerm: const Value('jpg'),
              autoFavorite: const Value(true),
            ),
          ),
        );
      };
      final lauf = await lib.importFiles([f.path], plan: plan).toList();
      final a = (await db.assetById(lauf.last.assetId!))!;
      expect(plan.eintraege.single.favorit, isFalse);
      expect(a.isFavorite, isFalse);
    },
  );
  test(
    'Wiederherstellung erhält manuelles Aufnahmedatum und Ablagepfad',
    () async {
      final f = await quelle();
      final id = (await imp.importFile(f.path)).assetId!;
      final datum = DateTime(2001, 2, 3, 4, 5);
      await lib.setzeAufnahmedatumVonHand([id], datum);
      await db.fuehreAus(FarbmarkeSetzen([id], 'rot'));
      await db.fuehreAus(OrtSetzen([id], 10, 20));
      await db.setLocationNames(
        id,
        country: 'Land',
        state: 'Region',
        city: 'Ort',
      );
      await db.fuehreAus(
        SchlagwortAnheften([id], 'synthetischer-tag', quelle: Tagquelle.ki),
      );
      final w = await VaultCrypto.createMasterKey(
        'synthetische-audit-passphrase',
      );
      await db.saveBackupKey(
        kdfSalt: w.kdfSalt,
        nonce: w.nonce,
        wrapped: w.wrapped,
      );
      final backup = BackupService(db, paths);
      final ziel = '${temp.path}/sicherung';
      await backup.performAutoBackup(ziel, w.masterKey).drain<void>();
      final wurzel = '$ziel/${BackupService.autoBackupFolderName}';
      final probe = (await backup.letzteProbe(wurzel))!;
      final zielDb = _ZielDb(NativeDatabase.memory());
      final zielPaths = await StoragePaths.forTesting(
        Directory('${temp.path}/ziel'),
      );
      try {
        await BackupService(zielDb, zielPaths)
            .restoreFromBackup(
              wurzel,
              ImportService(zielDb, zielPaths),
              passphrase: 'synthetische-audit-passphrase',
            )
            .drain<void>();
        final a = (await zielDb.select(zielDb.assets).get()).single;
        expect(probe.erfolgreich, isTrue);
        expect(a.fileCreatedAt.isAtSameMomentAs(datum), isTrue);
        expect(a.datumGeschaetzt, isFalse);
        expect(a.colorLabel, 'rot');
        expect(a.latitude, 10);
        expect(a.longitude, 20);
        expect(a.locationCity, 'Ort');
        expect(
          (await zielDb.kiTagNamesByAssetId())[a.id],
          contains('synthetischer-tag'),
        );
        expect(a.relativePath, contains('2001'));
        expect(await zielPaths.absolute(a.relativePath).exists(), isTrue);
      } finally {
        await zielDb.close();
      }
    },
  );
  test(
    'Probe erkennt abweichendes Datum und alter Schnappschuss stellt es auch ohne Manifest wieder her',
    () async {
      final f = await quelle();
      final id = (await imp.importFile(f.path)).assetId!;
      final datum = DateTime(2004, 3, 2, 12, 30);
      await AufnahmedatumDienst(
        db,
        paths,
      ).setze((await db.assetById(id))!, datum);
      final w = await VaultCrypto.createMasterKey('synthetische-passphrase');
      await db.saveBackupKey(
        kdfSalt: w.kdfSalt,
        nonce: w.nonce,
        wrapped: w.wrapped,
      );
      final backup = BackupService(db, paths);
      final ziel = '${temp.path}/alt';
      await backup.performAutoBackup(ziel, w.masterKey).drain<void>();
      final wurzel = '$ziel/${BackupService.autoBackupFolderName}';
      final meta = File('$wurzel/metadata.json'),
          klar = File('${temp.path}/manifest.json');
      await VaultCrypto.decryptFile(meta, klar, w.masterKey);
      final j = jsonDecode(await klar.readAsString()) as Map;
      (j['assets'] as List).single['fileCreatedAt'] = DateTime(
        1999,
      ).toUtc().toIso8601String();
      await klar.writeAsString(jsonEncode(j));
      await meta.delete();
      await VaultCrypto.encryptFile(klar, meta, w.masterKey);
      final probe = await backup.pruefeWiederherstellung(
        wurzel,
        schluessel: w.masterKey,
      );
      expect(probe.erfolgreich, isFalse);
      expect(probe.fehler, 'pv_probe_metadaten');
      await meta.delete();
      final zielDb = _ZielDb(NativeDatabase.memory());
      final zielPaths = await StoragePaths.forTesting(
        Directory('${temp.path}/alt-ziel'),
      );
      try {
        await BackupService(zielDb, zielPaths)
            .restoreFromBackup(
              wurzel,
              ImportService(zielDb, zielPaths),
              entschluesselungsschluessel: w.masterKey,
              streng: true,
            )
            .drain<void>();
        final a = (await zielDb.select(zielDb.assets).get()).single;
        expect(a.fileCreatedAt, datum);
        expect(await zielPaths.absolute(a.relativePath).exists(), isTrue);
      } finally {
        await zielDb.close();
      }
    },
  );
  test(
    'Restore erhält entfernte EXIF-Koordinaten und Ortsnamen ohne Stadt',
    () async {
      final bild = img.Image(width: 40, height: 30)
        ..clear(img.ColorRgb8(70, 90, 110));
      bild.exif.gpsIfd[1] = img.IfdValueAscii('N');
      bild.exif.gpsIfd[2] = img.IfdValueRational(10, 1)
        ..value.addAll(img.IfdValueRational(0, 1).value)
        ..value.addAll(img.IfdValueRational(0, 1).value);
      bild.exif.gpsIfd[3] = img.IfdValueAscii('E');
      bild.exif.gpsIfd[4] = img.IfdValueRational(20, 1)
        ..value.addAll(img.IfdValueRational(0, 1).value)
        ..value.addAll(img.IfdValueRational(0, 1).value);
      final mitGps = File('${temp.path}/mit-gps.jpg')
        ..writeAsBytesSync(img.encodeJpg(bild));
      final id = (await imp.importFile(mitGps.path)).assetId!;
      expect((await db.assetById(id))!.latitude, 10);
      await db.fuehreAus(OrtSetzen([id], null, null));
      final ohneStadt = (await imp.importFile((await quelle()).path)).assetId!;
      await db.setLocationNames(
        ohneStadt,
        country: 'Land',
        state: 'Region',
        city: null,
      );
      final w = await VaultCrypto.createMasterKey('synthetische-passphrase');
      await db.saveBackupKey(
        kdfSalt: w.kdfSalt,
        nonce: w.nonce,
        wrapped: w.wrapped,
      );
      final backup = BackupService(db, paths);
      final ziel = '${temp.path}/orte';
      await backup.performAutoBackup(ziel, w.masterKey).drain<void>();
      final wurzel = '$ziel/${BackupService.autoBackupFolderName}';
      expect((await backup.letzteProbe(wurzel))!.erfolgreich, isTrue);
      final zielDb = _ZielDb(NativeDatabase.memory());
      final zielPaths = await StoragePaths.forTesting(
        Directory('${temp.path}/orte-ziel'),
      );
      try {
        await BackupService(zielDb, zielPaths)
            .restoreFromBackup(
              wurzel,
              ImportService(zielDb, zielPaths),
              entschluesselungsschluessel: w.masterKey,
              streng: true,
            )
            .drain<void>();
        final fotos = await zielDb.select(zielDb.assets).get();
        final geloescht = fotos.singleWhere(
          (a) => a.originalFileName == 'mit-gps.jpg',
        );
        expect(geloescht.latitude, isNull);
        expect(geloescht.longitude, isNull);
        final ort = fotos.singleWhere((a) => a.originalFileName == 'probe.jpg');
        expect(ort.locationCountry, 'Land');
        expect(ort.locationState, 'Region');
        expect(ort.locationCity, isNull);
      } finally {
        await zielDb.close();
      }
    },
  );
  test(
    'Regeländerung vor Commit verwirft Original, Vorschau und DB-Zeile',
    () async {
      final f = await quelle();
      final dienst = ImportPlanDienst(db, imp);
      final plan = await dienst.erstelle([f.path]);
      final wechsler = _VorCommitImport(db, paths, () async {
        await db.fuehreAus(
          RegelSpeichern(
            AutomationRulesCompanion.insert(
              id: 'wechsel',
              name: 'Wechsel',
              triggerType: 'dateiendung',
              aiTagTerm: const Value('jpg'),
              autoFavorite: const Value(true),
            ),
          ),
        );
      });
      lib.importService = wechsler;
      final lauf = await lib.importFiles([f.path], plan: plan).toList();
      expect(lauf.last.gescheitert, isTrue);
      expect(await db.select(db.assets).get(), isEmpty);
      expect(
        await Directory(
          paths.originalsDir.parent.path,
        ).list(recursive: true).where((f) => f is File).toList(),
        isEmpty,
      );
    },
  );
  test(
    'Datumsverschiebung legt Original und Beilage bei DB-Fehler zurück',
    () async {
      final f = await quelle();
      final id = (await imp.importFile(f.path)).assetId!;
      final asset = (await db.assetById(id))!;
      final xmp = paths.absolute(paths.xmpSidecarPath(asset.relativePath));
      await xmp.writeAsString('synthetische-metadaten');
      await db.customStatement(
        "CREATE TRIGGER datum_abbruch BEFORE UPDATE ON assets BEGIN SELECT RAISE(ABORT, 'synthetisch'); END",
      );
      await expectLater(
        AufnahmedatumDienst(
          db,
          paths,
        ).setze(asset, DateTime(2001), streng: true),
        throwsA(anything),
      );
      expect(await paths.absolute(asset.relativePath).exists(), isTrue);
      expect(await xmp.exists(), isTrue);
      expect((await db.assetById(id))!.relativePath, asset.relativePath);
    },
  );
}

class _VorCommitImport extends ImportService {
  _VorCommitImport(super.db, super.paths, this.wechsle);
  final Future<void> Function() wechsle;
  @override
  Future<ThumbnailResult> generateThumbnailAndPreview(
    File file,
    String id,
    String ext, {
    Uint8List? alreadyReadBytes,
    String zusatz = '',
  }) async {
    final r = await super.generateThumbnailAndPreview(
      file,
      id,
      ext,
      alreadyReadBytes: alreadyReadBytes,
      zusatz: zusatz,
    );
    await wechsle();
    return r;
  }
}
