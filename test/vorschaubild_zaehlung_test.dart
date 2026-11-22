import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/vorschaubild_zaehlung.dart';
import 'package:photo_vault/state/library_state.dart';

/// Merkt sich jede Leseabfrage.
class _Mitschnitt extends QueryInterceptor {
  final abfragen = <String>[];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    abfragen.add(statement);
    return executor.runSelect(statement, args);
  }
}

/// Die Zahl auf der Karte „Vorschaubilder“ der Aufgaben.
///
/// Sie entstand als Länge der Liste, die der Lauf abarbeitet: jede
/// Aufnahme mit allen Spalten geladen und Datei für Datei geprüft, bei
/// jedem Öffnen der Aufgaben im Isolat der Oberfläche. Jetzt zählt die
/// Datenbank, und die Dateien prüft ein eigenes Isolat – mit demselben
/// Ergebnis.
void main() {
  late Directory wurzel;
  late _Mitschnitt mitschnitt;
  late AppDatabase db;
  late StoragePaths paths;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_vorschauzahl_');
    mitschnitt = _Mitschnitt();
    db = AppDatabase(NativeDatabase.memory().interceptWith(mitschnitt));
    paths = await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'l')));
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> aufnahme(
    String id, {
    String typ = 'IMAGE',
    String? miniatur,
    String? vorschau,
    bool dateienDa = true,
    bool papierkorb = false,
  }) async {
    for (final pfad in [miniatur, vorschau]) {
      if (pfad == null || !dateienDa) continue;
      paths.absolute(pfad)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync([1]);
    }
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: id,
            type: typ,
            fileCreatedAt: DateTime(2024),
            importedAt: DateTime(2024),
            thumbnailRelativePath: Value(miniatur),
            previewRelativePath: Value(vorschau),
            isTrashed: Value(papierkorb),
          ),
        );
  }

  test('zählt dasselbe wie die Liste, ohne ganze Zeilen zu laden', () async {
    await aufnahme('ohne'); // kein Eintrag
    await aufnahme('gut', miniatur: 'thumbnails/gut.jpg');
    await aufnahme('weg', miniatur: 'thumbnails/weg.jpg', dateienDa: false);
    await aufnahme('video', typ: 'VIDEO', miniatur: 'thumbnails/v.jpg');
    await aufnahme(
      'video_gut',
      typ: 'VIDEO',
      miniatur: 'thumbnails/vg.jpg',
      vorschau: 'previews/vg.jpg',
    );
    await aufnahme('papierkorb', papierkorb: true);
    // Miniatur da, Vorschau eingetragen, aber ihre Datei fehlt.
    await aufnahme('halb', miniatur: 'thumbnails/h.jpg');
    await (db.update(db.assets)..where((t) => t.id.equals('halb'))).write(
      const AssetsCompanion(previewRelativePath: Value('previews/h.jpg')),
    );

    final library = LibraryState()
      ..db = db
      ..paths = paths;
    final liste = await library.aufnahmenOhneVorschaubild();
    expect(liste.map((a) => a.id).toSet(), {'ohne', 'weg', 'video', 'halb'});

    mitschnitt.abfragen.clear();
    expect(await zahlOhneVorschaubild(db, paths), liste.length);
    expect(
      mitschnitt.abfragen.where((s) => s.contains('SELECT * FROM "assets"')),
      isEmpty,
      reason: 'ganze Zeilen geladen: ${mitschnitt.abfragen}',
    );
  });

  test('verbunden zählen nur die fehlenden Einträge', () async {
    paths.beschaffe = (_) async {};
    await aufnahme('ohne');
    await aufnahme('weg', miniatur: 'thumbnails/weg.jpg', dateienDa: false);
    expect(await zahlOhneVorschaubild(db, paths), 1);
  });
}
