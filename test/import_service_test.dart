import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

import 'cr3_bauen.dart';

class _FehlerndeDatenbank extends AppDatabase {
  _FehlerndeDatenbank() : super(NativeDatabase.memory());

  @override
  Future<void> insertAsset(AssetsCompanion asset) async {
    throw StateError('nach dem Kopieren absichtlich abgebrochen');
  }
}

void main() {
  late Directory tempRoot;
  late Directory sourceDir;
  late AppDatabase db;
  late StoragePaths paths;
  late ImportService importService;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('photo_vault_import_test_');
    sourceDir = Directory(p.join(tempRoot.path, 'incoming'))..createSync();
    paths = await StoragePaths.forTesting(
        Directory(p.join(tempRoot.path, 'library')));
    db = AppDatabase(NativeDatabase.memory());
    importService = ImportService(db, paths);
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  test(
      'isSupported erkennt Bild- und Videoformate unabhängig von Groß-/Kleinschreibung',
      () {
    expect(importService.isSupported('foto.JPG'), isTrue);
    expect(importService.isSupported('foto.heic'), isTrue);
    expect(importService.isSupported('foto.avif'), isTrue);
    expect(importService.isSupported('foto.AVIFS'), isTrue);
    expect(importService.isSupported('clip.MOV'), isTrue);
    expect(importService.isSupported('dokument.txt'), isFalse);
  });

  test('isSupported erkennt RAW-Formate weiterer Hersteller, nicht nur DNG',
      () {
    expect(importService.isSupported('foto.dng'), isTrue);
    expect(importService.isSupported('foto.CR2'), isTrue);
    expect(importService.isSupported('foto.cr3'), isTrue);
    expect(importService.isSupported('foto.crw'), isTrue);
    expect(importService.isSupported('foto.nef'), isTrue);
    expect(importService.isSupported('foto.arw'), isTrue);
    expect(importService.isSupported('foto.raf'), isTrue);
    expect(importService.isSupported('foto.orf'), isTrue);
    expect(importService.isSupported('foto.rw2'), isTrue);
    expect(importService.isSupported('foto.pef'), isTrue);
  });

  test(
      'importFile legt einen Asset-Eintrag an und kopiert die Datei in die Bibliothek',
      () async {
    final file = File(p.join(sourceDir.path, 'a.jpg'))
      ..writeAsBytesSync([1, 2, 3, 4, 5]);

    final result = await importService.importFile(file.path);

    expect(result.outcome, ImportOutcome.imported);
    expect(result.assetId, isNotNull);

    final asset = await db.assetById(result.assetId!);
    expect(asset, isNotNull);
    expect(asset!.originalFileName, 'a.jpg');
    expect(await paths.absolute(asset.relativePath).exists(), isTrue);
  });

  test(
      'identischer Dateiinhalt wird per SHA-256-Prüfsumme als Duplikat erkannt, auch unter anderem Dateinamen',
      () async {
    final bytes = [10, 20, 30, 40, 50, 60];
    final first = File(p.join(sourceDir.path, 'first.jpg'))
      ..writeAsBytesSync(bytes);
    final second = File(p.join(sourceDir.path, 'second.jpg'))
      ..writeAsBytesSync(bytes);

    final r1 = await importService.importFile(first.path);
    final r2 = await importService.importFile(second.path);

    expect(r1.outcome, ImportOutcome.imported);
    expect(r2.outcome, ImportOutcome.duplicateSkipped);

    final allAssets = await db.select(db.assets).get();
    expect(allAssets,
        hasLength(1)); // trotz zwei Importversuchen nur ein DB-Eintrag
  });

  test(
      'unterschiedlicher Inhalt mit gleichem Dateinamen wird NICHT als Duplikat behandelt',
      () async {
    final firstDir = Directory(p.join(sourceDir.path, 'ordner1'))..createSync();
    final secondDir = Directory(p.join(sourceDir.path, 'ordner2'))
      ..createSync();
    File(p.join(firstDir.path, 'foto.jpg')).writeAsBytesSync([1, 1, 1]);
    File(p.join(secondDir.path, 'foto.jpg')).writeAsBytesSync([2, 2, 2]);

    final r1 =
        await importService.importFile(p.join(firstDir.path, 'foto.jpg'));
    final r2 =
        await importService.importFile(p.join(secondDir.path, 'foto.jpg'));

    expect(r1.outcome, ImportOutcome.imported);
    expect(r2.outcome, ImportOutcome.imported);
    expect(await db.select(db.assets).get(), hasLength(2));
  });

  test(
      'nicht unterstütztes Format schlägt kontrolliert fehl statt eine Exception zu werfen',
      () async {
    final file = File(p.join(sourceDir.path, 'notiz.txt'))
      ..writeAsStringSync('hallo welt');

    final result = await importService.importFile(file.path);

    expect(result.outcome, ImportOutcome.failed);
    expect(result.error, contains('Nicht unterstütztes Format'));
    expect(await db.select(db.assets).get(), isEmpty);
  });

  test('ein Fehler nach dem Kopieren räumt Original und Vorschaudateien auf',
      () async {
    await db.close();
    db = _FehlerndeDatenbank();
    importService = ImportService(db, paths);
    final file = File(p.join(sourceDir.path, 'gueltig.jpg'))
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 24, height: 16)));

    final result = await importService.importFile(file.path);

    expect(result.outcome, ImportOutcome.failed);
    expect(result.error, contains('absichtlich abgebrochen'));
    final reste = paths.root
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => p.relative(f.path, from: paths.root.path))
        .toList();
    expect(reste, isEmpty,
        reason: 'ein nicht eingetragener Import darf keine Dateien behalten');
  });

  group('CR3 traegt seinen Ort im Container, nicht in den EXIF-Tags', () {
    /// Eine CR3 mit Koordinaten – Aufbau wie bei einer echten Aufnahme,
    /// Zahlen erfunden.
    File cr3(String name) => File(p.join(sourceDir.path, name))
      ..writeAsBytesSync(cr3Mit(gpsVerzeichnis(
          breite: beispielBreite,
          breiteRef: 'N',
          laenge: beispielLaenge,
          laengeRef: 'E')));

    test('readGpsLocation liest ihn – die Aufgabe „Orte einlesen" hing daran',
        () async {
      // `package:exif` liefert bei CR3 NULL Tags. Vor diesem Weg gab
      // readGpsLocation deshalb immer null zurueck, und in einer
      // Bibliothek mit 812 CR3-Aufnahmen trugen 522 einen Ort in der
      // Datei, den die Datenbank nie sah.
      final ort = await importService.readGpsLocation(cr3('mit_ort.cr3'));
      expect(ort, isNotNull);
      expect(ort!.latitude, closeTo(52.2431111, 1e-6));
      expect(ort.longitude, closeTo(10.5852778, 1e-6));
    });

    test('auch wenn der Dateiname etwas anderes behauptet', () async {
      // Die Endung ist eine Behauptung, die ersten Bytes sind die Datei.
      final ort = await importService.readGpsLocation(cr3('heisst_jpg.jpg'));
      expect(ort, isNotNull);
      expect(ort!.latitude, closeTo(52.2431111, 1e-6));
    });

    test('beim Import landet der Ort in der Datenbank', () async {
      // Die Verdrahtung, nicht der Leser: Ein Test, der nur
      // readGpsLocation aufruft, sieht den Weg vom Import dorthin nicht.
      final ergebnis = await importService.importFile(cr3('import.cr3').path);
      expect(ergebnis.outcome, ImportOutcome.imported);
      final zeile = (await db.select(db.assets).get()).single;
      expect(zeile.latitude, closeTo(52.2431111, 1e-6));
      expect(zeile.longitude, closeTo(10.5852778, 1e-6));
    });

    test('ohne Koordinaten bleibt der Ort leer statt 0/0', () async {
      final ohne = File(p.join(sourceDir.path, 'ohne_ort.cr3'))
        ..writeAsBytesSync(
            File('test/fixtures/werkzeuge/eos_r10_kopf.cr3').readAsBytesSync());
      expect(await importService.readGpsLocation(ohne), isNull);
    });
  });
}
