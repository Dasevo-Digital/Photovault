// **Was eine Sammelbearbeitung kostet – lose oder in einer Klammer.**
//
// Mehrere Bildschirme ändern viele Aufnahmen auf einmal: Ort setzen,
// Datum setzen, aus dem Papierkorb holen. Geschrieben wird dabei je
// Aufnahme eine eigene Anweisung, und jede ist für SQLite eine eigene
// Übertragung – mit allem, was dazugehört.
//
// Gemessen wird auf einer **Datei**, nicht im Speicher: Im Speicher gibt
// es kein Sichern auf die Platte, und genau das ist der Preis.
//
//   flutter test tool/messe_sammelaenderung_test.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

void main() {
  test('Ortsnamen fuer viele Aufnahmen', () async {
    final ordner = Directory.systemTemp.createTempSync('pv_sammel');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase(File('${ordner.path}/lib.sqlite')));
    addTearDown(db.close);

    const n = 500;
    final ids = [for (var i = 0; i < n; i++) 'a$i'];
    await db.batch((b) {
      for (final id in ids) {
        b.insert(
          db.assets,
          AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'pruef-$id',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2024, 6, 3),
            importedAt: DateTime(2024),
            latitude: const Value(51.5),
            longitude: const Value(10.6),
          ),
        );
      }
    });

    final lose = Stopwatch()..start();
    for (final id in ids) {
      await db.setLocationNames(id,
          country: 'Germany', state: 'Lower Saxony', city: 'Goslar');
    }
    lose.stop();

    final klammer = Stopwatch()..start();
    await db.transaction(() async {
      for (final id in ids) {
        await db.setLocationNames(id,
            country: 'Germany', state: 'Harz', city: 'Wernigerode');
      }
    });
    klammer.stop();

    final eine = Stopwatch()..start();
    await db.setLocationNamesBulk(ids,
        country: 'Germany', state: 'Harz', city: 'Ilsenburg');
    eine.stop();

    print('$n Aufnahmen:');
    print('  lose        ${lose.elapsedMilliseconds} ms '
        '(${(lose.elapsedMicroseconds / n / 1000).toStringAsFixed(2)} ms je Foto)');
    print('  in einer Klammer ${klammer.elapsedMilliseconds} ms '
        '(${(klammer.elapsedMicroseconds / n / 1000).toStringAsFixed(2)} ms je Foto)');
    print('  eine Anweisung   ${eine.elapsedMilliseconds} ms');
    print('  Faktor Klammer ${(lose.elapsedMicroseconds / klammer.elapsedMicroseconds).toStringAsFixed(1)}, '
        'Faktor eine Anweisung '
        '${(lose.elapsedMicroseconds / eine.elapsedMicroseconds).toStringAsFixed(1)}');
  });
}
