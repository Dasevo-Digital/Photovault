import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/ai_tagging_service.dart';

/// Das Mitübersetzen des Schlagwort-Vokabulars beim Sprachwechsel.
///
/// Der einzige Teil der Übersetzung, der **Nutzerdaten anfasst** – und
/// damit der einzige, der etwas kaputtmachen kann. Geprüft wird deshalb
/// vor allem, was erhalten bleiben muss.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<String> asset(String id) async {
    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'c_$id',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2024, 1, 1),
          importedAt: DateTime(2024, 1, 1),
        ));
    return id;
  }

  Future<List<String>> tagsVon(String assetId) async {
    final rows = await (db.select(db.assetTags)..where((t) => t.assetId.equals(assetId))).get();
    final namen = <String>[];
    for (final r in rows) {
      final tag = await (db.select(db.tags)..where((t) => t.id.equals(r.tagId))).getSingleOrNull();
      if (tag != null) namen.add(tag.name);
    }
    return namen..sort();
  }

  group('Die Zuordnungstabelle', () {
    test('deckt jeden Begriff der Startbestückung ab', () {
      // Ein fehlender Begriff bliebe beim Wechsel stehen und die
      // Bibliothek zerfiele in zwei Sprachen.
      for (final begriff in defaultAiTagVocabulary) {
        expect(aiTagVocabularyEnglisch, contains(begriff), reason: begriff);
      }
      expect(aiTagVocabularyEnglisch, hasLength(defaultAiTagVocabulary.length));
    });

    test('ist umkehrbar – keine zwei Begriffe teilen eine Übersetzung', () {
      // Sonst liesse sich der Wechsel zurück nach Deutsch nicht eindeutig
      // ausführen, und zwei Schlagwörter verschmölzen unbeabsichtigt.
      final englisch = aiTagVocabularyEnglisch.values.toList();
      expect(englisch.toSet(), hasLength(englisch.length));
    });

    test('liefert die Startbestückung in der gewünschten Sprache', () {
      expect(vokabularFuerSprache('de'), defaultAiTagVocabulary);
      final en = vokabularFuerSprache('en');
      expect(en, hasLength(defaultAiTagVocabulary.length));
      expect(en, contains('Sunset'));
      expect(en, isNot(contains('Sonnenuntergang')));
    });
  });

  group('Umbenennen', () {
    test('erhält alle bereits vergebenen Schlagwörter', () async {
      // Der eigentliche Grund, warum das überhaupt geht: AssetTags hängt an
      // Tags.id, nicht am Namen. Ein Umbenennen ist ein reines UPDATE.
      final a = await asset('a');
      await db.tagAsset(a, 'Hund');
      await db.tagAsset(a, 'Strand');
      expect(await tagsVon(a), ['Hund', 'Strand']);

      final anzahl = await db.uebersetzeVokabular({'Hund': 'Dog', 'Strand': 'Beach'});

      expect(anzahl, 2);
      expect(await tagsVon(a), ['Beach', 'Dog']);
    });

    test('ein Begriff ohne Vokabeleintrag wird übergangen', () async {
      // Die Zuordnungstabelle deckt die Startbestückung ab; ein Nutzer kann
      // Begriffe daraus aber gelöscht haben. Dann darf auch das zugehörige
      // Schlagwort nicht angefasst werden.
      final a = await asset('a');
      await db.tagAsset(a, 'Hund');
      await (db.delete(db.aiTagVocabulary)..where((t) => t.term.equals('Hund'))).go();

      final anzahl = await db.uebersetzeVokabular({'Hund': 'Dog'});

      expect(anzahl, 0);
      expect(await tagsVon(a), ['Hund']);
    });

    test('benennt Vokabel UND Schlagwort um, Zuordnung bleibt', () async {
      final a = await asset('a');
      await db.tagAsset(a, 'Hund');

      final anzahl = await db.uebersetzeVokabular({'Hund': 'Dog'});

      expect(anzahl, 1);
      expect(await db.aiTagVocabularyTerms(), contains('Dog'));
      expect(await db.aiTagVocabularyTerms(), isNot(contains('Hund')));
      expect(await tagsVon(a), ['Dog'], reason: 'die Zuordnung folgt über die ID');
    });

    test('selbst hinzugefügte Begriffe bleiben unverändert', () async {
      await db.into(db.aiTagVocabulary)
          .insert(AiTagVocabularyCompanion.insert(term: 'Oma Elses Garten'));

      await db.uebersetzeVokabular({'Hund': 'Dog'});

      final begriffe = await db.aiTagVocabularyTerms();
      expect(begriffe, contains('Dog'));
      expect(begriffe, contains('Oma Elses Garten'));
    });
  });

  group('Namenskollision', () {
    test('verschmilzt statt zu brechen', () async {
      // Beide Namensspalten sind unique. Gibt es das Ziel schon, muss
      // verschmolzen werden – ein blindes UPDATE bräche die ganze
      // Umstellung mit einem Constraint-Fehler ab.
      // 'Hund' bringt die Startbestückung schon mit; 'Dog' legt der Nutzer
      // von Hand an – genau daraus entsteht die Kollision.
      await db.into(db.aiTagVocabulary).insert(AiTagVocabularyCompanion.insert(term: 'Dog'));

      final a = await asset('a');
      final b = await asset('b');
      await db.tagAsset(a, 'Hund');
      await db.tagAsset(b, 'Dog');

      await db.uebersetzeVokabular({'Hund': 'Dog'});

      final begriffe = await db.aiTagVocabularyTerms();
      expect(begriffe.where((t) => t == 'Dog'), hasLength(1));
      expect(begriffe, isNot(contains('Hund')));
      expect(await tagsVon(a), ['Dog'], reason: 'das Foto behält sein Schlagwort');
      expect(await tagsVon(b), ['Dog']);
    });

    test('ein Foto mit beiden Schlagwörtern bekommt danach eines', () async {
      // 'Hund' bringt die Startbestückung schon mit; 'Dog' legt der Nutzer
      // von Hand an – genau daraus entsteht die Kollision.
      await db.into(db.aiTagVocabulary).insert(AiTagVocabularyCompanion.insert(term: 'Dog'));

      final a = await asset('a');
      await db.tagAsset(a, 'Hund');
      await db.tagAsset(a, 'Dog');

      await db.uebersetzeVokabular({'Hund': 'Dog'});

      expect(await tagsVon(a), ['Dog'], reason: 'nicht doppelt');
    });
  });

  group('Automatisierungsregeln', () {
    test('der Auslöse-Begriff wandert mit', () async {
      // Die Stelle, die man übersieht: aiTagTerm ist eine Textspalte mit
      // exaktem Namensbezug. Bliebe sie stehen, hörte die Regel lautlos auf
      // zu feuern.
      await db.into(db.automationRules).insert(AutomationRulesCompanion.insert(
        id: 'r1',
        name: 'Hundefotos markieren',
        triggerType: 'aiTag',
        aiTagTerm: const Value('Hund'),
      ));

      await db.uebersetzeVokabular({'Hund': 'Dog'});

      final regel =
          await (db.select(db.automationRules)..where((t) => t.id.equals('r1'))).getSingle();
      expect(regel.aiTagTerm, 'Dog');
    });

    test('Regeln zu anderen Begriffen bleiben unberührt', () async {
      await db.into(db.automationRules).insert(AutomationRulesCompanion.insert(
        id: 'r1',
        name: 'Katzenfotos',
        triggerType: 'aiTag',
        aiTagTerm: const Value('Katze'),
      ));

      await db.uebersetzeVokabular({'Hund': 'Dog'});

      final regel =
          await (db.select(db.automationRules)..where((t) => t.id.equals('r1'))).getSingle();
      expect(regel.aiTagTerm, 'Katze');
    });
  });

  test('ein vollständiger Wechsel und zurück landet wieder am Anfang', () async {
    // Die härteste Zusage: Nichts geht verloren, auch nicht über zwei
    // Umstellungen hinweg.
    final a = await asset('a');
    await db.tagAsset(a, 'Sonnenuntergang');
    await db.tagAsset(a, 'Meer');

    await db.uebersetzeVokabular(aiTagVocabularyEnglisch);
    expect(await tagsVon(a), ['Sea', 'Sunset']);

    final zurueck = {for (final e in aiTagVocabularyEnglisch.entries) e.value: e.key};
    await db.uebersetzeVokabular(zurueck);

    expect(await tagsVon(a), ['Meer', 'Sonnenuntergang']);
    expect((await db.aiTagVocabularyTerms()).toSet(), defaultAiTagVocabulary.toSet());
  });

  test('eigene Begriffe werden richtig gezählt', () async {
    await db.into(db.aiTagVocabulary).insert(AiTagVocabularyCompanion.insert(term: 'Segeln'));

    expect(await db.zaehleEigeneVokabelbegriffe(defaultAiTagVocabulary.toSet()), 1);
  });
}
