import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations_de.dart';
import 'package:photo_vault/services/export_service.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Der Export kann jetzt verkleinern. Entscheidend ist, dass die
/// Voreinstellung weiterhin die unveränderte Originaldatei liefert und dass
/// nichts ausgelassen wird, worauf eine Grössenvorgabe nicht anwendbar ist.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late StoragePaths paths;
  late ImportService imp;
  late ExportService exporter;
  late Directory ziel;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_export_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
    imp = ImportService(db, paths);
    exporter = ExportService(paths);
    ziel = Directory(p.join(tempRoot.path, 'ziel'))..createSync();
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<AssetData> importiere(String name, List<int> bytes) async {
    final inc = Directory(p.join(tempRoot.path, 'in'))..createSync(recursive: true);
    final f = File(p.join(inc.path, name))..writeAsBytesSync(bytes);
    final r = await imp.importFile(f.path);
    return (await db.assetById(r.assetId!))!;
  }

  test('die Voreinstellung liefert die Datei unverändert', () async {
    final inhalt = List.generate(500, (i) => i % 256);
    final asset = await importiere('urlaub.jpg', inhalt);

    final name = await exporter.exportAsset(asset, ziel.path);

    expect(name, 'urlaub.jpg', reason: 'Name und Endung bleiben');
    expect(File(p.join(ziel.path, name)).readAsBytesSync(), inhalt,
        reason: 'ohne Grössenvorgabe wird byteweise kopiert');
  });

  test('neben dem Original entsteht eine XMP-Datei', () async {
    final asset = await importiere('mitxmp.jpg', [1, 2, 3]);
    final name = await exporter.exportAsset(asset, ziel.path);
    // Die Sidecar-Datei ersetzt die Endung (siehe StoragePaths.xmpSidecarPath),
    // sie hängt sie nicht an.
    final sidecar = File(p.setExtension(p.join(ziel.path, name), '.xmp'));
    expect(sidecar.existsSync(), isTrue);
  });

  test('eine Namenskollision überschreibt nichts', () async {
    final a = await importiere('gleich.jpg', [1, 2, 3]);
    final erste = await exporter.exportAsset(a, ziel.path);
    final zweite = await exporter.exportAsset(a, ziel.path);

    expect(erste, 'gleich.jpg');
    expect(zweite, isNot('gleich.jpg'));
    expect(File(p.join(ziel.path, erste)).existsSync(), isTrue);
  });

  test('die Grössenstufen sind sinnvoll geordnet', () {
    expect(Exportgroesse.original.maxKante, isNull);
    final kanten = Exportgroesse.values
        .where((g) => g.maxKante != null)
        .map((g) => g.maxKante!)
        .toList();
    expect(kanten, [4096, 2048, 1024],
        reason: 'absteigend, damit die Liste von "gross" nach "klein" liest');
    // Die Beschriftungen stehen seit der Übersetzung nicht mehr im Enum,
    // sondern in den Sprachdateien – geprüft wird jetzt, dass für jeden Wert
    // wirklich einer dort steht und keiner durch die Nachschlagetabelle
    // fällt.
    for (final g in Exportgroesse.values) {
      expect(exportgroesseBezeichnung(AppTexteDe(), g), isNotEmpty);
    }
  });

  test('ein Video wird auch mit Grössenvorgabe unverändert kopiert', () async {
    // Für Videos gibt es keine JPEG-Umwandlung; sie dürfen deshalb nicht
    // stillschweigend aus dem Export fallen.
    final asset = await importiere('film.mov', [9, 9, 9, 9]);
    expect(asset.type, 'VIDEO');

    final name = await exporter.exportAsset(asset, ziel.path,
        groesse: Exportgroesse.web);

    expect(name, 'film.mov', reason: 'Endung und Inhalt bleiben');
    expect(File(p.join(ziel.path, name)).readAsBytesSync(), [9, 9, 9, 9]);
  });
}
