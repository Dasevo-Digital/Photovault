import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/wasserzeichen.dart';
import 'package:photo_vault/services/export_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Schritt 104 (#497): Exportvorgaben tragen ein Wasserzeichen. Bestehende
/// Vorgaben bekommen keines und exportieren genau wie vorher.
void main() {
  late Directory temp;
  late File datei;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_schema104_');
    datei = File('${temp.path}/library.sqlite');
  });
  tearDown(() => temp.delete(recursive: true));

  test('103 auf 104: die Spalte kommt dazu, bestehende Vorgaben bleiben '
      'ohne Wasserzeichen', () async {
    final vorher = AppDatabase(NativeDatabase(datei));
    await vorher.upsertExportPreset(
      ExportPresetsCompanion.insert(
        name: 'Web',
        nachJpeg: const Value(true),
        maxKante: const Value(2048),
        ortMitgeben: const Value(true),
        erstelltAm: DateTime(2026, 11, 1),
      ),
    );
    await vorher.close();

    // Zurück auf 103: ohne die neue Spalte.
    final roh = sqlite.sqlite3.open(datei.path);
    roh.execute('ALTER TABLE export_presets DROP COLUMN wasserzeichen');
    roh.execute('PRAGMA user_version = 103');
    roh.close();

    final db = AppDatabase(NativeDatabase(datei));
    addTearDown(db.close);
    final web = (await db.alleExportPresets()).single;
    expect(web.wasserzeichen, isNull);
    expect(web.ortMitgeben, isTrue, reason: 'Schritt 103 bleibt, wie er war');
    final vorgabe = Exportvorgabe.ausPreset(web);
    expect(vorgabe.wasserzeichen, isNull);
    expect(vorgabe.maxKante, 2048);
    expect(
      (await db.customSelect('PRAGMA user_version').getSingle())
          .data
          .values
          .single,
      db.schemaVersion,
    );

    // Das Wasserzeichen lässt sich setzen.
    await db.upsertExportPreset(
      web
          .toCompanion(true)
          .copyWith(
            wasserzeichen: Value(const Wasserzeichen(text: '© 2026').kodiert()),
          ),
    );
    final mit = (await db.alleExportPresets()).single;
    expect(Exportvorgabe.ausPreset(mit).wasserzeichen?.text, '© 2026');
  });
}
