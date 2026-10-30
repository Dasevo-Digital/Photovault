import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:kern/db/database.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// Der überwachte Ordner nimmt neue Dateien von selbst auf. Die Zusagen,
/// auf die es dabei ankommt: Es wird nichts doppelt importiert, im fremden
/// Ordner wird nichts verändert oder gelöscht, Eingelesenes wird nicht
/// alle fünf Minuten wieder gelesen, und Halbfertiges kommt nicht an
/// (#252).
void main() {
  late Directory tempRoot;
  late Directory beobachtet;
  late AppDatabase db;
  late LibraryState lib;
  late _Zaehlend importe;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_watch_');
    beobachtet = Directory(p.join(tempRoot.path, 'kamera'))..createSync();
    db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(
      Directory(p.join(tempRoot.path, 'lib')),
    );
    importe = _Zaehlend(db, paths);
    lib = LibraryState()
      ..db = db
      ..paths = paths
      ..importService = importe;
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  /// Eine Datei, die schon eine Weile unverändert dort liegt.
  File lege(String name, int fuellung) => File(p.join(beobachtet.path, name))
    ..writeAsBytesSync(List.filled(64, fuellung))
    ..setLastModifiedSync(DateTime.now().subtract(const Duration(minutes: 10)));

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

    expect(
      await lib.pruefeUeberwachtenOrdner(),
      0,
      reason:
          'die Prüfsummenerkennung des Imports muss greifen, sonst '
          'wüchse die Bibliothek bei jedem Durchgang',
    );
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
    expect(
      nachher,
      vorher,
      reason: 'ein fremder Ordner wird gelesen, nicht aufgeräumt',
    );
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
    await db.setzeUeberwachtenOrdner(
      pfad: p.join(tempRoot.path, 'gibtesnicht'),
    );
    expect(
      await lib.pruefeUeberwachtenOrdner(),
      0,
      reason: 'eine abgezogene Platte darf den Programmstart nicht stören',
    );
  });

  test('Eingelesenes wird nicht wieder gelesen (#252)', () async {
    lege('a.jpg', 1);
    lege('b.jpg', 2);
    await db.setzeUeberwachtenOrdner(pfad: beobachtet.path);
    await lib.pruefeUeberwachtenOrdner();
    expect(importe.gelesen, 2);

    await lib.pruefeUeberwachtenOrdner();
    await lib.pruefeUeberwachtenOrdner();
    expect(
      importe.gelesen,
      2,
      reason: 'jeder Durchgang las bisher jede Datei ganz für ihre Prüfsumme',
    );

    // Was sich ändert, kommt wieder dran.
    lege('a.jpg', 7);
    expect(await lib.pruefeUeberwachtenOrdner(), 1);
    expect(importe.gelesen, 3);
  });

  test('eine eben geschriebene Datei wartet einen Durchgang', () async {
    await db.setzeUeberwachtenOrdner(pfad: beobachtet.path);
    File(
      p.join(beobachtet.path, 'frisch.jpg'),
    ).writeAsBytesSync(List.filled(64, 9));

    expect(await lib.pruefeUeberwachtenOrdner(), 0);
    expect(importe.gelesen, 0);

    expect(await lib.pruefeUeberwachtenOrdner(), 1);
    expect(await db.select(db.assets).get(), hasLength(1));
  });

  test('eine wachsende Datei kommt erst vollständig an', () async {
    await db.setzeUeberwachtenOrdner(pfad: beobachtet.path);
    final datei = File(p.join(beobachtet.path, 'video.mp4'))
      ..writeAsBytesSync(List.filled(64, 1));
    expect(await lib.pruefeUeberwachtenOrdner(), 0);

    // Die Kopie läuft weiter: andere Grösse, also wieder warten.
    datei.writeAsBytesSync(List.filled(64, 1), mode: FileMode.append);
    expect(await lib.pruefeUeberwachtenOrdner(), 0);

    expect(await lib.pruefeUeberwachtenOrdner(), 1);
    final a = (await db.select(db.assets).get()).single;
    expect(a.fileSizeBytes, 128);
  });
}

/// Zählt, wie oft der Import eine Datei anfasst – jedes Mal liest er sie
/// für die Prüfsumme ganz.
class _Zaehlend extends ImportService {
  _Zaehlend(super.db, super.paths);

  int gelesen = 0;

  @override
  Future<ImportResult> importFile(
    String filePath, {
    String? erwartetePruefsumme,
    ImportDateiangaben? erwarteteAngaben,
    Future<void> Function(String assetId)? beiEintrag,
  }) {
    gelesen++;
    return super.importFile(
      filePath,
      erwartetePruefsumme: erwartetePruefsumme,
      erwarteteAngaben: erwarteteAngaben,
      beiEintrag: beiEintrag,
    );
  }
}
