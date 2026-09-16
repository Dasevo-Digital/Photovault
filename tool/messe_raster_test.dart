// Was das Raster bei JEDEM Neuaufbau tut - an der echten Bibliothek.
//
//   PV_DB=/pfad/lese.sqlite flutter test tool/messe_raster_test.dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/db/rasterzeile.dart';
import 'package:photo_vault/widgets/month_grouped_asset_grid.dart';

void main() {
  test('Gruppieren je Neuaufbau', () async {
    final pfad = Platform.environment['PV_DB'];
    if (pfad == null) {
      markTestSkipped('PV_DB nicht gesetzt');
      return;
    }
    final db = AppDatabase(NativeDatabase(File(pfad)));
    addTearDown(db.close);
    final alle = await db.alleAufnahmen();
    // ignore: avoid_print
    print('${alle.length} Aufnahmen');

    for (final n in [600, 1800, alle.length]) {
      final teil = alle.take(n).toList();
      for (var i = 0; i < 5; i++) {
        monatsgruppen([for (final x in teil) Rasterzeile.aus(x)]);
      }
      final uhr = Stopwatch()..start();
      const laeufe = 50;
      for (var i = 0; i < laeufe; i++) {
        monatsgruppen([for (final x in teil) Rasterzeile.aus(x)]);
      }
      uhr.stop();
      // ignore: avoid_print
      print('$n Aufnahmen: '
          '${(uhr.elapsedMicroseconds / laeufe / 1000).toStringAsFixed(2)} ms '
          'je Neuaufbau');
    }
  });
}
