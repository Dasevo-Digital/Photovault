import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/bearbeitungsprogramme.dart';
import 'package:photo_vault/services/fremdprogramme.dart';
import 'package:photo_vault/state/library_state.dart';

/// **Klartextkopien blieben liegen** (#499): Ein Foto in GIMP geöffnet,
/// dann gesperrt oder endgültig gelöscht – die Arbeitskopie lag weiter im
/// Klartext unter „Bilder“. Jetzt räumt die Bibliothek sie dabei weg; was
/// das Programm selbst gespeichert hat, bleibt (siehe
/// Bearbeitungsbruecke.raeumeKlartextWeg).
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths pfade;
  late LibraryState bib;
  late Bearbeitungsprogramme programme;
  late List<List<String>> gerufen;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_klartext_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(wurzel.path, 'lib')),
    );
    programme = Bearbeitungsprogramme(
      basis: Directory(p.join(wurzel.path, 'Bilder')),
      einstellungen: () async => File(p.join(wurzel.path, 'programme.json')),
      system: 'macos',
      erkenne: () async => const {},
    );
    gerufen = [];
    bib = LibraryState()
      ..db = db
      ..paths = pfade
      ..klartextOrdnerFuerTests = Directory(p.join(wurzel.path, 'klartext'))
      ..beiKlartextFort = (ids) async {
        gerufen.add(ids);
        await programme.raeumeKlartextWeg(ids);
      };
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<String> importiere(String name) async {
    final eingang = Directory(p.join(wurzel.path, 'ein'))..createSync();
    final datei = File(p.join(eingang.path, name))
      ..writeAsBytesSync(
        List<int>.generate(3000, (i) => (i + name.codeUnits.first) % 256),
      );
    return (await ImportService(db, pfade).importFile(datei.path)).assetId!;
  }

  Future<Directory> inGimp(String id) async {
    final gimp = programme.alle.singleWhere((x) => x.art == Bekannt.gimp);
    final b = programme.bruecke(gimp);
    final a = (await db.assetById(id))!;
    await b.oeffne(
      id: id,
      name: a.originalFileName,
      original: pfade.absolute(a.relativePath),
    );
    return b.ordner(id);
  }

  test('beim Sperren geht die Arbeitskopie mit', () async {
    final id = await importiere('Urlaub.jpg');
    final ordner = await inGimp(id);
    expect(File(p.join(ordner.path, 'Urlaub.jpg')).existsSync(), isTrue);
    await bib.setupVaultPin('1234');
    await bib.lockAsset((await db.assetById(id))!);
    expect(gerufen, [
      [id],
    ]);
    expect(ordner.existsSync(), isFalse);

    // Gegenprobe: Entsperren ruft nichts auf.
    await bib.unlockAsset((await db.assetById(id))!);
    expect(gerufen, hasLength(1));
  });

  test(
    'beim endgültigen Löschen auch – nur für das, was wirklich ging',
    () async {
      final id = await importiere('Urlaub.jpg');
      final ordner = await inGimp(id);
      final bleibt = await inGimp(await importiere('Garten.jpg'));
      await (db.update(db.assets)..where((t) => t.id.equals(id))).write(
        AssetsCompanion(
          isTrashed: const Value(true),
          trashedAt: Value(DateTime(2026, 8)),
        ),
      );
      expect(await bib.endgueltigLoeschen(), 1);
      expect(gerufen, [
        [id],
      ]);
      expect(ordner.existsSync(), isFalse);
      expect(bleibt.existsSync(), isTrue);
    },
  );

  test(
    'Gegenprobe: ohne eingesetzten Aufräumer bleibt alles, wie es war',
    () async {
      bib.beiKlartextFort = null;
      final id = await importiere('Urlaub.jpg');
      final ordner = await inGimp(id);
      await bib.setupVaultPin('1234');
      await bib.lockAsset((await db.assetById(id))!);
      expect(ordner.existsSync(), isTrue);
    },
  );
}
