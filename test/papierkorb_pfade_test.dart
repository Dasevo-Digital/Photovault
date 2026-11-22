import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/papierkorb_leeren.dart';
import 'package:kern/services/storage_paths.dart';

/// Zählt die Abfragen, die nach Pfaden in `assets` suchen.
class _Zaehler extends QueryInterceptor {
  var pfadabfragen = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('FROM assets WHERE relative_path IN')) {
      pfadabfragen++;
    }
    return executor.runSelect(statement, args);
  }
}

/// Welche Dateien eine bleibende Aufnahme noch braucht, prüft eine
/// einzige Abfrage – nicht eine je 500 Pfade, jede ein voller Durchlauf
/// über die Aufnahmen (#435).
void main() {
  test('viele Pfade, ein Durchlauf; was noch gebraucht wird, bleibt', () async {
    final ordner = await Directory.systemTemp.createTemp('pv_pfade_');
    addTearDown(() => ordner.delete(recursive: true));
    final ablage = await StoragePaths.oeffne(ordner);
    final zaehler = _Zaehler();
    final db = AppDatabase(NativeDatabase.memory().interceptWith(zaehler));
    addTearDown(db.close);
    await db.insertAsset(
      AssetsCompanion.insert(
        id: 'bleibt',
        originalFileName: 'bleibt.jpg',
        relativePath: 'originals/bleibt.jpg',
        thumbnailRelativePath: const Value('thumbnails/geteilt.jpg'),
        checksum: 'bleibt',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2026),
        importedAt: DateTime(2026),
      ),
    );
    final pfade = {
      'originals/bleibt.jpg',
      'thumbnails/geteilt.jpg',
      for (var i = 0; i < 1200; i++) 'thumbnails/weg$i.jpg',
    };
    for (final p in ['originals/bleibt.jpg', 'thumbnails/geteilt.jpg']) {
      ablage.absolute(p)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('x');
    }
    for (var i = 0; i < 1200; i += 400) {
      ablage.absolute('thumbnails/weg$i.jpg').writeAsStringSync('x');
    }

    await loescheVerwaisteDateien(db, ablage, pfade);

    expect(zaehler.pfadabfragen, 1);
    expect(ablage.absolute('originals/bleibt.jpg').existsSync(), isTrue);
    expect(ablage.absolute('thumbnails/geteilt.jpg').existsSync(), isTrue);
    for (var i = 0; i < 1200; i += 400) {
      expect(ablage.absolute('thumbnails/weg$i.jpg').existsSync(), isFalse);
    }
  });
}
