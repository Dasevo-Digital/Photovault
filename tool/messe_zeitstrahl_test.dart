// Dasselbe mit dem ECHTEN Code, samt der Objekte, die dabei entstehen.
//
//   PV_DB=/pfad/lese.sqlite flutter test tool/messe_zeitstrahl_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/bildreihen.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('Gesamthoehe aller Monatsgruppen', () {
    final pfad = Platform.environment['PV_DB'];
    if (pfad == null) {
      markTestSkipped('PV_DB nicht gesetzt');
      return;
    }
    final db = sqlite3.open(pfad, mode: OpenMode.readOnly);
    final zeilen = db.select('''
      SELECT file_created_at, width_px, height_px FROM assets
      WHERE is_trashed = 0 AND is_locked = 0
      ORDER BY file_created_at DESC
    ''');
    db.close();

    final gruppen = <int, List<double>>{};
    for (final z in zeilen) {
      final t = DateTime.fromMillisecondsSinceEpoch(
          (z['file_created_at'] as int) * 1000);
      final w = z['width_px'] as int?, h = z['height_px'] as int?;
      gruppen.putIfAbsent(t.year * 100 + t.month, () => []).add(
          (w != null && h != null && h > 0) ? w / h : seitenverhaeltnisVorgabe);
    }
    // ignore: avoid_print
    print('${zeilen.length} Aufnahmen, ${gruppen.length} Monatsgruppen');

    double durchgang() {
      var summe = 0.0;
      for (final vs in gruppen.values) {
        summe += reihenGesamthoehe(
            bildreihen(
                seitenverhaeltnisse: vs,
                breite: 1200,
                zielhoehe: 160,
                abstand: 4),
            4);
      }
      return summe;
    }

    for (var i = 0; i < 5; i++) {
      durchgang();
    }
    final uhr = Stopwatch()..start();
    const laeufe = 50;
    for (var i = 0; i < laeufe; i++) {
      durchgang();
    }
    uhr.stop();
    final je = uhr.elapsedMicroseconds / laeufe / 1000;
    // ignore: avoid_print
    print('eine Gesamthoehe: ${je.toStringAsFixed(2)} ms  '
        '(zweimal je Bild: ${(je * 2).toStringAsFixed(2)} ms)');
  });
}
