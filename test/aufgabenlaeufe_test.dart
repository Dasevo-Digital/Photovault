import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Issue #15: Nach einem vollständigen Lauf zählen die Aufgaben ohne
/// eigene Notiz je Aufnahme nur noch, was seitdem dazukam.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> aufnahme(String id, String typ, DateTime importiert) => db
      .into(db.assets)
      .insert(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.${typ == 'VIDEO' ? 'mov' : 'jpg'}',
          relativePath: 'originals/$id',
          checksum: 'pruef-$id',
          type: typ,
          fileCreatedAt: DateTime(2020),
          importedAt: importiert,
          cameraMake: const Value(null),
        ),
      );

  test('ohne Lauf alles, nach dem Lauf nur Neues', () async {
    await aufnahme('v1', 'VIDEO', DateTime(2026, 1, 1));
    await aufnahme('v2', 'VIDEO', DateTime(2026, 1, 2));
    await aufnahme('f1', 'IMAGE', DateTime(2026, 1, 3));
    expect(await db.aufgabeFertigAm('dateiarten'), isNull);
    expect(await db.countAssetsOfType('VIDEO'), 2);

    await db.merkeAufgabenlauf('dateiarten');
    final seit = (await db.aufgabeFertigAm('dateiarten'))!;
    expect(await db.countAssetsOfType('VIDEO', importiertNach: seit), 0);
    expect(
      await db.countUnlinkedAssetsOfType('IMAGE', importiertNach: seit),
      0,
    );
    expect(await db.countCameraMetadataBackfill(importiertNach: seit), 0);

    // Ein neuer Import ist wieder Arbeit.
    await aufnahme('v3', 'VIDEO', seit.add(const Duration(seconds: 1)));
    expect(await db.countAssetsOfType('VIDEO', importiertNach: seit), 1);
    expect(await db.countCameraMetadataBackfill(importiertNach: seit), 1);
    expect(await db.countXmpExport(importiertNach: seit), 1);
  });

  test('ein zweiter Lauf schiebt den Zeitpunkt vor', () async {
    await db.merkeAufgabenlauf('xmp');
    final erster = (await db.aufgabeFertigAm('xmp'))!;
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await db.merkeAufgabenlauf('xmp');
    expect((await db.aufgabeFertigAm('xmp'))!.isAfter(erster), isTrue);
    expect(await db.aufgabeFertigAm('rendern'), isNull);
  });

  test('Migration 89 auf 90 legt die Tabelle an', () async {
    final dir = await Directory.systemTemp.createTemp('photo_vault_v89_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/library.sqlite');
    final initial = AppDatabase(NativeDatabase(file));
    await initial.merkeErinnerung(
      id: 'e',
      titel: 'e',
      tag: DateTime(2020),
      assetIds: const [],
    );
    await initial.close();

    final alt = sqlite.sqlite3.open(file.path);
    alt.execute('DROP TABLE aufgabenlaeufe');
    alt.execute('PRAGMA user_version = 89');
    alt.close();

    final neu = AppDatabase(NativeDatabase(file));
    addTearDown(neu.close);
    expect(await neu.alleGemerktenErinnerungen(), hasLength(1));
    expect(await neu.aufgabeFertigAm('dateiarten'), isNull);
    await neu.merkeAufgabenlauf('dateiarten');
    expect(await neu.aufgabeFertigAm('dateiarten'), isNotNull);
  });
}
