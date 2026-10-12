import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/search_filters.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Das Gesprochene in Videos: welche Videos gehört werden, wie man es
/// findet, und dass es beim Sperren verschwindet.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> aufnahme(
    String id, {
    String typ = 'VIDEO',
    String? partner,
    bool gesperrt = false,
    bool papierkorb = false,
  }) => db
      .into(db.assets)
      .insert(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.mov',
          relativePath: 'originals/$id.mov',
          checksum: 'pruef-$id',
          type: typ,
          fileCreatedAt: DateTime(2025, 6, int.parse(id.substring(1))),
          importedAt: DateTime(2026),
          linkedAssetId: Value(partner),
          isLocked: Value(gesperrt),
          isTrashed: Value(papierkorb),
        ),
      );

  test(
    'gehört werden Videos, keine Fotos und keine Live-Photo-Hälften',
    () async {
      await aufnahme('v1');
      await aufnahme('v2');
      await aufnahme('f3', typ: 'IMAGE');
      await aufnahme('v4', partner: 'f3');
      await aufnahme('v5', gesperrt: true);
      await aufnahme('v6', papierkorb: true);
      final offen = await db.assetsForTranskription();
      expect(
        [for (final a in offen) a.id],
        ['v2', 'v1'],
        reason: 'neueste zuerst',
      );
      expect(await db.countTranskription(), 2);

      // Auch „nichts gesagt" ist erledigt.
      await db.setTranskript('v1');
      expect([for (final a in await db.assetsForTranskription()) a.id], ['v2']);
      expect(
        [for (final a in await db.assetsForTranskription(alle: true)) a.id],
        ['v2', 'v1'],
      );
    },
  );

  test('das Gesprochene ist durchsuchbar, Wortanfänge genügen', () async {
    await aufnahme('v1');
    await aufnahme('v2');
    await db.setTranskript(
      'v1',
      text: 'Wir feiern heute den 70. Geburtstag von Oma Gertrud im Garten.',
      sprache: 'de',
    );
    await db.setTranskript('v2', text: 'Der Zug nach Hamburg.', sprache: 'de');
    Future<List<String>> suche(String begriff) async => [
      for (final a in await db.searchAssets(
        SearchFilters(textMode: SearchTextMode.transkript, query: begriff),
      ))
        a.id,
    ];
    expect(await suche('Geburt'), ['v1']);
    expect(await suche('hamburg'), ['v2']);
    expect(await suche('Oma Garten'), ['v1']);
    expect(await suche('Kuchen'), isEmpty);
    final v1 = (await db.assetsByIds(['v1'])).single;
    expect(v1.transkriptSprache, 'de');
    expect(v1.transkriptGeprueft, isTrue);
  });

  test('beim Sperren verschwindet das Gesprochene aus der Datenbank', () async {
    await aufnahme('v1');
    await db.setTranskript('v1', text: 'Geheimer Plan', sprache: 'de');
    await db.clearDerivedContentData(['v1']);
    final v1 = (await db.assetsByIds(['v1'])).single;
    expect(v1.transkript, isNull);
    expect(v1.transkriptGeprueft, isFalse, reason: 'nach dem Entsperren neu');
    expect(
      await db.searchAssets(
        const SearchFilters(
          textMode: SearchTextMode.transkript,
          query: 'Geheimer',
        ),
      ),
      isEmpty,
      reason: 'auch nicht im Volltextindex',
    );
    await db.setTranskript('v1', text: 'Noch ein Plan');
    await db.hidePrivateMetadata('v1');
    expect((await db.assetsByIds(['v1'])).single.transkript, isNull);
  });

  test(
    'Migration 91 auf 92: Spalten und Volltextindex, nichts verloren',
    () async {
      final dir = await Directory.systemTemp.createTemp('photo_vault_v91_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/library.sqlite');
      final vorher = AppDatabase(NativeDatabase(file));
      await vorher
          .into(vorher.assets)
          .insert(
            AssetsCompanion.insert(
              id: 'f1',
              originalFileName: 'f1.jpg',
              relativePath: 'originals/f1.jpg',
              checksum: 'pruef-f1',
              type: 'IMAGE',
              fileCreatedAt: DateTime(2025),
              importedAt: DateTime(2026),
              ocrText: const Value('Bahnhofstrasse'),
            ),
          );
      await vorher.close();

      // Zurück auf 91: Spalten weg, Index und Auslöser in der alten Form.
      final alt = sqlite.sqlite3.open(file.path);
      for (final t in [
        'assets_fts_insert',
        'assets_fts_update',
        'assets_fts_delete',
      ]) {
        alt.execute('DROP TRIGGER $t');
      }
      alt.execute('DROP TABLE asset_search_fts');
      for (final spalte in [
        'transkript',
        'transkript_sprache',
        'transkript_geprueft',
      ]) {
        alt.execute('ALTER TABLE assets DROP COLUMN $spalte');
      }
      alt.execute('''
      CREATE VIRTUAL TABLE asset_search_fts USING fts5(
        asset_id UNINDEXED, original_file_name, description, ocr_text,
        ai_caption, ai_caption_de, tokenize = 'unicode61 remove_diacritics 2')
    ''');
      alt.execute('''
      INSERT INTO asset_search_fts (asset_id, original_file_name, description,
        ocr_text, ai_caption, ai_caption_de)
      SELECT id, original_file_name, '', coalesce(ocr_text, ''), '', '' FROM assets
    ''');
      alt.execute('PRAGMA user_version = 91');
      alt.close();

      final nachher = AppDatabase(NativeDatabase(file));
      addTearDown(nachher.close);
      // Der alte Index ist im neuen aufgegangen …
      final ocr = await nachher.searchAssets(
        const SearchFilters(textMode: SearchTextMode.ocr, query: 'Bahnhof'),
      );
      expect([for (final a in ocr) a.id], ['f1']);
      // … und das Gesprochene kommt dazu.
      await nachher
          .into(nachher.assets)
          .insert(
            AssetsCompanion.insert(
              id: 'v2',
              originalFileName: 'v2.mov',
              relativePath: 'originals/v2.mov',
              checksum: 'pruef-v2',
              type: 'VIDEO',
              fileCreatedAt: DateTime(2025),
              importedAt: DateTime(2026),
            ),
          );
      expect(await nachher.countTranskription(), 1);
      await nachher.setTranskript('v2', text: 'Gleis vier', sprache: 'de');
      final treffer = await nachher.searchAssets(
        const SearchFilters(
          textMode: SearchTextMode.transkript,
          query: 'gleis',
        ),
      );
      expect([for (final a in treffer) a.id], ['v2']);
    },
  );
}
