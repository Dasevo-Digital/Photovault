import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/export_service.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Export-Voreinstellungen: die gespeicherte Vorgabe selbst (Schema 37) und
/// dass ein Export-Lauf sie tatsächlich befolgt.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late StoragePaths paths;
  late ImportService imp;
  late ExportService exporter;
  late Directory ziel;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_exportvorgabe_');
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

  ExportPresetsCompanion vorgabe({
    String name = 'Fotoclub',
    bool nachJpeg = false,
    int? maxKante,
    String muster = '{name}',
    bool xmp = true,
  }) =>
      ExportPresetsCompanion.insert(
        name: name,
        nachJpeg: Value(nachJpeg),
        maxKante: Value(maxKante),
        namensmuster: Value(muster),
        xmpDaneben: Value(xmp),
        erstelltAm: DateTime(2026, 8, 18),
      );

  group('gespeicherte Vorgaben', () {
    test('anlegen, lesen, ändern, löschen', () async {
      await db.upsertExportPreset(vorgabe());
      var alle = await db.alleExportPresets();
      expect(alle, hasLength(1));
      expect(alle.single.name, 'Fotoclub');
      expect(alle.single.namensmuster, '{name}');

      await db.upsertExportPreset(ExportPresetsCompanion(
        id: Value(alle.single.id),
        name: const Value('Fotoclub'),
        namensmuster: const Value('{datum}_{nr}'),
        erstelltAm: Value(alle.single.erstelltAm),
      ));
      alle = await db.alleExportPresets();
      expect(alle, hasLength(1), reason: 'dieselbe Zeile, kein Duplikat');
      expect(alle.single.namensmuster, '{datum}_{nr}');

      await db.deleteExportPreset(alle.single.id);
      expect(await db.alleExportPresets(), isEmpty);
    });

    test('ein doppelter Name wird erkannt, bevor gespeichert wird', () async {
      await db.upsertExportPreset(vorgabe(name: 'Web'));
      final web = (await db.alleExportPresets()).single;

      expect(await db.exportPresetNameVergeben('Web'), isTrue);
      expect(await db.exportPresetNameVergeben('Archiv'), isFalse);
      expect(await db.exportPresetNameVergeben('Web', ausserId: web.id), isFalse,
          reason: 'beim Bearbeiten kollidiert eine Vorgabe nicht mit sich selbst');
    });

    test('am Speichern vorbei bleibt der doppelte Name unmöglich', () async {
      // Die Prüfung oben ist die freundliche Hälfte; die `unique`-Spalte ist
      // die harte. Ohne sie würde ein zweiter Eintrag mit gleichem Namen
      // still danebenliegen und die Auswahlliste mehrdeutig machen.
      await db.upsertExportPreset(vorgabe(name: 'Web'));
      await expectLater(
        db.upsertExportPreset(vorgabe(name: 'Web', muster: '{jahr}')),
        throwsA(anything),
      );
      expect(await db.alleExportPresets(), hasLength(1));
    });

    test('die Liste kommt alphabetisch', () async {
      await db.upsertExportPreset(vorgabe(name: 'Zeitung'));
      await db.upsertExportPreset(vorgabe(name: 'Archiv'));
      await db.upsertExportPreset(vorgabe(name: 'Mail'));
      expect((await db.alleExportPresets()).map((v) => v.name),
          ['Archiv', 'Mail', 'Zeitung']);
    });
  });

  group('ein Export befolgt die Vorgabe', () {
    test('das Namensmuster bestimmt den Dateinamen', () async {
      final asset = await importiere('urlaub.jpg', [1, 2, 3]);
      await db.upsertExportPreset(vorgabe(muster: '{datum}_{nr}'));
      final gespeichert = (await db.alleExportPresets()).single;

      final name = await exporter.exportAsset(
        asset,
        ziel.path,
        vorgabe: Exportvorgabe.ausPreset(gespeichert),
        nummer: 3,
      );

      final datum = asset.fileCreatedAt;
      final erwartet =
          '${datum.year}-${datum.month.toString().padLeft(2, '0')}-'
          '${datum.day.toString().padLeft(2, '0')}_0003.jpg';
      expect(name, erwartet);
      expect(File(p.join(ziel.path, name)).existsSync(), isTrue);
    });

    test('ohne XMP-Schalter entsteht keine Beistelldatei', () async {
      final asset = await importiere('ohnexmp.jpg', [1, 2, 3]);

      final mit = await exporter.exportAsset(asset, ziel.path,
          vorgabe: const Exportvorgabe());
      expect(File(p.setExtension(p.join(ziel.path, mit), '.xmp')).existsSync(),
          isTrue);

      final ohne = await exporter.exportAsset(asset, ziel.path,
          vorgabe: const Exportvorgabe(xmpDaneben: false));
      expect(File(p.setExtension(p.join(ziel.path, ohne), '.xmp')).existsSync(),
          isFalse);
    });

    test('ohne JPEG-Schalter bleibt die Datei Bit für Bit dieselbe', () async {
      final inhalt = List.generate(400, (i) => i % 256);
      final asset = await importiere('roh.dng', inhalt);

      final name = await exporter.exportAsset(asset, ziel.path,
          vorgabe: const Exportvorgabe(namensmuster: '{name}'));

      expect(p.extension(name), '.dng', reason: 'kein umbenanntes JPEG');
      expect(File(p.join(ziel.path, name)).readAsBytesSync(), inhalt);
    });

    test('eine Namenskollision aus dem Muster überschreibt nichts', () async {
      // Ein Muster ohne {name} und ohne {nr} liefert für jedes Foto
      // denselben Namen – der Kollisionsschutz muss auch dann greifen.
      final a = await importiere('eins.jpg', [1]);
      final b = await importiere('zwei.jpg', [2]);
      const v = Exportvorgabe(namensmuster: '{datum}');

      final erste = await exporter.exportAsset(a, ziel.path, vorgabe: v);
      final zweite = await exporter.exportAsset(b, ziel.path, vorgabe: v);

      expect(zweite, isNot(erste));
      expect(File(p.join(ziel.path, erste)).readAsBytesSync(), [1]);
      expect(File(p.join(ziel.path, zweite)).readAsBytesSync(), [2]);
    });

    test('die feste Grösse und die Vorgabe beschreiben dasselbe', () {
      // Beide Wege laufen durch denselben Dienst; wären sie ungleich,
      // verhielte sich der schnelle Weg anders als eine gespeicherte
      // Vorgabe mit denselben Werten.
      final ausGroesse = Exportvorgabe.ausGroesse(Exportgroesse.web);
      expect(ausGroesse.nachJpeg, isTrue);
      expect(ausGroesse.maxKante, 2048);
      expect(Exportvorgabe.ausGroesse(Exportgroesse.original).nachJpeg, isFalse);
    });
  });

  test('eine Datenbank von Schema 36 bekommt die Tabelle nachgereicht', () async {
    final datei = File(p.join(tempRoot.path, 'alt.sqlite'));

    // Vollständige Datenbank anlegen, dann auf den Stand vor der Änderung
    // zurückversetzen: Tabelle weg, Version zurückgestempelt.
    var alt = AppDatabase(NativeDatabase(datei));
    await alt.setThemeMode('dark');
    await alt.close();

    final roh = sqlite.sqlite3.open(datei.path);
    roh.execute('DROP TABLE export_presets;');
    roh.execute('PRAGMA user_version = 36;');
    roh.close();

    // Öffnen löst die Migration auf 37 aus.
    final neu = AppDatabase(NativeDatabase(datei));
    await neu.upsertExportPreset(vorgabe(name: 'nach der Migration'));
    final alle = await neu.alleExportPresets();
    final einstellungen = await neu.watchAppSettings().first;
    await neu.close();

    expect(alle.single.name, 'nach der Migration');
    expect(einstellungen?.themeMode, 'dark',
        reason: 'vorhandene Daten bleiben unberührt');
  });
}
