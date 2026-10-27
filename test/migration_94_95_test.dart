import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Schema 95: wie weit der Stammbaum reicht (#233).
///
/// Von Hand wie migration_90_91_test: Die drei Spalten kommen dazu, und
/// was vorher gemerkt war, bleibt.
void main() {
  test(
    'Migration 94 auf 95 legt die Spalten an, ohne etwas zu verlieren',
    () async {
      final dir = await Directory.systemTemp.createTemp('photo_vault_v94_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/library.sqlite');

      final initial = AppDatabase(NativeDatabase(file));
      await initial.setzeStammbaumZuletzt(ansicht: 'baum', person: 'p1');
      await initial.setzeLebensbaum(
        richtung: 'familie',
        stil: 'gold',
        generationen: 4,
        familieKreis: 'geschwister',
      );
      await initial.close();

      // Zurück auf den Stand von 94: die drei Spalten weg.
      final alt = sqlite.sqlite3.open(file.path);
      for (final spalte in [
        'stammbaum_oben',
        'stammbaum_unten',
        'stammbaum_kreis',
      ]) {
        alt.execute('ALTER TABLE app_settings DROP COLUMN $spalte');
      }
      alt.execute('PRAGMA user_version = 94');
      alt.close();

      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      expect(await db.stammbaumZuletzt(), (ansicht: 'baum', person: 'p1'));
      expect((await db.lebensbaumZuletzt()).familieKreis, 'geschwister');
      expect(await db.stammbaumUmfang(), (
        oben: null,
        unten: null,
        kreis: null,
      ));

      await db.setzeStammbaumUmfang(oben: 5, unten: 0, kreis: 'cousins');
      expect(await db.stammbaumUmfang(), (oben: 5, unten: 0, kreis: 'cousins'));
      // Die anderen Einstellungen derselben Zeile bleiben stehen.
      expect(await db.stammbaumZuletzt(), (ansicht: 'baum', person: 'p1'));
    },
  );
}
