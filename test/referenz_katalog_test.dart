import 'dart:io';
import 'package:kern/services/backup_service.dart';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/aufnahmedatum.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/original_referenzen.dart';
import 'package:kern/services/referenz_katalog.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp, quelle;
  late StoragePaths paths;
  late OriginalReferenzen refs;
  late AppDatabase db;
  late ReferenzKatalog katalog;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_referenz_test_');
    quelle = await Directory(p.join(temp.path, 'quelle')).create();
    paths = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'bibliothek')),
    );
    refs = OriginalReferenzen(File(p.join(temp.path, 'lokal.json')));
    paths.referenzen = refs;
    db = AppDatabase(NativeDatabase.memory());
    katalog = ReferenzKatalog(db, paths, ImportService(db, paths));
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });
  Future<File> foto(String name, {int farbe = 42}) async {
    final image = img.Image(width: 12, height: 10)
      ..clear(img.ColorRgb8(farbe, 20, 30));
    final f = File(p.join(quelle.path, name));
    await f.parent.create(recursive: true);
    return f.writeAsBytes(img.encodeJpg(image));
  }

  test('Scan katalogisiert ohne Originalkopie und überlebt Neustart', () async {
    final source = await foto('urlaub/bild.jpg');
    final bytes = await source.readAsBytes();
    final s = await katalog.scanne(quelle).last;
    expect(s.neu, 1);
    expect(s.fehler, 0);
    final a = (await db.allAssetsForIntegrityCheck()).single;
    expect(a.relativePath, startsWith('referenzen/'));
    expect(await paths.absolute(a.relativePath).exists(), isFalse);
    expect(await paths.originalsDir.list(recursive: true).toList(), isEmpty);
    expect(await (await paths.bereit(a.relativePath)).readAsBytes(), bytes);
    final neu = OriginalReferenzen(refs.datei);
    await neu.laden();
    expect(
      await (await neu.lesen(
        a.relativePath,
        inhaltPruefen: true,
      )).readAsBytes(),
      bytes,
    );
    expect(await source.readAsBytes(), bytes);
  });

  test(
    'erneuter Scan ist idempotent; Ausschlüsse und Links werden nicht gelesen',
    () async {
      await foto('bild.jpg');
      await foto('privat/anders.jpg', farbe: 90);
      final fremd = await Directory(p.join(temp.path, 'fremd')).create();
      await File(p.join(fremd.path, 'draußen.jpg')).writeAsBytes([1, 2, 3]);
      await Link(p.join(quelle.path, 'link')).create(fremd.path);
      await katalog.scanne(quelle, ausschliessen: ['privat/**']).drain<void>();
      final s = await katalog.scanne(quelle, ausschliessen: ['privat/**']).last;
      expect(s.doppelt, 1);
      expect(s.neu, 0);
      expect((await db.allAssetsForIntegrityCheck()).length, 1);
      expect(refs.dateien.length, 1);
    },
  );

  test(
    'Abbruch und frühe Grenze bewahren Quellen und gültige Einträge',
    () async {
      await foto('a.jpg');
      await foto('b.jpg', farbe: 80);
      await expectLater(
        katalog.scanne(quelle, abgebrochen: () => true).drain<void>(),
        throwsA(isA<ReferenzAbbruch>()),
      );
      expect(await db.allAssetsForIntegrityCheck(), isEmpty);
      await expectLater(
        katalog.scanne(quelle, hoechstens: 1).drain<void>(),
        throwsStateError,
      );
      expect(await quelle.list().length, 2);
    },
  );

  test(
    'fremde Originale bleiben bei Papierkorb, Löschen und Datumskorrektur unberührt',
    () async {
      final source = await foto('bild.jpg');
      final bytes = await source.readAsBytes();
      await katalog.scanne(quelle).drain<void>();
      final a = (await db.allAssetsForIntegrityCheck()).single;
      expect(await paths.moveToPhysicalTrash(a.relativePath), a.relativePath);
      await paths.deletePermanently(a.relativePath);
      expect(refs.dateien.containsKey(a.relativePath), isFalse);
      await AufnahmedatumDienst(db, paths).setze(a, DateTime(2001, 2, 3));
      expect((await db.assetById(a.id))!.relativePath, a.relativePath);
      expect(await source.readAsBytes(), bytes);
    },
  );

  test(
    'geändertes Original wird abgewiesen statt still neu interpretiert',
    () async {
      final source = await foto('bild.jpg');
      await katalog.scanne(quelle).drain<void>();
      final a = (await db.allAssetsForIntegrityCheck()).single;
      await source.writeAsBytes([1, 2, 3]);
      await expectLater(paths.bereit(a.relativePath), throwsFormatException);
    },
  );

  test(
    'Ordner neu zuordnen prüft Inhalt und übernimmt keine falsche Kopie',
    () async {
      final source = await foto('bild.jpg');
      await katalog.scanne(quelle).drain<void>();
      final a = (await db.allAssetsForIntegrityCheck()).single;
      final id = refs.ordner.keys.single;
      final neu = await Directory(p.join(temp.path, 'neu')).create();
      final ziel = await source.copy(p.join(neu.path, 'bild.jpg'));
      await refs.ordnerNeuZuordnen(id, neu);
      expect(
        (await refs.lesen(a.relativePath)).path,
        await ziel.resolveSymbolicLinks(),
      );
      await source.writeAsBytes([1, 2, 3]);
      await expectLater(
        refs.ordnerNeuZuordnen(id, quelle),
        throwsFormatException,
      );
      expect(
        (await refs.lesen(a.relativePath)).path,
        await ziel.resolveSymbolicLinks(),
      );
    },
  );

  test('Journal bestätigt neue Zuordnung vor Katalogeintrag', () async {
    final source = await foto('bild.jpg');
    final id = await refs.ordnerHinzufuegen(quelle);
    final rel = await refs.aufnehmen(id, source);
    final wieder = OriginalReferenzen(refs.datei);
    await wieder.laden();
    expect(wieder.dateien[rel]!.sha256, refs.dateien[rel]!.sha256);
    await refs.entfernen(rel);
    final danach = OriginalReferenzen(refs.datei);
    await danach.laden();
    expect(danach.dateien, isEmpty);
  });

  test(
    'Bibliothekswurzel und ungültige Ausschlüsse scheitern vor dem Scan',
    () async {
      await expectLater(
        katalog.scanne(temp).drain<void>(),
        throwsFormatException,
      );
      await expectLater(
        katalog.scanne(quelle, ausschliessen: ['../*']).drain<void>(),
        throwsFormatException,
      );
    },
  );
  test(
    'abgerissener Journalanhang verwirft nur die unbestätigte letzte Zeile',
    () async {
      final f = await foto('bild.jpg');
      final root = await refs.ordnerHinzufuegen(quelle);
      final id = await refs.aufnehmen(root, f);
      await File(
        '${refs.datei.path}.jsonl',
      ).writeAsString('{"id":', mode: FileMode.append);
      final neu = OriginalReferenzen(refs.datei);
      await neu.laden();
      expect(
        await (await neu.lesen(id, inhaltPruefen: true)).readAsBytes(),
        await f.readAsBytes(),
      );
      final nochmals = OriginalReferenzen(refs.datei);
      await nochmals.laden();
      expect(nochmals.dateien.keys, [id]);
    },
  );
  test(
    'Sicherung externer Originale stellt verwaltete Kopien ohne Quellzuordnung her',
    () async {
      final f = await foto('bild.jpg');
      await katalog.scanne(quelle).drain<void>();
      final ziel = '${temp.path}/sicherung';
      final lauf = await BackupService(db, paths).performBackup(ziel).toList();
      expect(
        lauf.last.wiederherstellungsprobe?.erfolgreich,
        isTrue,
        reason: lauf.last.wiederherstellungsprobe?.alsJson().toString(),
      );
      final neuDb = AppDatabase(NativeDatabase.memory());
      addTearDown(neuDb.close);
      final neuPaths = await StoragePaths.forTesting(
        Directory('${temp.path}/neu'),
      );
      final r = await BackupService(neuDb, neuPaths)
          .restoreFromBackup(
            '$ziel/PhotoVault-Backup',
            ImportService(neuDb, neuPaths),
            streng: true,
          )
          .toList();
      expect(r.last.wiederherstellung?.erfolgreich, isTrue);
      final a = (await neuDb.allAssetsForIntegrityCheck()).single;
      expect(neuPaths.istReferenziert(a.relativePath), isFalse);
      expect(
        await (await neuPaths.bereit(a.relativePath)).readAsBytes(),
        await f.readAsBytes(),
      );
    },
  );
}
