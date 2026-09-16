import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Eine fehlerhafte Zwischenfassung hat Datenbanken auf Schemaversion 28
/// gestempelt, ohne die zugehörige Spalte anzulegen. Drift hält die
/// Migration damit für erledigt und führt sie nie erneut aus – die
/// Datenbank bliebe dauerhaft unbrauchbar.
///
/// Diese Tests halten fest, dass die Migration so etwas repariert, statt
/// daran zu scheitern.
void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('pv_migration_'));
  tearDown(() => temp.deleteSync(recursive: true));

  /// Baut den Schadensfall realistisch nach: eine vollständige Datenbank,
  /// aus der die Spalte entfernt und deren Version trotzdem auf [version]
  /// gestempelt wird – genau der Zustand, den die fehlerhafte
  /// Zwischenfassung hinterlassen hat.
  Future<File> beschaedigteDatenbank(int version) async {
    final datei = File('${temp.path}/library.sqlite');

    // Vollständiges Schema anlegen und einen Wert setzen, der die
    // Reparatur überleben muss.
    var db = AppDatabase(NativeDatabase(datei));
    await db.setThemeMode('dark');
    await db.close();

    final roh = sqlite.sqlite3.open(datei.path);
    roh.execute('ALTER TABLE app_settings DROP COLUMN auto_analyze_after_import;');
    roh.execute('PRAGMA user_version = $version;');
    roh.close();
    return datei;
  }

  test('fehlende Spalte wird nachgeholt, obwohl die Version sie vortäuscht', () async {
    final datei = await beschaedigteDatenbank(28);

    // Öffnen löst die Migration nach 29 aus.
    final db = AppDatabase(NativeDatabase(datei));
    final wert = await db.autoAnalyzeAfterImportEnabled();
    await db.close();

    expect(wert, isTrue, reason: 'Standardwert muss lesbar sein');

    final roh = sqlite.sqlite3.open(datei.path);
    final spalten = roh
        .select('PRAGMA table_info(app_settings)')
        .map((r) => r['name'] as String)
        .toSet();
    roh.close();
    expect(spalten, contains('auto_analyze_after_import'));
  });

  test('vorhandene Daten überleben die Reparatur', () async {
    final datei = await beschaedigteDatenbank(28);

    final db = AppDatabase(NativeDatabase(datei));
    final zeile = await db.watchAppSettings().first;
    await db.close();

    expect(zeile?.themeMode, 'dark',
        reason: 'die Reparatur darf bestehende Einstellungen nicht verwerfen');
  });

  test('eine bereits vollständige Datenbank wird nicht doppelt migriert', () async {
    // Frisch angelegt = vollständiges Schema. Ein erneutes Öffnen darf
    // nicht an "duplicate column" scheitern.
    final datei = File('${temp.path}/frisch.sqlite');
    var db = AppDatabase(NativeDatabase(datei));
    await db.setAutoAnalyzeAfterImport(false);
    await db.close();

    db = AppDatabase(NativeDatabase(datei));
    expect(await db.autoAnalyzeAfterImportEnabled(), isFalse);
    await db.close();
  });
}
