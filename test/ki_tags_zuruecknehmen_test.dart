import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';

/// **Zurücknehmen, ohne die eigene Arbeit mitzunehmen.**
///
/// Anlass: 94.040 KI-Schlagwörter gegen 3 von Hand vergebene. Ein Knopf,
/// der reinen Tisch macht, ist nur dann vertretbar, wenn er die drei
/// stehen lässt – und genau dafür steht seit Schema 56 die Herkunft in
/// `asset_tags`.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> aufnahme(String id, {bool durchgesehen = true}) => db
      .into(db.assets)
      .insert(
        AssetsCompanion.insert(
          id: id,
          relativePath: 'originals/$id.jpg',
          originalFileName: '$id.jpg',
          type: 'IMAGE',
          checksum: 'pruef-$id',
          fileCreatedAt: DateTime(2024),
          importedAt: DateTime(2024),
          aiTagsScanned: Value(durchgesehen),
        ),
      );

  test('nimmt die KI-Schlagwörter und lässt die eigenen stehen', () async {
    await aufnahme('a');
    await aufnahme('b');
    await db.tagAsset('a', 'Strand', quelle: Tagquelle.ki);
    await db.tagAsset('a', 'Hochzeit', quelle: Tagquelle.ki);
    await db.tagAsset('a', 'Oma'); // von Hand
    await db.tagAsset('b', 'Bildschirmfoto', quelle: Tagquelle.ki);

    expect(await db.kiTagAnzahl(), 3);
    expect(await db.nimmKiTagsZurueck(), 3);
    expect(await db.kiTagAnzahl(), 0);

    final uebrig = await db.select(db.assetTags).get();
    expect(uebrig.length, 1);
    expect(uebrig.single.assetId, 'a');
    expect(uebrig.single.quelle, Tagquelle.hand);
  });

  test('ein von Hand übernommener Begriff fällt nicht mit', () async {
    await aufnahme('a');
    // Erst schlägt die Bilderkennung vor, dann übernimmt der Nutzer.
    await db.tagAsset('a', 'Strand', quelle: Tagquelle.ki);
    await db.tagAsset('a', 'Strand');
    await db.nimmKiTagsZurueck();
    final uebrig = await db.select(db.assetTags).get();
    expect(uebrig.length, 1, reason: 'die Übernahme muss bleiben');
  });

  test('löscht den Vermerk, sonst käme nie etwas Neues', () async {
    await aufnahme('a');
    await db.tagAsset('a', 'Strand', quelle: Tagquelle.ki);
    await db.nimmKiTagsZurueck();
    final a = await (db.select(
      db.assets,
    )..where((t) => t.id.equals('a'))).getSingle();
    expect(
      a.aiTagsScanned,
      isFalse,
      reason: 'mit dem Vermerk überspringt die Bilderkennung das Foto',
    );
  });

  test(
    'danach sind auch Fotos mit eigenen Schlagwörtern wieder offen',
    () async {
      // KI-079: „KI-Tags“ zählte 1 statt 2 offene Fotos – das Foto mit dem
      // von Hand vergebenen „Oma“ galt nicht als offen und bekam nie wieder
      // KI-Schlagwörter.
      await aufnahme('a');
      await aufnahme('b');
      await db.tagAsset('a', 'Strand', quelle: Tagquelle.ki);
      await db.tagAsset('a', 'Oma');
      await db.tagAsset('b', 'Wald', quelle: Tagquelle.ki);
      expect(await db.countAiTagging(onlyUntagged: true), 0);

      await db.nimmKiTagsZurueck();

      expect(await db.countAiTagging(onlyUntagged: true), 2);
      expect(
        (await db.assetsForAiTagging(onlyUntagged: true)).map((a) => a.id),
        unorderedEquals(['a', 'b']),
      );
    },
  );

  test('räumt Schlagwörter weg, an denen nichts mehr hängt', () async {
    await aufnahme('a');
    await db.tagAsset('a', 'Geburtstagstorte', quelle: Tagquelle.ki);
    await db.tagAsset('a', 'Oma');
    await db.nimmKiTagsZurueck();
    final namen = [for (final t in await db.select(db.tags).get()) t.name];
    expect(namen, [
      'Oma',
    ], reason: 'sonst stünde die Suchliste voll leerer Begriffe');
  });

  test('ein von Hand angelegtes Schlagwort ohne Foto bleibt stehen', () async {
    // KI-081: „Leer“ hängt an keinem Foto, nur an einer Regel. Früher
    // löschte das Zurücknehmen jedes Schlagwort ohne Foto, und die Regel
    // verwies danach auf eine Kennung ohne Schlagwort.
    await aufnahme('a');
    await db.tagAsset('a', 'Strand', quelle: Tagquelle.ki);
    final leer = await db.ensureTag('Leer');
    final ohneAlles = await db.ensureTag('Ohne alles');
    await db
        .into(db.automationRules)
        .insert(
          AutomationRulesCompanion.insert(
            id: 'r1',
            name: 'Regel Leer',
            triggerType: 'location',
          ),
        );
    await db
        .into(db.automationRuleTags)
        .insert(AutomationRuleTagsCompanion.insert(ruleId: 'r1', tagId: leer));

    await db.nimmKiTagsZurueck();

    final ids = [for (final t in await db.select(db.tags).get()) t.id];
    expect(ids, containsAll([leer, ohneAlles]));
    expect(await db.select(db.automationRuleTags).get(), hasLength(1));
  });

  test('ein KI-Schlagwort, das eine Regel setzt, bleibt stehen', () async {
    await aufnahme('a');
    await db.tagAsset('a', 'Strand', quelle: Tagquelle.ki);
    final strand = await db.ensureTag('Strand');
    await db
        .into(db.automationRules)
        .insert(
          AutomationRulesCompanion.insert(
            id: 'r1',
            name: 'Meer',
            triggerType: 'location',
          ),
        );
    await db
        .into(db.automationRuleTags)
        .insert(
          AutomationRuleTagsCompanion.insert(ruleId: 'r1', tagId: strand),
        );

    await db.nimmKiTagsZurueck();

    expect([for (final t in await db.select(db.tags).get()) t.id], [strand]);
  });

  test('Abnehmen löscht ein Schlagwort nicht, das eine Regel nutzt', () async {
    await aufnahme('a');
    await db.tagAsset('a', 'Urlaub');
    final urlaub = await db.ensureTag('Urlaub');
    await db
        .into(db.automationRules)
        .insert(
          AutomationRulesCompanion.insert(
            id: 'r1',
            name: 'Ferien',
            triggerType: 'location',
          ),
        );
    await db
        .into(db.automationRuleTags)
        .insert(
          AutomationRuleTagsCompanion.insert(ruleId: 'r1', tagId: urlaub),
        );

    await db.nimmSchlagwortAb(['a'], 'Urlaub');

    expect([for (final t in await db.select(db.tags).get()) t.id], [urlaub]);
    // Ohne Regel verschwindet es wie bisher.
    await db.tagAsset('a', 'Einmal');
    await db.nimmSchlagwortAb(['a'], 'Einmal');
    expect(
      [for (final t in await db.select(db.tags).get()) t.name],
      ['Urlaub'],
    );
  });

  test('auf einer leeren Bibliothek passiert nichts Schlimmes', () async {
    expect(await db.nimmKiTagsZurueck(), 0);
  });
}
