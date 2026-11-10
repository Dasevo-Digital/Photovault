import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:test/test.dart';

/// Beim Öffnen stapelt der Server nach, was eine neue Fassung zusätzlich
/// als dieselbe Aufnahme erkennt (#365) – und schreibt es fürs Abgleichen
/// mit, sonst sähen die Geräte die Paare weiter einzeln.
void main() {
  late Directory ordner;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_formatstapel_oeffnen_');
  });

  tearDown(() => ordner.delete(recursive: true));

  Future<void> lege(AppDatabase db, String id, String name) => db.insertAsset(
    AssetsCompanion.insert(
      id: id,
      originalFileName: name,
      relativePath: 'originals/$id',
      checksum: id,
      type: 'IMAGE',
      fileCreatedAt: DateTime(2025, 12, 6, 14, 3, 9),
      importedAt: DateTime(2026, 1, 1),
      dateiformat: Value(name.split('.').last.toLowerCase()),
      cameraModel: const Value('Canon EOS R10'),
    ),
  );

  Future<Set<String>> sichtbar(AppDatabase db) async => {
    for (final z
        in await db
            .customSelect('SELECT id FROM assets WHERE $rasterSichtbar')
            .get())
      z.read<String>('id'),
  };

  Future<int> aenderungen(AppDatabase db) async =>
      (await db
              .customSelect('SELECT count(*) AS n FROM pv_aenderungen')
              .getSingle())
          .read<int>('n');

  test('mit Schalter: die Paare kommen beim Öffnen zusammen', () async {
    final erst = await Bibliothek.oeffne(ordner);
    await lege(erst.db, 'r', 'IMG_0531.CR3');
    await lege(erst.db, 'j', 'IMG_0531-1bd0b0c6.jpg');
    await erst.db.setzeFormateStapeln(true);
    // Als hätten alle Geräte schon alles: Was jetzt ins Protokoll kommt,
    // kommt vom Öffnen.
    await erst.db.customStatement('DELETE FROM pv_aenderungen');
    await erst.schliesse();

    final dann = await Bibliothek.oeffne(ordner);
    expect(await sichtbar(dann.db), {'j'});
    expect((await dann.db.assetById('r'))!.stackId, isNotNull);
    expect(await aenderungen(dann.db), greaterThan(0));
    await dann.db.customStatement('DELETE FROM pv_aenderungen');
    await dann.schliesse();

    // Ein zweiter Lauf ändert nichts.
    final nochmal = await Bibliothek.oeffne(ordner);
    addTearDown(nochmal.schliesse);
    expect(await aenderungen(nochmal.db), 0);
  });

  test('ohne Schalter bleibt alles einzeln', () async {
    final erst = await Bibliothek.oeffne(ordner);
    await lege(erst.db, 'r', 'IMG_0532.CR3');
    await lege(erst.db, 'j', 'IMG_0532-d8566b0d.jpg');
    await erst.schliesse();
    final dann = await Bibliothek.oeffne(ordner);
    addTearDown(dann.schliesse);
    expect(await sichtbar(dann.db), {'r', 'j'});
  });
}
