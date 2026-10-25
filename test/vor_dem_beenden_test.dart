import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/state/library_state.dart';

/// Vor dem Beenden schliesst die Bibliothek ihre Datenbank (#215) – sonst
/// räumte die Dart-Laufzeit sie erst beim Herunterfahren über Finalizer ab,
/// und die App stürzte dabei in `sqlite3_finalize` ab.
void main() {
  test('schliesst die Datenbank, ein zweiter Aufruf tut nichts', () async {
    final temp = Directory.systemTemp.createTempSync('pv_beenden_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    final bib = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(temp.path, 'lib')),
      );
    bib.datenbankAlsGeoeffnet();
    expect(await db.select(db.assets).get(), isEmpty);

    await bib.vorDemBeenden();
    await expectLater(db.select(db.assets).get(), throwsA(anything));
    await bib.vorDemBeenden();
  });
}
