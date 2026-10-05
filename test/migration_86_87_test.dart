import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Schema 87: der gemerkte Stand des Lebensbaums.
///
/// Von Hand und nicht mit dem Test, den `drift_dev make-migrations`
/// erzeugt: Der kann die Vorgabewerte dieses Schemas nicht auswerten (die
/// Datenbank lässt sich für den Export nicht ausserhalb von Flutter
/// starten) und schreibt sie als Dart-Ausdrücke ab, die in seinen Dateien
/// unbekannt sind. Der Schemastand selbst liegt trotzdem unter
/// drift_schemas/.
void main() {
  test(
    'Migration 86 auf 87 legt die Spalten an, ohne etwas zu verlieren',
    () async {
      final dir = await Directory.systemTemp.createTemp('photo_vault_v86_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/library.sqlite');

      final initial = AppDatabase(NativeDatabase(file));
      await initial.setzeStammbaumZuletzt(ansicht: 'faecher', person: 'p1');
      await initial.close();

      // Zurück auf den Stand von 86: die drei Spalten weg.
      final alt = sqlite.sqlite3.open(file.path);
      for (final spalte in [
        'lebensbaum_richtung',
        'lebensbaum_stil',
        'lebensbaum_generationen',
      ]) {
        alt.execute('ALTER TABLE app_settings DROP COLUMN $spalte');
      }
      alt.execute('PRAGMA user_version = 86');
      alt.close();

      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      // Was vorher gemerkt war, ist noch da.
      final zuletzt = await db.stammbaumZuletzt();
      expect(zuletzt.ansicht, 'faecher');
      expect(zuletzt.person, 'p1');
      // Der Lebensbaum hat noch nichts gemerkt …
      final leer = await db.lebensbaumZuletzt();
      expect(leer.richtung, isNull);
      expect(leer.stil, isNull);
      expect(leer.generationen, isNull);
      // … und kann es jetzt.
      await db.setzeLebensbaum(
        richtung: 'nachkommen',
        stil: 'wappen',
        generationen: 5,
      );
      final gemerkt = await db.lebensbaumZuletzt();
      expect(gemerkt.richtung, 'nachkommen');
      expect(gemerkt.stil, 'wappen');
      expect(gemerkt.generationen, 5);
      // Und das Merken des Lebensbaums lässt den übrigen Stand stehen.
      expect((await db.stammbaumZuletzt()).person, 'p1');
    },
  );
}
