import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

/// Prüft, dass eine frisch angelegte Datenbank mindestens Schema-Version 14
/// hat und alle in Migration 14 hinzugefügten Indizes tatsächlich existieren
/// – vor allem als Absicherung gegen einen Tippfehler in den rohen
/// SQL-Statements (`customStatement`), den `flutter analyze` naturgemäß
/// nicht erkennen kann. Bewusst "mindestens" statt exakt 14, damit spätere
/// Schema-Versionen diesen Test nicht bei jeder Migration anpassen müssen.
void main() {
  test('legt alle Indizes aus Migration 14 auf einer frischen DB an', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, greaterThanOrEqualTo(14));

    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .get();
    final indexNames = rows.map((r) => r.data['name'] as String).toSet();

    for (final expected in [
      'idx_assets_trashed_locked_created',
      'idx_assets_location',
      'idx_faces_asset_id',
      'idx_faces_person_id',
      'idx_album_assets_asset_id',
      'idx_assets_trashed_at',
      'idx_assets_gps',
      'idx_assets_not_backed_up',
      'idx_assets_not_auto_backed_up',
      'idx_assets_camera',
    ]) {
      expect(indexNames, contains(expected), reason: 'Index $expected fehlt.');
    }
  });

  test('legt die Kamera-Preset-Tabellen aus Migration 15 auf einer frischen DB an', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, greaterThanOrEqualTo(15));

    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final tableNames = rows.map((r) => r.data['name'] as String).toSet();

    expect(tableNames, contains('camera_presets'));
    expect(tableNames, contains('camera_preset_tags'));
  });

  test('legt die DevelopSettings-Tabelle und Assets.developed_relative_path aus Migration 16 an', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, greaterThanOrEqualTo(16));

    final tableRows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    expect(tableRows.map((r) => r.data['name'] as String).toSet(), contains('develop_settings'));

    final columnRows = await db.customSelect('PRAGMA table_info(assets)').get();
    final columnNames = columnRows.map((r) => r.data['name'] as String).toSet();
    expect(columnNames, contains('developed_relative_path'));
  });

  test('legt rating/colorLabel/ocrText/ocrScanned/sharpnessScore aus Migration 17 an', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, greaterThanOrEqualTo(17));

    final columnRows = await db.customSelect('PRAGMA table_info(assets)').get();
    final columnNames = columnRows.map((r) => r.data['name'] as String).toSet();
    expect(columnNames, contains('rating'));
    expect(columnNames, contains('color_label'));
    expect(columnNames, contains('ocr_text'));
    expect(columnNames, contains('ocr_scanned'));
    expect(columnNames, contains('sharpness_score'));
  });

  test('legt die DevelopHistory-Tabelle aus Migration 18 auf einer frischen DB an', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, greaterThanOrEqualTo(18));

    final tableRows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    expect(tableRows.map((r) => r.data['name'] as String).toSet(), contains('develop_history'));
  });

  test('legt die VideoTrims-Tabelle und Assets.trimmed_relative_path aus Migration 19 an', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, greaterThanOrEqualTo(19));

    final tableRows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    expect(tableRows.map((r) => r.data['name'] as String).toSet(), contains('video_trims'));

    final columnRows = await db.customSelect('PRAGMA table_info(assets)').get();
    final columnNames = columnRows.map((r) => r.data['name'] as String).toSet();
    expect(columnNames, contains('trimmed_relative_path'));
  });

  test('legt stack_id/is_stack_cover/stack_size aus Migration 20 an', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, greaterThanOrEqualTo(20));

    final columnRows = await db.customSelect('PRAGMA table_info(assets)').get();
    final columnNames = columnRows.map((r) => r.data['name'] as String).toSet();
    expect(columnNames, contains('stack_id'));
    expect(columnNames, contains('is_stack_cover'));
    expect(columnNames, contains('stack_size'));
  });

  test('legt die DevelopMasks-Tabelle aus Migration 21 auf einer frischen DB an', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, greaterThanOrEqualTo(21));

    final tableRows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    expect(tableRows.map((r) => r.data['name'] as String).toSet(), contains('develop_masks'));
  });

  test('legt ai_caption/ai_caption_scanned aus Migration 22 auf einer frischen DB an', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, greaterThanOrEqualTo(22));

    final columnRows = await db.customSelect('PRAGMA table_info(assets)').get();
    final columnNames = columnRows.map((r) => r.data['name'] as String).toSet();
    expect(columnNames, contains('ai_caption'));
    expect(columnNames, contains('ai_caption_scanned'));
  });

  test('legt die AppSettings-Tabelle aus Migration 23 auf einer frischen DB an', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, greaterThanOrEqualTo(23));

    final tableRows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    expect(tableRows.map((r) => r.data['name'] as String).toSet(), contains('app_settings'));
  });

  test('legt die AiTagVocabulary-Tabelle aus Migration 24 auf einer frischen DB an', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, greaterThanOrEqualTo(24));

    final tableRows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    expect(tableRows.map((r) => r.data['name'] as String).toSet(), contains('ai_tag_vocabulary'));
  });

  test('legt Faces.eye_open_score aus Migration 25 auf einer frischen DB an', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, greaterThanOrEqualTo(25));

    final columnRows = await db.customSelect('PRAGMA table_info(faces)').get();
    final columnNames = columnRows.map((r) => r.data['name'] as String).toSet();
    expect(columnNames, contains('eye_open_score'));
  });

  test('legt DevelopMasks.shape_definition_json aus Migration 26 auf einer frischen DB an', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, greaterThanOrEqualTo(26));

    final columnRows = await db.customSelect('PRAGMA table_info(develop_masks)').get();
    final columnNames = columnRows.map((r) => r.data['name'] as String).toSet();
    expect(columnNames, contains('shape_definition_json'));
  });

  test('legt Assets.restored_relative_path und die RestoreJobs-Tabelle aus Migration 27 an', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.schemaVersion, greaterThanOrEqualTo(27));

    final columnRows = await db.customSelect('PRAGMA table_info(assets)').get();
    final columnNames = columnRows.map((r) => r.data['name'] as String).toSet();
    expect(columnNames, contains('restored_relative_path'));

    final tableRows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    expect(tableRows.map((r) => r.data['name'] as String).toSet(), contains('restore_jobs'));
  });
}
