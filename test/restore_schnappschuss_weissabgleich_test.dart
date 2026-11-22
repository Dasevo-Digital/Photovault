import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// **Eine Sicherung von vor Schema 102 (#466).** Ihr Schnappschuss trägt
/// die Temperatur in der früheren Bedeutung (höher = kühler). Die
/// Zielbibliothek ist schon aufgestuft, ihre Migration sieht die
/// übernommenen Zeilen nie – das Übernehmen rechnet sie deshalb selbst um.
/// Eine Sicherung ab 102 bleibt, wie sie ist.
void main() {
  late Directory temp;
  late File schnappschuss;
  late AppDatabase db;
  late StoragePaths paths;

  Future<void> legeSchnappschussAn(int stufe) async {
    schnappschuss = File('${temp.path}/schnappschuss.sqlite');
    final quelle = AppDatabase(NativeDatabase(schnappschuss));
    await quelle.insertAsset(
      AssetsCompanion.insert(
        id: 'gesichert',
        originalFileName: 'a.jpg',
        relativePath: 'originals/2026/01/gesichert.jpg',
        checksum: 'pruefsumme',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2026, 1, 5),
        importedAt: DateTime(2026),
      ),
    );
    await quelle
        .into(quelle.developSettings)
        .insert(
          DevelopSettingsCompanion.insert(
            assetId: 'gesichert',
            temperature: const Value(4000),
            updatedAt: DateTime(2026),
          ),
        );
    await quelle.upsertDevelopPreset(
      DevelopPresetsCompanion.insert(
        name: 'Kunstlicht',
        temperature: const Value(5200),
        erstelltAm: DateTime(2026),
      ),
    );
    await quelle.close();
    final roh = sqlite.sqlite3.open(schnappschuss.path);
    roh.execute('PRAGMA user_version = $stufe');
    roh.close();
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_schnappschuss_wb_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory('${temp.path}/bibliothek'));
    await db.insertAsset(
      AssetsCompanion.insert(
        id: 'hier',
        originalFileName: 'a.jpg',
        relativePath: 'originals/2026/01/hier.jpg',
        checksum: 'pruefsumme',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2026, 1, 5),
        importedAt: DateTime(2026),
      ),
    );
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  test('vor 102: Temperaturen kommen umgerechnet an', () async {
    await legeSchnappschussAn(101);
    await BackupService(db, paths).uebernimmAusSchnappschuss(schnappschuss);
    expect((await db.developSettingsForAsset('hier'))!.temperature, 10562.5);
    expect(
      (await db.select(db.developPresets).get()).single.temperature,
      8125.0,
    );
  });

  test('ab 102: unverändert', () async {
    await legeSchnappschussAn(102);
    await BackupService(db, paths).uebernimmAusSchnappschuss(schnappschuss);
    expect((await db.developSettingsForAsset('hier'))!.temperature, 4000);
    expect((await db.select(db.developPresets).get()).single.temperature, 5200);
  });
}
