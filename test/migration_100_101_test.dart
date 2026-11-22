import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/search_filters.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test(
    '100 auf 101 erhält Originaldatum, ergänzt nullable Bereiche und Indizes',
    () async {
      final temp = await Directory.systemTemp.createTemp('pv_schema101_');
      addTearDown(() => temp.delete(recursive: true));
      final f = File('${temp.path}/catalog.sqlite'),
          original = DateTime(2024, 6, 1, 17, 2);
      final vorher = AppDatabase(NativeDatabase(f));
      await vorher.insertAsset(
        AssetsCompanion.insert(
          id: 'a',
          originalFileName: 'a.jpg',
          relativePath: 'originals/a.jpg',
          checksum: 'a' * 64,
          type: 'IMAGE',
          fileCreatedAt: original,
          importedAt: DateTime(2026),
        ),
      );
      await vorher.close();
      final raw = sqlite.sqlite3.open(f.path);
      raw.execute('DROP INDEX idx_assets_kalender');
      // Der Index der Zeitleiste trägt die Spalten der Datierung erst seit
      // #435; in Fassung 100 stand er ohne sie.
      raw.execute('DROP INDEX idx_assets_sichtbar');
      raw.execute(
        'CREATE INDEX idx_assets_sichtbar ON assets ('
        'is_trashed, is_locked, file_created_at DESC, id DESC, '
        'type, linked_asset_id, stack_id, is_stack_cover, is_archived)',
      );
      for (final c in [
        'datum_von',
        'datum_bis',
        'datum_genauigkeit',
        'datum_quelle',
        'datum_hinweis',
      ]) {
        raw.execute('ALTER TABLE assets DROP COLUMN $c');
      }
      raw.execute('PRAGMA user_version=100');
      raw.close();
      final db = AppDatabase(NativeDatabase(f));
      addTearDown(db.close);
      expect((await db.assetById('a'))!.fileCreatedAt, original);
      expect((await db.assetById('a'))!.datumVon, isNull);
      await db.fuehreAus(
        DatierungSetzen(
          ['a'],
          AufnahmeDatierung.zeitraum(
            DateTime(1984, 3, 4),
            DateTime(1986, 5, 6),
          ),
        ),
      );
      expect(
        await db.searchAssetIds(
          SearchFilters(
            startDate: DateTime(1985, 7, 2),
            endDate: DateTime(1985, 7, 2),
          ),
        ),
        ['a'],
      );
      expect(
        await db.searchAssetIds(SearchFilters(startDate: DateTime(1986, 5, 7))),
        isEmpty,
      );
      expect(
        await db.searchAssetIds(SearchFilters(endDate: DateTime(1984, 3, 3))),
        isEmpty,
      );
      expect(
        (await db.customSelect('PRAGMA integrity_check').get())
            .single
            .data
            .values
            .single,
        'ok',
      );
      expect(
        (await db.customSelect('PRAGMA user_version').get())
            .single
            .data
            .values
            .single,
        db.schemaVersion,
      );
    },
  );
}
