// **Was der Gesundheitsbildschirm und der Rueckblick kosten.**
//
// Beide haben in 3.13.0/3.14.0 Abfragen dazubekommen: drei Karten mehr,
// und der Rueckblick fragt bei leerem Tag ein zweites Mal ueber die
// ganze Tabelle. Gemessen wird an einer echten Bibliothek, sonst sagt
// die Zahl nichts.
//
//   PV_DB=/pfad/kopie.sqlite flutter test tool/messe_zustand_und_rueckblick_test.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

Future<double> misst(String name, Future<void> Function() was,
    {int laeufe = 10}) async {
  for (var i = 0; i < 2; i++) {
    await was();
  }
  final uhr = Stopwatch()..start();
  for (var i = 0; i < laeufe; i++) {
    await was();
  }
  uhr.stop();
  final je = uhr.elapsedMicroseconds / laeufe / 1000;
  print('${name.padRight(46)} ${je.toStringAsFixed(1).padLeft(8)} ms');
  return je;
}

void main() {
  final pfad = Platform.environment['PV_DB'];
  late AppDatabase db;

  setUpAll(() {
    if (pfad == null) return;
    db = AppDatabase(NativeDatabase(File(pfad)));
  });
  tearDownAll(() async {
    if (pfad != null) await db.close();
  });

  test('Gesundheitsbildschirm', () async {
    if (pfad == null) {
      print('PV_DB nicht gesetzt.');
      return;
    }
    print('\n--- Zustand der Bibliothek, je Abfrage');
    var summe = 0.0;
    summe += await misst('databaseQuickCheck', () => db.databaseQuickCheck());
    summe += await misst('backupSettingsRow', () => db.backupSettingsRow());
    summe += await misst('countNotAutoBackedUp', () => db.countNotAutoBackedUp());
    summe += await misst("countAssetsOfType('IMAGE')", () => db.countAssetsOfType('IMAGE'));
    summe += await misst("countAssetsOfType('VIDEO')", () => db.countAssetsOfType('VIDEO'));
    summe += await misst('countOrtsvorschlagskandidaten', () => db.countOrtsvorschlagskandidaten());
    summe += await misst('countOffeneGesichter', () => db.countOffeneGesichter());
    summe += await misst('countAuffaelligeAufnahmedaten  (neu)', () => db.countAuffaelligeAufnahmedaten());
    summe += await misst('countVideoZweitblick  (neu)', () => db.countVideoZweitblick());
    summe += await misst('countVorschlaege  (neu)', () => db.countVorschlaege());
    print('${'Summe der Abfragen'.padRight(46)} ${summe.toStringAsFixed(1).padLeft(8)} ms');

    print('\n--- nebenlaeufig, so wie der Bildschirm es tut');
    await misst('alle elf zusammen (Future.wait)', () async {
      await Future.wait<Object?>([
        db.databaseQuickCheck(),
        db.backupSettingsRow(),
        db.countNotAutoBackedUp(),
        db.countAssetsOfType('IMAGE'),
        db.countAssetsOfType('VIDEO'),
        db.countOrtsvorschlagskandidaten(),
        db.countOffeneGesichter(),
        db.countAuffaelligeAufnahmedaten(),
        db.countVideoZweitblick(),
        db.countVorschlaege(),
      ]);
    }, laeufe: 5);
  }, timeout: const Timeout(Duration(minutes: 15)));

  test('Rueckblick', () async {
    if (pfad == null) return;
    print('\n--- Erkunden, oberster Abschnitt');
    // Ein Tag mit Treffern und einer ohne - der zweite ist der teure.
    await misst('assetsOnThisDay (Tag mit Treffern)',
        () => db.assetsOnThisDay(DateTime(2026, 8, 15)));
    await misst('assetsOnThisDay (leerer Tag)',
        () => db.assetsOnThisDay(DateTime(2026, 9, 12)));
    await misst('assetsInDiesemMonat (Rueckfall)',
        () => db.assetsInDiesemMonat(DateTime(2026, 9, 12)));

    print('\n--- die uebrigen Streifen');
    await misst('watchPeople().first', () => db.watchPeople().first);
    await misst('watchReisen().first', () => db.watchReisen().first);
    await misst('watchAktivitaeten().first', () => db.watchAktivitaeten().first);
    await misst('watchAlbums().first', () => db.watchAlbums().first);
    await misst('watchTimeline(limit: 40).first',
        () => db.watchTimeline(limit: 40).first);
  }, timeout: const Timeout(Duration(minutes: 15)));
}
