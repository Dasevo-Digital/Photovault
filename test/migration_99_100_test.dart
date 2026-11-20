import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test(
    '99 auf 100 erhält Fotos und Entwicklungen und legt Varianten an',
    () async {
      final temp = await Directory.systemTemp.createTemp('pv_migration100_');
      addTearDown(() => temp.delete(recursive: true));
      final f = File('${temp.path}/library.sqlite');
      final vorher = AppDatabase(NativeDatabase(f));
      await vorher.insertAsset(
        AssetsCompanion.insert(
          id: 'foto',
          originalFileName: 'foto.jpg',
          relativePath: 'originals/foto.jpg',
          checksum: 'a' * 64,
          type: 'IMAGE',
          fileCreatedAt: DateTime(2024),
          importedAt: DateTime(2026),
        ),
      );
      await vorher.saveDevelopResult(
        'foto',
        settings: DevelopSettingsCompanion.insert(
          assetId: 'foto',
          updatedAt: DateTime(2026),
        ),
        developedRelativePath: 'developed/foto.jpg',
      );
      await vorher.close();
      final alt = sqlite.sqlite3.open(f.path);
      alt.execute('DROP TABLE develop_variant_files');
      alt.execute('DROP TABLE develop_variants');
      alt.execute('ALTER TABLE develop_settings DROP COLUMN crop_json');
      alt.execute('ALTER TABLE develop_history DROP COLUMN crop_json');
      alt.execute('PRAGMA user_version=99');
      alt.close();
      final db = AppDatabase(NativeDatabase(f));
      addTearDown(db.close);
      expect(
        (await db.assetById('foto'))!.developedRelativePath,
        'developed/foto.jpg',
      );
      expect((await db.developSettingsForAsset('foto'))!.cropJson, isNull);
      expect(await db.variantenFuer('foto'), isEmpty);
      expect(await db.select(db.developVariantFiles).get(), isEmpty);
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
