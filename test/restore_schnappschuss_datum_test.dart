import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/storage_paths.dart';

/// Ein einziges Original, dessen Datum sich beim Übernehmen aus dem
/// Schnappschuss nicht umsetzen lässt, darf nicht alles andere mitnehmen
/// (#243): Personen, Gesichter, Stammbaum und Reisen kommen trotzdem.
void main() {
  late Directory temp;
  late File schnappschuss;
  late AppDatabase db;
  late StoragePaths paths;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_schnappschuss_datum_');
    // Im Schnappschuss: eine Aufnahme von 2020 und eine Person.
    schnappschuss = File('${temp.path}/schnappschuss.sqlite');
    final quelle = AppDatabase(NativeDatabase(schnappschuss));
    await quelle.insertAsset(
      AssetsCompanion.insert(
        id: 'gesichert',
        originalFileName: 'a.jpg',
        relativePath: 'originals/2020/01/gesichert.jpg',
        checksum: 'pruefsumme',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2020, 1, 5),
        importedAt: DateTime(2026),
      ),
    );
    await quelle.createPerson(
      PeopleCompanion.insert(id: 'person', name: 'Erika'),
    );
    await quelle.close();

    // Im Ziel dieselbe Aufnahme, anders datiert. Ihr Original fehlt auf
    // der Platte – das Umbenennen in den Ordner von 2020 scheitert.
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory('${temp.path}/bibliothek'));
    await db.insertAsset(
      AssetsCompanion.insert(
        id: 'hier',
        originalFileName: 'a.jpg',
        relativePath: 'originals/2026/10/hier.jpg',
        checksum: 'pruefsumme',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2026, 10, 1),
        importedAt: DateTime(2026),
      ),
    );
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  test('die Personen kommen trotzdem, das Datum bleibt', () async {
    await BackupService(db, paths).uebernimmAusSchnappschuss(schnappschuss);

    expect((await db.select(db.people).get()).map((p) => p.name), ['Erika']);
    final hier = (await db.assetById('hier'))!;
    expect(hier.fileCreatedAt, DateTime(2026, 10, 1));
    expect(hier.relativePath, 'originals/2026/10/hier.jpg');
  });

  test('die strenge Probe meldet den Fehler weiterhin', () async {
    await expectLater(
      BackupService(
        db,
        paths,
      ).uebernimmAusSchnappschuss(schnappschuss, streng: true),
      throwsA(isA<FileSystemException>()),
    );
  });
}
