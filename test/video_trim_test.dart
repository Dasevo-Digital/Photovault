import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

/// Prüft die DB-Seite des nicht-destruktiven Video-Zuschnitts (siehe
/// VideoTrimScreen): Speichern/Zurücksetzen von Start/Ende samt
/// `Assets.trimmedRelativePath`, analog zu develop_settings_test.dart für
/// die nicht-destruktive Bildentwicklung.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> insertVideoAsset(String id, {bool isLocked = false}) async {
    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.mov',
          relativePath: 'originals/$id.mov',
          checksum: 'checksum_$id',
          type: 'VIDEO',
          fileCreatedAt: DateTime(2024, 1, 1),
          importedAt: DateTime(2024, 1, 1),
          isLocked: Value(isLocked),
        ));
    return id;
  }

  test('saveVideoTrim speichert Start/Ende und trimmedRelativePath in einem Zug', () async {
    final assetId = await insertVideoAsset('a');

    await db.saveVideoTrim(
      assetId,
      startSeconds: 1.5,
      endSeconds: 8.25,
      trimmedRelativePath: 'trimmed/a.mp4',
    );

    final asset = await db.assetById(assetId);
    expect(asset!.trimmedRelativePath, 'trimmed/a.mp4');

    final trim = await db.videoTrimForAsset(assetId);
    expect(trim, isNotNull);
    expect(trim!.startSeconds, closeTo(1.5, 1e-9));
    expect(trim.endSeconds, closeTo(8.25, 1e-9));
  });

  test('saveVideoTrim auf bereits zugeschnittenem Video überschreibt den alten Zuschnitt', () async {
    final assetId = await insertVideoAsset('a');
    await db.saveVideoTrim(assetId, startSeconds: 0, endSeconds: 5, trimmedRelativePath: 'trimmed/a.mp4');
    await db.saveVideoTrim(assetId, startSeconds: 2, endSeconds: 9, trimmedRelativePath: 'trimmed/a.mp4');

    final all = await db.select(db.videoTrims).get();
    expect(all, hasLength(1)); // kein zweiter Datensatz für dasselbe Asset
    expect(all.single.startSeconds, closeTo(2, 1e-9));
    expect(all.single.endSeconds, closeTo(9, 1e-9));
  });

  test('resetVideoTrim löscht den Zuschnitt und setzt trimmedRelativePath zurück', () async {
    final assetId = await insertVideoAsset('a');
    await db.saveVideoTrim(assetId, startSeconds: 0, endSeconds: 5, trimmedRelativePath: 'trimmed/a.mp4');

    await db.resetVideoTrim(assetId);

    expect(await db.videoTrimForAsset(assetId), isNull);
    expect((await db.assetById(assetId))!.trimmedRelativePath, isNull);
  });

  test('resetVideoTrim auf nie zugeschnittenem Video ist ein günstiges No-Op', () async {
    final assetId = await insertVideoAsset('a');
    await db.resetVideoTrim(assetId); // darf nicht werfen
    expect(await db.videoTrimForAsset(assetId), isNull);
  });
}
