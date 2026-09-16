// **Was die Uebernahme aus dem Datenbank-Schnappschuss kostet.**
//
// `uebernimmAusSchnappschuss` schreibt jede Zeile mit einem eigenen
// `customInsert` - ohne Klammer, also je Zeile eine Transaktion mit
// eigenem fsync. Bei dieser Bibliothek sind das 18.386 Gesichter, 3.965
// Spurpunkte und alles Weitere. Gemessen auf einer DATEI, denn im
// Speicher gibt es kein fsync und damit nichts zu sehen.
//
//   PV_DB=/pfad/lese.sqlite flutter test tool/messe_schnappschuss_test.dart
// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('Schnappschuss zurueckspielen', () async {
    final quelle = Platform.environment['PV_DB'];
    if (quelle == null) {
      markTestSkipped('PV_DB nicht gesetzt');
      return;
    }
    final schnappschuss = File(quelle);

    final roh = sqlite3.open(quelle, mode: OpenMode.readOnly);
    final aufnahmen = roh
        .select('SELECT id, checksum FROM assets')
        .map((z) => (z['id'] as String, z['checksum'] as String))
        .toList();
    for (final t in ['faces', 'people', 'spurpunkte', 'reise_aufnahmen',
                     'aktivitaet_aufnahmen', 'develop_settings']) {
      final n = roh.select('SELECT count(*) AS n FROM "$t"').first['n'];
      print('  $t: $n');
    }
    roh.close();

    final temp = Directory.systemTemp.createTempSync('pv_schnapp_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final ziel = AppDatabase(NativeDatabase(File(p.join(temp.path, 'ziel.sqlite'))));
    addTearDown(ziel.close);
    final pfade = await StoragePaths.forTesting(Directory(p.join(temp.path, 'lib')));

    await ziel.batch((b) => b.insertAll(ziel.assets, [
          for (var i = 0; i < aufnahmen.length; i++)
            AssetsCompanion.insert(
              id: 'neu-$i',
              relativePath: 'originals/neu-$i.jpg',
              originalFileName: 'neu-$i.jpg',
              type: 'IMAGE',
              checksum: aufnahmen[i].$2,
              fileCreatedAt: DateTime(2024),
              importedAt: DateTime(2024),
            ),
        ]));

    final uhr = Stopwatch()..start();
    final zeilen =
        await BackupService(ziel, pfade).uebernimmAusSchnappschuss(schnappschuss);
    uhr.stop();
    print('\n$zeilen Zeilen in ${uhr.elapsedMilliseconds} ms '
        '(${(uhr.elapsedMicroseconds / zeilen / 1000).toStringAsFixed(3)} ms je Zeile)');
  }, timeout: const Timeout(Duration(minutes: 30)));
}
