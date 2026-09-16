// **Was das Zurueckspielen einer Sicherung an der Datenbank kostet.**
//
// `_applyMetadataExport` schreibt je Aufnahme bis zu sieben einzelne
// Anweisungen (Name, Favorit, Beschreibung, Bewertung, Farbe, Ort,
// Ortsnamen) und je Schlagwort noch einmal zwei (`ensureTag` +
// Einfuegen). Jede davon laeuft ohne Klammer, also als eigene
// Transaktion mit eigenem fsync. Hier steht die Frage: Wie teuer ist
// das, und was bringt eine Klammer darum?
//
//   PV_DB=/pfad/lese.sqlite flutter test tool/messe_sicherung_test.dart
// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

/// Genau die Folge, die `_applyMetadataExport` je Eintrag abarbeitet.
Future<void> eintrag(AppDatabase db, String id, int n) async {
  await db.setOriginalFileName(id, 'IMG_$n.jpg');
  await db.setFavorite(id, true);
  await db.setDescription(id, 'aus der Sicherung $n');
  await db.setRating(id, (n % 5) + 1);
  await db.setColorLabel(id, 'gruen');
  await db.setLocation(id, 51.8 + n / 10000, 10.6 + n / 10000);
  await db.setLocationNames(id,
      country: 'Deutschland', state: 'Sachsen-Anhalt', city: 'Ilsenburg');
  for (final tag in ['Wald', 'Berg', 'Sicherung$n']) {
    await db.tagAsset(id, tag);
  }
}

void main() {
  test('Sicherung zurueckspielen: mit und ohne Klammer', () async {
    final quelle = Platform.environment['PV_DB'];
    if (quelle == null) {
      markTestSkipped('PV_DB nicht gesetzt');
      return;
    }

    // Auf einer DATEI messen, nicht im Speicher: Ohne fsync gibt es
    // keinen Unterschied zu sehen, und genau der ist die Frage.
    final ordner = await Directory.systemTemp.createTemp('pv_sicherung');
    Future<(AppDatabase, File)> frisch() async {
      final ziel = File('${ordner.path}/${DateTime.now().microsecondsSinceEpoch}.sqlite');
      await File(quelle).copy(ziel.path);
      return (AppDatabase(NativeDatabase(ziel)), ziel);
    }

    for (final anzahl in [200, 1000]) {
      print('\n=== $anzahl Aufnahmen ===');

      {
        final (db, _) = await frisch();
        final ids = (await db.customSelect(
                'SELECT id FROM assets LIMIT $anzahl')
            .get()).map((z) => z.read<String>('id')).toList();
        final uhr = Stopwatch()..start();
        for (var i = 0; i < ids.length; i++) {
          await eintrag(db, ids[i], i);
        }
        uhr.stop();
        print('ohne Klammer (heute)   ${uhr.elapsedMilliseconds.toString().padLeft(6)} ms');
        await db.close();
      }

      {
        final (db, _) = await frisch();
        final ids = (await db.customSelect(
                'SELECT id FROM assets LIMIT $anzahl')
            .get()).map((z) => z.read<String>('id')).toList();
        final uhr = Stopwatch()..start();
        await db.transaction(() async {
          for (var i = 0; i < ids.length; i++) {
            await eintrag(db, ids[i], i);
          }
        });
        uhr.stop();
        print('eine Klammer darum     ${uhr.elapsedMilliseconds.toString().padLeft(6)} ms');
        await db.close();
      }
    }
    await ordner.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 20)));
}
