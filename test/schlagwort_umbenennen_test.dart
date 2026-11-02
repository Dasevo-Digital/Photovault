import 'package:drift/drift.dart' show InsertMode;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';

/// Ein Schlagwort umbenennen (#273): an allen Aufnahmen zugleich, mit
/// derselben Kennung.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    for (final id in ['a1', 'a2']) {
      await db.insertAsset(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'c$id',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2025),
          importedAt: DateTime(2026),
        ),
      );
    }
    await db.fuehreAus(const SchlagwortAnheften(['a1', 'a2'], 'Strand'));
    await db.fuehreAus(const SchlagwortAnheften(['a2'], 'Hafen'));
  });

  tearDown(() => db.close());

  Future<TagData> schlagwort(String name) =>
      (db.select(db.tags)..where((t) => t.name.equals(name))).getSingle();

  test('neuer Name an allen Aufnahmen, die Kennung bleibt', () async {
    final vorher = await schlagwort('Strand');

    await db.fuehreAus(SchlagwortUmbenennen(vorher.id, '  Meer '));

    final nachher = await schlagwort('Meer');
    expect(nachher.id, vorher.id);
    final an = await (db.select(
      db.assetTags,
    )..where((t) => t.tagId.equals(vorher.id))).get();
    expect(an.map((z) => z.assetId), unorderedEquals(['a1', 'a2']));
  });

  test('einen vergebenen Namen gibt es nicht zweimal', () async {
    final strand = await schlagwort('Strand');
    await expectLater(
      db.fuehreAus(SchlagwortUmbenennen(strand.id, 'Hafen')),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'pv_schlagwort_vorhanden',
        ),
      ),
    );
    expect((await schlagwort('Strand')).id, strand.id);
  });

  test('das Vokabular der Bilderkennung zieht mit', () async {
    await db
        .into(db.aiTagVocabulary)
        .insert(
          AiTagVocabularyCompanion.insert(term: 'Strand'),
          mode: InsertMode.insertOrIgnore,
        );
    final strand = await schlagwort('Strand');

    await db.fuehreAus(SchlagwortUmbenennen(strand.id, 'Meer'));

    final begriffe = [
      for (final v in await db.select(db.aiTagVocabulary).get()) v.term,
    ];
    expect(begriffe, contains('Meer'));
    expect(begriffe, isNot(contains('Strand')));
    expect(
      await (db.select(
        db.tags,
      )..where((t) => t.name.equals('Strand'))).getSingleOrNull(),
      isNull,
    );
  });
}
