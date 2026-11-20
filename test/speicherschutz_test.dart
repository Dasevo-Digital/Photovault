import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_auswahl.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/original_referenzen.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/platform/folder_access.dart';
import 'package:photo_vault/services/platform/speicherlaufwerk.dart';
import 'package:photo_vault/services/speicherkarte.dart';
import 'package:photo_vault/services/speicherschutz.dart';

void main() {
  late Directory temp, originalort, backupparent;
  late AppDatabase db;
  late StoragePaths paths;
  late AssetData foto;
  late Speicherschutz dienst;
  late BackupAuswahl backup;
  var gleichesLaufwerk = false;
  PickedFolder originalziel() => PickedFolder(originalort.path, '');
  PickedFolder backupziel() => PickedFolder(
    p.join(backupparent.path, BackupService.backupFolderName),
    '',
  );
  Speicherschutz neu({Future<void> Function(File)? entfernen}) =>
      Speicherschutz(
        db,
        paths,
        nachweise: SpeicherkarteDienst(
          db,
          paths,
          File(p.join(temp.path, 'privat', 'nachweis.json')),
        ),
        laufwerk: (pfad) async => Speicherlaufwerk(
          gleichesLaufwerk
              ? 'gleich'
              : p.isWithin(originalort.path, pfad) ||
                    p.equals(originalort.path, pfad)
              ? 'originale'
              : p.isWithin(backupparent.path, pfad) ||
                    p.equals(backupparent.path, pfad)
              ? 'backup'
              : 'bibliothek',
          'Test',
          '/',
        ),
        entfernen: entfernen,
      );
  setUp(() async {
    temp = Directory(
      (await Directory.systemTemp.createTemp(
        'pv_speicherschutz_',
      )).resolveSymbolicLinksSync(),
    );
    originalort = await Directory(p.join(temp.path, 'originalort')).create();
    backupparent = await Directory(p.join(temp.path, 'sicherung')).create();
    paths = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'bibliothek')),
    );
    paths.referenzen = OriginalReferenzen(
      File(p.join(temp.path, 'privat', 'referenzen.json')),
    );
    db = AppDatabase(NativeDatabase.memory());
    final file = await File(p.join(temp.path, 'foto.jpg')).writeAsBytes(
      img.encodeJpg(
        img.Image(width: 12, height: 10)..clear(img.ColorRgb8(42, 80, 120)),
      ),
    );
    final r = await ImportService(db, paths).importFile(file.path);
    foto = (await db.assetById(r.assetId!))!;
    await for (final _ in BackupService(
      db,
      paths,
    ).performBackup(backupparent.path)) {}
    foto = (await db.assetById(foto.id))!;
    backup = await BackupAuswahl.oeffne(
      backupziel().path,
      schemaVersion: db.schemaVersion,
    );
    gleichesLaufwerk = false;
    dienst = neu();
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  test(
    'Freigabe erhält zwei echte Kopien, Katalogmetadaten und einen sofort lesbaren Originalverweis',
    () async {
      final vorher = await paths.absolute(foto.relativePath).readAsBytes();
      expect(await dienst.originalkopienAnlegen(originalziel()), 1);
      final plan = await dienst.pruefe(
        originalziel(),
        backupziel(),
        backup,
        unabhaengigkeitBestaetigt: true,
      );
      expect(plan.kandidaten, hasLength(1));
      expect(plan.bytes, vorher.length);
      await expectLater(
        dienst.freigeben(plan, bestaetigt: false),
        throwsA(isA<SpeicherschutzFehler>()),
      );
      expect(await paths.absolute(foto.relativePath).exists(), isTrue);
      final r = await dienst.freigeben(plan, bestaetigt: true);
      expect(r.dateien, 1);
      expect(r.bytes, vorher.length);
      final nachher = (await db.assetById(foto.id))!;
      expect(paths.istReferenziert(nachher.relativePath), isTrue);
      final alt = foto.toJson()..remove('relativePath');
      expect(nachher.toJson()..remove('relativePath'), alt);
      expect(
        await (await paths.referenzen!.lesen(
          nachher.relativePath,
          inhaltPruefen: true,
        )).readAsBytes(),
        vorher,
      );
      expect(await backup.pruefeOriginal(foto.checksum), isTrue);
      expect(await paths.absolute(foto.relativePath).exists(), isFalse);
      final wieder = OriginalReferenzen(paths.referenzen!.datei);
      await wieder.laden();
      expect(
        await (await wieder.lesen(
          nachher.relativePath,
          inhaltPruefen: true,
        )).readAsBytes(),
        vorher,
      );
    },
  );

  test(
    'Zwei Ordner auf demselben Dateisystem und fehlende Bestätigung genügen nicht',
    () async {
      final vorher = await paths.absolute(foto.relativePath).readAsBytes();
      await dienst.originalkopienAnlegen(originalziel());
      await expectLater(
        dienst.pruefe(
          originalziel(),
          backupziel(),
          backup,
          unabhaengigkeitBestaetigt: false,
        ),
        throwsA(isA<SpeicherschutzFehler>()),
      );
      gleichesLaufwerk = true;
      await expectLater(
        dienst.pruefe(
          originalziel(),
          backupziel(),
          backup,
          unabhaengigkeitBestaetigt: true,
        ),
        throwsA(isA<SpeicherschutzFehler>()),
      );
      expect(await paths.absolute(foto.relativePath).readAsBytes(), vorher);
      expect((await db.assetById(foto.id))!.relativePath, foto.relativePath);
    },
  );

  test('Geprüfte Sicherung muss zum angegebenen Ziel gehören', () async {
    await dienst.originalkopienAnlegen(originalziel());
    final anderes = await Directory(p.join(temp.path, 'anderesziel')).create();
    await expectLater(
      dienst.pruefe(
        originalziel(),
        PickedFolder(anderes.path, ''),
        backup,
        unabhaengigkeitBestaetigt: true,
      ),
      throwsA(isA<SpeicherschutzFehler>()),
    );
    expect(await paths.absolute(foto.relativePath).exists(), isTrue);
  });

  test(
    'Nachträglich beschädigte Rückfallkopie verhindert jede lokale Entfernung',
    () async {
      await dienst.originalkopienAnlegen(originalziel());
      final plan = await dienst.pruefe(
        originalziel(),
        backupziel(),
        backup,
        unabhaengigkeitBestaetigt: true,
      );
      final kopie = File(plan.kandidaten.single.originalkopie);
      await kopie.writeAsBytes([9, 9, 9]);
      await expectLater(
        dienst.freigeben(plan, bestaetigt: true),
        throwsA(isA<SpeicherschutzFehler>()),
      );
      expect(await paths.absolute(foto.relativePath).exists(), isTrue);
      expect((await db.assetById(foto.id))!.relativePath, foto.relativePath);
    },
  );

  test(
    'Fehlgeschlagene Entfernung setzt nur den Pfad zurück und erhält neue Metadaten',
    () async {
      await dienst.originalkopienAnlegen(originalziel());
      final plan = await dienst.pruefe(
        originalziel(),
        backupziel(),
        backup,
        unabhaengigkeitBestaetigt: true,
      );
      final mitFehler = neu(
        entfernen: (_) async {
          await (db.update(db.assets)..where((t) => t.id.equals(foto.id)))
              .write(const AssetsCompanion(description: Value('Nachtrag')));
          throw const FileSystemException('Testfehler');
        },
      );
      await expectLater(
        mitFehler.freigeben(plan, bestaetigt: true),
        throwsA(isA<FileSystemException>()),
      );
      final f = (await db.assetById(foto.id))!;
      expect(f.relativePath, foto.relativePath);
      expect(f.description, 'Nachtrag');
      expect(await paths.absolute(foto.relativePath).exists(), isTrue);
      expect(paths.referenzen!.dateien, isEmpty);
    },
  );

  test(
    'Gesperrte Fotos werden nicht als lesbare Originalkopie ausgelagert',
    () async {
      await (db.update(db.assets)..where((t) => t.id.equals(foto.id))).write(
        const AssetsCompanion(isLocked: Value(true)),
      );
      expect(await dienst.originalkopienAnlegen(originalziel()), 0);
      expect(await originalort.list().toList(), isEmpty);
      expect(await paths.absolute(foto.relativePath).exists(), isTrue);
    },
  );

  test('Ein vorhandenes fremdes Ziel wird nicht überschrieben', () async {
    final f = File(p.join(originalort.path, '${foto.checksum}.jpg'));
    await f.writeAsBytes([1, 2, 3]);
    await expectLater(
      dienst.originalkopienAnlegen(originalziel()),
      throwsA(isA<SpeicherschutzFehler>()),
    );
    expect(await f.readAsBytes(), [1, 2, 3]);
    expect(
      sha256
          .convert(await paths.absolute(foto.relativePath).readAsBytes())
          .toString(),
      foto.checksum,
    );
  });
}
