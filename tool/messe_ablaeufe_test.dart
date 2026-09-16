// Wiederkehrende Arbeit an der echten Bibliothek.
//
//   PV_DB=/pfad/lese.sqlite flutter test tool/messe_ablaeufe_test.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

Future<double> misst(String name, Future<void> Function() was,
    {int laeufe = 10}) async {
  for (var i = 0; i < 3; i++) {
    await was();
  }
  final uhr = Stopwatch()..start();
  for (var i = 0; i < laeufe; i++) {
    await was();
  }
  uhr.stop();
  final je = uhr.elapsedMicroseconds / laeufe / 1000;
  print('${name.padRight(38)} ${je.toStringAsFixed(1)} ms');
  return je;
}

void main() {
  test('Abfragen der Bibliothek', () async {
    final pfad = Platform.environment['PV_DB'];
    if (pfad == null) {
      markTestSkipped('PV_DB nicht gesetzt');
      return;
    }
    final db = AppDatabase(NativeDatabase(File(pfad)));
    addTearDown(db.close);

    await misst('Zeitleiste voll, Startfenster 600',
        () => db.watchTimeline(limit: 600).first);
    await misst('Zeitleiste voll, ganze Bibliothek',
        () => db.watchTimeline().first, laeufe: 5);
    await misst('Rasterzeilen, Startfenster 600',
        () => db.watchRasterzeilen(limit: 600).first);
    await misst('Rasterzeilen, ganze Bibliothek',
        () => db.watchRasterzeilen().first, laeufe: 5);
    await misst('alleAufnahmen (Fotowaehler)',
        () => db.alleAufnahmen(), laeufe: 5);
    await misst('verortete Aufnahmen (Karte)',
        () => db.assetsWithLocation(), laeufe: 5);
    await misst('Alben', () => db.watchAlbums().first);
    await misst('Personen', () => db.watchPeople().first);
    await misst('Einbettungen (KI-Suche)',
        () => db.allEmbeddings(), laeufe: 3);
    await misst('Papierkorb', () => db.watchTrash().first, laeufe: 5);
    await misst('Jahreszahlen', () => db.watchAssetCountsByYear().first);
  });
}
