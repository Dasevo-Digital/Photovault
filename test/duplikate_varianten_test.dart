import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/duplikatsuche.dart';

/// Varianten sind keine Duplikate (#249): Ein Stapel sucht nur mit seiner
/// Hauptversion mit.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> aufnahme(String id, {int breite = 4000}) async {
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/2026/01/$id.jpg',
            checksum: 'c_$id',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 1, 1),
            importedAt: DateTime(2026, 1, 1),
            widthPx: Value(breite),
            heightPx: const Value(3000),
          ),
        );
    await db.saveEmbedding(id, Float32List.fromList(List.filled(16, 0.25)));
  }

  test('zwei Varianten eines Stapels sind keine Gruppe', () async {
    await aufnahme('haupt');
    await aufnahme('original');
    await db.createStack(variantenstapelId('v1'), [
      'haupt',
      'original',
    ], 'haupt');

    final e = await sucheDuplikate(db, 0.9);
    expect(e.gruppen, isEmpty);
  });

  test('ein drittes Foto zieht die verdeckte Variante nicht hinein', () async {
    await aufnahme('haupt');
    await aufnahme('original');
    await aufnahme('kopie', breite: 1000);
    await db.createStack(variantenstapelId('v1'), [
      'haupt',
      'original',
    ], 'haupt');

    final e = await sucheDuplikate(db, 0.9);
    expect(e.gruppen, hasLength(1));
    final g = e.gruppen.single;
    expect(g.aufnahmen.map((a) => a.id), unorderedEquals(['haupt', 'kopie']));
    expect(g.loeschbar.map((a) => a.id), ['kopie']);
  });

  test('eine Serie bleibt durchsuchbar', () async {
    await aufnahme('erstes');
    await aufnahme('zweites');
    await db.createStack('serie-1', ['erstes', 'zweites'], 'erstes');

    final e = await sucheDuplikate(db, 0.9);
    expect(e.gruppen, hasLength(1));
  });
}
