import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// Der überwachte Ordner nimmt neue Dateien von selbst auf. Die beiden
/// Zusagen, auf die es dabei ankommt: Es wird nichts doppelt importiert,
/// und im fremden Ordner wird nichts verändert oder gelöscht.
void main() {
  late Directory tempRoot;
  late Directory beobachtet;
  late AppDatabase db;
  late LibraryState lib;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_watch_');
    beobachtet = Directory(p.join(tempRoot.path, 'kamera'))..createSync();
    db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
    lib = LibraryState()
      ..db = db
      ..paths = paths
      ..importService = ImportService(db, paths);
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  File lege(String name, int fuellung) =>
      File(p.join(beobachtet.path, name))..writeAsBytesSync(List.filled(64, fuellung));

  test('ohne eingerichteten Ordner passiert nichts', () async {
    expect(await lib.pruefeUeberwachtenOrdner(), 0);
    expect(await db.select(db.assets).get(), isEmpty);
  });

  test('neue Dateien werden übernommen', () async {
    lege('a.jpg', 1);
    lege('b.jpg', 2);
    await db.setzeUeberwachtenOrdner(pfad: beobachtet.path);

    expect(await lib.pruefeUeberwachtenOrdner(), 2);
    expect(await db.select(db.assets).get(), hasLength(2));
  });

  test('ein zweiter Durchgang importiert nichts doppelt', () async {
    lege('a.jpg', 1);
    await db.setzeUeberwachtenOrdner(pfad: beobachtet.path);
    await lib.pruefeUeberwachtenOrdner();

    expect(await lib.pruefeUeberwachtenOrdner(), 0,
        reason: 'die Prüfsummenerkennung des Imports muss greifen, sonst '
            'wüchse die Bibliothek bei jedem Durchgang');
    expect(await db.select(db.assets).get(), hasLength(1));

    // Erst eine wirklich neue Datei kommt hinzu.
    lege('c.jpg', 3);
    expect(await lib.pruefeUeberwachtenOrdner(), 1);
    expect(await db.select(db.assets).get(), hasLength(2));
  });

  test('im überwachten Ordner bleibt alles unangetastet', () async {
    lege('bleibt.jpg', 4);
    final vorher = beobachtet
        .listSync()
        .whereType<File>()
        .map((f) => '${p.basename(f.path)}:${f.lengthSync()}')
        .toList();
    await db.setzeUeberwachtenOrdner(pfad: beobachtet.path);

    await lib.pruefeUeberwachtenOrdner();

    final nachher = beobachtet
        .listSync()
        .whereType<File>()
        .map((f) => '${p.basename(f.path)}:${f.lengthSync()}')
        .toList();
    expect(nachher, vorher,
        reason: 'ein fremder Ordner wird gelesen, nicht aufgeräumt');
  });

  test('die Überwachung lässt sich wieder abschalten', () async {
    await db.setzeUeberwachtenOrdner(pfad: beobachtet.path);
    expect(await db.ueberwachterOrdner(), isNotNull);

    await db.setzeUeberwachtenOrdner(pfad: null);
    expect(await db.ueberwachterOrdner(), isNull);

    lege('danach.jpg', 5);
    expect(await lib.pruefeUeberwachtenOrdner(), 0);
    expect(await db.select(db.assets).get(), isEmpty);
  });

  test('ein verschwundener Ordner wirft nicht', () async {
    await db.setzeUeberwachtenOrdner(pfad: p.join(tempRoot.path, 'gibtesnicht'));
    expect(await lib.pruefeUeberwachtenOrdner(), 0,
        reason: 'eine abgezogene Platte darf den Programmstart nicht stören');
  });
}
