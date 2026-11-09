import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Schema 96: der Schalter für Stapel aus mehreren Dateiformaten (#361).
void main() {
  test('Migration 95 auf 96 legt die Spalte an, Vorgabe aus', () async {
    final dir = await Directory.systemTemp.createTemp('photo_vault_v95_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/library.sqlite');

    final initial = AppDatabase(NativeDatabase(file));
    await initial.setAutoAnalyzeAfterImport(false);
    await initial.close();

    final alt = sqlite.sqlite3.open(file.path);
    alt.execute('ALTER TABLE app_settings DROP COLUMN formate_stapeln');
    alt.execute('PRAGMA user_version = 95');
    alt.close();

    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    expect(await db.autoAnalyzeAfterImportEnabled(), isFalse);
    expect(await db.formateStapeln(), isFalse);
    await db.setzeFormateStapeln(true);
    expect(await db.formateStapeln(), isTrue);
  });
}
