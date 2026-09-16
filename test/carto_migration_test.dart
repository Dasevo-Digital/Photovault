import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Die Migration 57 → 58: die Spalte für den CARTO-Schlüssel.
///
/// Der Schritt ist klein, aber er darf nichts umwerfen: `app_settings`
/// ist eine einzige Zeile mit inzwischen einem Dutzend Spalten, und an
/// ihr hängen Design, Sprache, Kartenansicht und die Gesichtsschwelle.
///
/// Geprüft wird an einer echten Datei, aus der die Spalte wieder
/// entfernt und deren Stempel zurückgesetzt wird – dann läuft die
/// Migration beim nächsten Öffnen von selbst.
void main() {
  late Directory temp;
  late File datei;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pv_carto_');
    datei = File('${temp.path}/library.sqlite');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<void> aufFassung57Zuruecksetzen() async {
    final roh = sqlite.sqlite3.open(datei.path);
    roh.execute('ALTER TABLE app_settings DROP COLUMN carto_schluessel');
    roh.execute('PRAGMA user_version = 57');
    roh.close();
  }

  Set<String> spalten() {
    final roh = sqlite.sqlite3.open(datei.path);
    final s = roh
        .select('PRAGMA table_info(app_settings)')
        .map((r) => r['name'] as String)
        .toSet();
    roh.close();
    return s;
  }

  test('die Spalte kommt dazu und die Nachbarn bleiben', () async {
    // Ein Bestand, wie ihn jemand nach Monaten Nutzung hat.
    var db = AppDatabase(NativeDatabase(datei));
    await db.setThemeMode('dark');
    await db.setzeKartenansicht('topo');
    await db.setFaceSimilarityThreshold(0.42);
    await db.close();

    await aufFassung57Zuruecksetzen();
    expect(spalten(), isNot(contains('carto_schluessel')));

    db = AppDatabase(NativeDatabase(datei));
    // Der erste Zugriff löst die Migration aus - nicht das Öffnen.
    final schluessel = await db.cartoSchluesselWert();
    final ansicht = await db.kartenansicht();
    final schwelle = await db.faceSimilarityThresholdWert();
    await db.close();

    expect(spalten(), contains('carto_schluessel'));
    // Null und nicht "": Die dunkle Karte soll nach der Migration OSM
    // zeichnen, nicht `…?key=` bei CARTO anfragen.
    expect(schluessel, isNull);
    expect(ansicht, 'topo', reason: 'die gemerkte Ansicht darf nicht kippen');
    expect(schwelle, closeTo(0.42, 0.0001));
  });

  test('ein eingetragener Schlüssel überlebt das nächste Öffnen', () async {
    var db = AppDatabase(NativeDatabase(datei));
    await db.setzeCartoSchluesselWert('abc123');
    await db.close();

    db = AppDatabase(NativeDatabase(datei));
    expect(await db.cartoSchluesselWert(), 'abc123');
    await db.close();
  });

  test('die Migration läuft auch zweimal ohne Schaden', () async {
    // Der Fall aus migration_repair_test: Ein Stempel, der die Spalte
    // vortäuscht. `_addColumnIfMissing` muss beides aushalten.
    var db = AppDatabase(NativeDatabase(datei));
    await db.setzeCartoSchluesselWert('abc123');
    await db.close();

    final roh = sqlite.sqlite3.open(datei.path);
    roh.execute('PRAGMA user_version = 57'); // Spalte bleibt stehen
    roh.close();

    db = AppDatabase(NativeDatabase(datei));
    expect(await db.cartoSchluesselWert(), 'abc123');
    await db.close();
  });
}
