// **Was der Start an der Datenbank abfragt, bevor das erste Bild steht.**
//
// `LibraryState.initialize()` wartet auf eine Reihe kleiner Abfragen.
// Fuenf davon lesen dieselbe eine Zeile aus `app_settings` - jede fuer
// sich, jede ueber die Isolat-Grenze.
//
//   PV_DB=/pfad/lese.sqlite flutter test tool/messe_startabfragen_test.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

Future<double> misst(String name, Future<void> Function() was,
    {int laeufe = 20}) async {
  for (var i = 0; i < 3; i++) {
    await was();
  }
  final uhr = Stopwatch()..start();
  for (var i = 0; i < laeufe; i++) {
    await was();
  }
  uhr.stop();
  final je = uhr.elapsedMicroseconds / laeufe / 1000;
  print('${name.padRight(42)} ${je.toStringAsFixed(3).padLeft(7)} ms');
  return je;
}

void main() {
  test('Startabfragen', () async {
    final quelle = Platform.environment['PV_DB'];
    if (quelle == null) {
      markTestSkipped('PV_DB nicht gesetzt');
      return;
    }
    // Erst oeffnen und wandern lassen, dann messen.
    final ordner = await Directory.systemTemp.createTemp('pv_start');
    final ziel = File('${ordner.path}/start.sqlite');
    await File(quelle).copy(ziel.path);
    addTearDown(() => ordner.deleteSync(recursive: true));

    final auf = Stopwatch()..start();
    final db = AppDatabase(NativeDatabase.createInBackground(ziel));
    await db.customSelect('SELECT 1 AS n').getSingle();
    auf.stop();
    addTearDown(db.close);
    print('oeffnen + wandern (Schema 78 -> ${db.schemaVersion}): '
        '${auf.elapsedMilliseconds} ms\n');

    var summe = 0.0;
    summe += await misst('faceSimilarityThresholdWert', () => db.faceSimilarityThresholdWert());
    summe += await misst('cartoSchluesselWert', () => db.cartoSchluesselWert());
    summe += await misst('eigeneKarteWert', () => db.eigeneKarteWert());
    summe += await misst('karteHochaufloesendWert', () => db.karteHochaufloesendWert());
    summe += await misst('maxGleichzeitigeAufgaben', () => db.maxGleichzeitigeAufgaben());
    summe += await misst('autoAnalyzeAfterImportEnabled',
        () => db.autoAnalyzeAfterImportEnabled());
    summe += await misst('resetStuckRunningRestoreJobs',
        () => db.resetStuckRunningRestoreJobs());
    print('\nSumme der Einzelabfragen: ${summe.toStringAsFixed(3)} ms');

    await misst('EINE Zeile app_settings, alles darin',
        () async => db.watchAppSettings().first);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
