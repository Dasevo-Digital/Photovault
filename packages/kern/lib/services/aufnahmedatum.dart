import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:drift/drift.dart' show Value;
import '../db/database.dart';
import 'storage_paths.dart';

/// Datum und Ablagepfad werden gemeinsam geändert, auch beim Restore.
class AufnahmedatumDienst {
  const AufnahmedatumDienst(this.db, this.paths);
  final AppDatabase db;
  final StoragePaths paths;

  Future<void> setze(
    AssetData asset,
    DateTime datum, {
    bool geschaetzt = false,
    bool streng = false,
  }) async {
    final neu = datum.toLocal();
    final alterPfad = asset.relativePath;
    final neuerPfad = paths.originalRelativePath(
      neu,
      asset.id,
      p.extension(alterPfad).toLowerCase(),
    );
    if (asset.fileCreatedAt.isAtSameMomentAs(neu) &&
        asset.datumGeschaetzt == geschaetzt &&
        alterPfad == neuerPfad) {
      return;
    }
    final quelle = paths.absolute(alterPfad), ziel = paths.absolute(neuerPfad);
    var verschoben = false, beilage = false;
    final alteBeilage = paths.absolute(paths.xmpSidecarPath(alterPfad));
    final neueBeilage = paths.absolute(paths.xmpSidecarPath(neuerPfad));
    try {
      if (alterPfad != neuerPfad) {
        await ziel.parent.create(recursive: true);
        if (await ziel.exists()) {
          throw const FileSystemException('pv_datum_ziel_belegt');
        }
        await quelle.rename(ziel.path);
        verschoben = true;
        if (await alteBeilage.exists()) {
          try {
            await alteBeilage.rename(neueBeilage.path);
            beilage = true;
          } on FileSystemException {
            if (streng) rethrow;
          }
        }
      }
    } on FileSystemException {
      if (streng) {
        if (verschoben) await ziel.rename(quelle.path);
        rethrow;
      }
    }
    try {
      await db.transaction(() async {
        await db.setAufnahmezeitpunkt(
          asset.id,
          neu,
          neuerPfad: verschoben ? neuerPfad : null,
        );
        await (db.update(db.assets)..where((t) => t.id.equals(asset.id))).write(
          AssetsCompanion(datumGeschaetzt: Value(geschaetzt)),
        );
      });
    } catch (_) {
      try {
        if (beilage) await neueBeilage.rename(alteBeilage.path);
      } finally {
        if (verschoben) await ziel.rename(quelle.path);
      }
      rethrow;
    }
  }
}
