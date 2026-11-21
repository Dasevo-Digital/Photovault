import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:kern/db/database.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault/services/export_service.dart';
import 'package:photo_vault/state/library_state.dart';

/// **Aus dem gesperrten Ordner kam eine Datei ohne Namen** (BEA-132).
///
/// Gesperrt heisst jede Aufnahme in der Datenbank „Private Aufnahme“; der
/// echte Name liegt verschlüsselt daneben. Der Export nahm Name und Endung
/// aus der Datenbank – am Ziel lag „Private Aufnahme“, ohne Endung.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths pfade;
  late LibraryState bib;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_tresor_export_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(wurzel.path, 'lib')),
    );
    bib = LibraryState()
      ..db = db
      ..paths = pfade
      ..klartextOrdnerFuerTests = Directory(p.join(wurzel.path, 'klartext'));
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  test('der Export trägt den echten Namen samt Endung', () async {
    final eingang = Directory(p.join(wurzel.path, 'ein'))..createSync();
    final inhalt = List<int>.generate(2000, (i) => i % 256);
    final datei = File(p.join(eingang.path, 'Urlaub_2019.jpg'))
      ..writeAsBytesSync(inhalt);
    final id = (await ImportService(db, pfade).importFile(datei.path)).assetId!;
    await bib.setupVaultPin('1234');
    await bib.lockAsset((await db.assetById(id))!);
    final gesperrt = (await db.assetById(id))!;
    expect(gesperrt.originalFileName, 'Private Aufnahme');

    final ziel = Directory(p.join(wurzel.path, 'aus'))..createSync();
    final name = await ExportService(
      pfade,
      library: bib,
    ).exportAsset(gesperrt, ziel.path);

    expect(name, 'Urlaub_2019.jpg');
    expect(File(p.join(ziel.path, name)).readAsBytesSync(), inhalt);
    expect(
      (await db.assetById(id))!.originalFileName,
      'Private Aufnahme',
      reason: 'in der Datenbank bleibt der neutrale Name',
    );
  });
}
