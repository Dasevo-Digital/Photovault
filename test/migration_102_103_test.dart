import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:photo_vault/services/export_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Schritt 103 (#468): Exportvorgaben tragen den Schalter „Ort mitgeben“.
/// Bestehende Vorgaben bekommen `false` und geben damit genau so viel Ort
/// mit wie vorher: eine gerenderte keinen, eine unverändert kopierte den
/// der Datei.
void main() {
  late Directory temp;
  late File datei;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_schema103_');
    datei = File('${temp.path}/library.sqlite');
  });
  tearDown(() => temp.delete(recursive: true));

  test('102 auf 103: die Spalte kommt dazu, für bestehende Vorgaben ändert '
      'sich nichts', () async {
    final vorher = AppDatabase(NativeDatabase(datei));
    for (final (name, jpeg) in [('Web', true), ('Kopie', false)]) {
      await vorher.upsertExportPreset(
        ExportPresetsCompanion.insert(
          name: name,
          nachJpeg: Value(jpeg),
          maxKante: Value(jpeg ? 2048 : null),
          erstelltAm: DateTime(2026, 11, 1),
        ),
      );
    }
    await vorher
        .into(vorher.developPresets)
        .insert(
          DevelopPresetsCompanion.insert(
            name: 'Kunstlicht',
            temperature: const Value(3200),
            erstelltAm: DateTime(2026, 11, 1),
          ),
        );
    await vorher.close();

    // Zurück auf 102: ohne die neue Spalte.
    final roh = sqlite.sqlite3.open(datei.path);
    roh.execute('ALTER TABLE export_presets DROP COLUMN ort_mitgeben');
    roh.execute('PRAGMA user_version = 102');
    roh.close();

    final db = AppDatabase(NativeDatabase(datei));
    addTearDown(db.close);
    final vorgaben = {for (final v in await db.alleExportPresets()) v.name: v};
    expect(vorgaben.keys, unorderedEquals(['Web', 'Kopie']));
    expect(vorgaben.values.map((v) => v.ortMitgeben), everyElement(isFalse));
    // Wie bis 102: gerendert ohne Ort, die Kopie mit dem Ort der Datei.
    expect(Exportvorgabe.ausPreset(vorgaben['Web']!).ortMitgeben, isFalse);
    expect(Exportvorgabe.ausPreset(vorgaben['Kopie']!).ortMitgeben, isTrue);
    expect(
      (await db.customSelect('PRAGMA user_version').getSingle())
          .data
          .values
          .single,
      db.schemaVersion,
    );
    // Schritt 102 läuft nicht noch einmal: Die Temperatur bleibt stehen.
    final warm = await db.select(db.developPresets).getSingle();
    expect(warm.temperature, 3200);

    // Der Schalter lässt sich setzen.
    await db.upsertExportPreset(
      vorgaben['Web']!
          .toCompanion(true)
          .copyWith(ortMitgeben: const Value(true)),
    );
    final web = (await db.alleExportPresets()).firstWhere(
      (v) => v.name == 'Web',
    );
    expect(Exportvorgabe.ausPreset(web).ortMitgeben, isTrue);
  });
}
