import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/db/rasterzeile.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/widgets/timeline_grid_layout.dart';

/// Prüft [timelineOffsetForAsset] – den geschätzten Scroll-Offset für "Foto
/// in der Timeline anzeigen" (Kontextmenü der Vollbildansicht). Muss nicht
/// pixelgenau sein (siehe Kommentar in timeline_grid_layout.dart), aber
/// monoton mit der Position des Fotos wachsen und Fotos in derselben Zeile
/// gleich behandeln.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late ImportService import;
  var nextByte = 0;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('photo_vault_timeline_layout_test_');
    db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
    import = ImportService(db, paths);
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<AssetData> importPhotoAt(String name, DateTime date) async {
    final incoming = Directory(p.join(tempRoot.path, 'incoming'))..createSync(recursive: true);
    final file = File(p.join(incoming.path, name))..writeAsBytesSync([1, 2, 3, nextByte++]);
    final result = await import.importFile(file.path);
    expect(result.outcome, ImportOutcome.imported);
    await db.setFileCreatedAt(result.assetId!, date);
    return (await db.assetById(result.assetId!))!;
  }

  test('Fotos in einer chronologisch früheren Monatsgruppe bekommen einen größeren Offset', () async {
    final june = await importPhotoAt('a.jpg', DateTime(2026, 6, 15));
    final may = await importPhotoAt('b.jpg', DateTime(2026, 5, 15));

    final groups = <int, List<Rasterzeile>>{
      202606: [Rasterzeile.aus(june)],
      202605: [Rasterzeile.aus(may)],
    };
    const orderedKeys = [202606, 202605]; // absteigend, wie in MonthGroupedAssetGrid

    final juneOffset = timelineOffsetForAsset(orderedKeys, groups, 800, june.id);
    final mayOffset = timelineOffsetForAsset(orderedKeys, groups, 800, may.id);

    expect(juneOffset, timelineHeaderHeight); // erste Gruppe: nur die Kopfzeilenhöhe
    expect(mayOffset, greaterThan(juneOffset!));
  });

  test('gibt null zurück, wenn das Foto in keiner Gruppe vorkommt', () async {
    final asset = await importPhotoAt('a.jpg', DateTime(2026, 6, 15));
    final groups = <int, List<Rasterzeile>>{
      202606: [Rasterzeile.aus(asset)]
    };
    expect(timelineOffsetForAsset(const [202606], groups, 800, 'unbekannte-id'), isNull);
  });

  test('Fotos in derselben Zeile (gleiche Reihe) haben denselben Offset', () async {
    final columns = timelineColumnsForWidth(800);
    expect(columns, greaterThan(1));
    final assets = <AssetData>[];
    for (var i = 0; i < columns; i++) {
      assets.add(await importPhotoAt('p$i.jpg', DateTime(2026, 6, 15)));
    }
    final groups = <int, List<Rasterzeile>>{202606: [for (final a in assets) Rasterzeile.aus(a)]};
    final firstOffset = timelineOffsetForAsset(const [202606], groups, 800, assets.first.id);
    final lastOffset = timelineOffsetForAsset(const [202606], groups, 800, assets.last.id);
    expect(firstOffset, lastOffset);
  });
}
