import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:kern/abgleich/protokoll.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/embedding_codec.dart';
import 'package:kern/services/suchlauf.dart';
import 'package:test/test.dart';

/// Der Vorrat der Einbettungen (Issue #184): einmal geladen, danach aus
/// dem Speicher – und neu geladen, sobald sich etwas geändert hat, auch
/// wenn die Änderung als fertige Zeile aus dem Abgleich kommt.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    for (final id in ['a1', 'a2']) {
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.jpg',
              relativePath: 'originals/$id.jpg',
              checksum: 'p$id',
              type: 'IMAGE',
              fileCreatedAt: DateTime(2025),
              importedAt: DateTime(2026),
            ),
          );
    }
    await db.saveEmbedding('a1', Float32List.fromList([1, 0]));
  });
  tearDown(() => db.close());

  test('derselbe Vorrat, solange sich nichts ändert', () async {
    final erst = await db.einbettungenImSpeicher();
    expect(identical(await db.einbettungenImSpeicher(), erst), isTrue);
    await db.saveEmbedding('a2', Float32List.fromList([0, 1]));
    expect(
      (await db.einbettungenImSpeicher()).keys,
      unorderedEquals(['a1', 'a2']),
    );
  });

  test('eine Einbettung aus dem Abgleich ist danach zu finden', () async {
    expect((await db.einbettungenImSpeicher()).keys, ['a1']);
    // So kommt sie an einem verbundenen Gerät an: als Zeile, an den
    // Abfragen vorbei, die den Stand sonst hochzählen.
    await Protokoll(db).wendeAn([
      Zeilenstand(
        'image_embeddings',
        ['a2'],
        {
          'asset_id': 'a2',
          'vector': blobFromEmbeddingFloats(Float32List.fromList([0, 1])),
        },
      ),
    ]);
    expect(
      (await db.einbettungenImSpeicher()).keys,
      unorderedEquals(['a1', 'a2']),
      reason: 'vorher blieb der alte Vorrat stehen, solange er warm war',
    );
    final treffer = await suchlauf(
      db,
      text: 'x',
      art: Suchart.inhalt,
      vektor: Float32List.fromList([0, 1]),
    );
    expect(treffer.first.id, 'a2');
  });

  test('der Papierkorb eines anderen Geräts nimmt sie heraus', () async {
    await db.saveEmbedding('a2', Float32List.fromList([0, 1]));
    expect((await db.einbettungenImSpeicher()).keys, hasLength(2));
    final zeile = await (db.select(
      db.assets,
    )..where((t) => t.id.equals('a2'))).getSingle();
    final werte = zeile
        .toColumns(false)
        .map((k, v) => MapEntry(k, (v as dynamic).value));
    // Wie der Abgleich SQLite-Werte überträgt: Wahrheitswerte als Zahl,
    // Zeitpunkte als Sekunden.
    final roh = {
      for (final e in werte.entries)
        e.key: switch (e.value) {
          final bool b => b ? 1 : 0,
          final DateTime d => d.millisecondsSinceEpoch ~/ 1000,
          final v => v,
        },
    };
    await Protokoll(db).wendeAn([
      Zeilenstand('assets', ['a2'], {...roh, 'is_trashed': 1}),
    ]);
    expect((await db.einbettungenImSpeicher()).keys, ['a1']);
  });
}
