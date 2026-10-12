import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Schema 91: wie weit der Lebensbaum „Familie" reicht.
///
/// Von Hand aus demselben Grund wie migration_86_87_test: Der Test, den
/// `drift_dev make-migrations` erzeugt, kann die Vorgabewerte dieses
/// Schemas nicht auswerten.
void main() {
  test(
    'Migration 90 auf 91 legt die Spalten an, ohne etwas zu verlieren',
    () async {
      final dir = await Directory.systemTemp.createTemp('photo_vault_v90_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/library.sqlite');

      final initial = AppDatabase(NativeDatabase(file));
      await initial.setzeLebensbaum(
        richtung: 'familie',
        stil: 'gold',
        generationen: 5,
      );
      await initial.close();

      // Zurück auf den Stand von 90: die drei Spalten weg.
      final alt = sqlite.sqlite3.open(file.path);
      for (final spalte in [
        'lebensbaum_familie_oben',
        'lebensbaum_familie_unten',
        'lebensbaum_familie_kreis',
      ]) {
        alt.execute('ALTER TABLE app_settings DROP COLUMN $spalte');
      }
      alt.execute('PRAGMA user_version = 90');
      alt.close();

      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      // Was vorher gemerkt war, ist noch da, und die Familie hat die
      // Vorgabe.
      final vorher = await db.lebensbaumZuletzt();
      expect(vorher.richtung, 'familie');
      expect(vorher.stil, 'gold');
      expect(vorher.generationen, 5);
      expect(vorher.familieOben, isNull);
      expect(vorher.familieUnten, isNull);
      expect(vorher.familieKreis, isNull);

      await db.setzeLebensbaum(
        richtung: 'familie',
        stil: 'gold',
        generationen: 5,
        familieOben: 2,
        familieUnten: 0,
        familieKreis: 'linie',
      );
      final gemerkt = await db.lebensbaumZuletzt();
      expect(gemerkt.familieOben, 2);
      expect(gemerkt.familieUnten, 0);
      expect(gemerkt.familieKreis, 'linie');

      // Wer die Familie nicht nennt, lässt ihren Stand stehen.
      await db.setzeLebensbaum(
        richtung: 'vorfahren',
        stil: 'gold',
        generationen: 4,
      );
      final danach = await db.lebensbaumZuletzt();
      expect(danach.richtung, 'vorfahren');
      expect(danach.familieOben, 2);
      expect(danach.familieKreis, 'linie');
    },
  );
}
