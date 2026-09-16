// **Wo die 70 ms der Zeitleisten-Abfrage wirklich hingehen.**
//
// Drei Verdaechtige: SQLite selbst, das Abbilden auf `AssetData` durch
// drift, und der Weg ueber die Isolat-Grenze. Vor einem Umbau gehoert
// gemessen, welcher davon zahlt.
//
//   PV_DB=/pfad/lese.sqlite flutter test tool/messe_spalten_test.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

/// Genau die Spalten, die ein Raster anfasst - aus den Aufrufern
/// zusammengesucht: Kachel, assetFormatLabel, assetHasLocation,
/// Panorama-Erkennung und der Zeitleistenbildschirm selbst.
const _schmal = 'id, type, original_file_name, relative_path, '
    'thumbnail_relative_path, file_created_at, duration_seconds, is_favorite, '
    'is_stack_cover, stack_id, stack_size, linked_asset_id, rating, '
    'width_px, height_px, latitude, longitude, camera_make, is_locked';

const _wo = 'WHERE is_trashed = 0 AND is_locked = 0 '
    "AND (type = 'IMAGE' OR linked_asset_id IS NULL) "
    'ORDER BY file_created_at DESC';

Future<double> misst(String name, Future<int> Function() was,
    {int laeufe = 10}) async {
  var n = 0;
  for (var i = 0; i < 3; i++) {
    n = await was();
  }
  final uhr = Stopwatch()..start();
  for (var i = 0; i < laeufe; i++) {
    await was();
  }
  uhr.stop();
  final je = uhr.elapsedMicroseconds / laeufe / 1000;
  print('${name.padRight(44)} ${je.toStringAsFixed(1).padLeft(6)} ms   ($n Zeilen)');
  return je;
}

void main() {
  test('Spalten, Abbildung, Isolat', () async {
    final pfad = Platform.environment['PV_DB'];
    if (pfad == null) {
      markTestSkipped('PV_DB nicht gesetzt');
      return;
    }

    for (final (art, oeffnen) in <(String, AppDatabase Function())>[
      ('im selben Isolat', () => AppDatabase(NativeDatabase(File(pfad)))),
      ('ueber die Isolat-Grenze',
          () => AppDatabase(NativeDatabase.createInBackground(File(pfad)))),
    ]) {
      final db = oeffnen();
      print('\n--- $art ---');
      await misst('SELECT * , auf AssetData abgebildet',
          () async => (await db.watchTimeline().first).length, laeufe: 5);
      await misst('SELECT * , roh (keine Abbildung)',
          () async => (await db.customSelect('SELECT * FROM assets $_wo').get())
              .length,
          laeufe: 5);
      await misst('19 Spalten, roh',
          () async =>
              (await db.customSelect('SELECT $_schmal FROM assets $_wo').get())
                  .length,
          laeufe: 5);
      await misst('nur id, roh',
          () async =>
              (await db.customSelect('SELECT id FROM assets $_wo').get()).length,
          laeufe: 5);
      await misst('nur count(*)',
          () async => (await db
                  .customSelect('SELECT count(*) AS n FROM assets $_wo')
                  .getSingle())
              .read<int>('n'),
          laeufe: 5);
      await db.close();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
