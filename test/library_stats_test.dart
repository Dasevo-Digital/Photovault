import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/library_stats.dart';

/// Fügt ein synthetisches Asset mit frei wählbaren, für die Statistik
/// relevanten Feldern ein (analog zu insertSyntheticAssets in
/// timeline_pagination_test.dart, hier aber mit Kontrolle über
/// Typ/Kamera/Größe/Favorit/Papierkorb/Sperre statt nur Datum).
Future<void> insertStatsAsset(
  AppDatabase db,
  String id, {
  String type = 'IMAGE',
  DateTime? fileCreatedAt,
  bool isFavorite = false,
  bool isTrashed = false,
  bool isLocked = false,
  int fileSizeBytes = 0,
  String? linkedAssetId,
  String? cameraMake,
  String? cameraModel,
}) async {
  await db.into(db.assets).insert(AssetsCompanion.insert(
        id: id,
        originalFileName: '$id.jpg',
        relativePath: 'originals/$id.jpg',
        checksum: 'checksum_$id',
        type: type,
        fileCreatedAt: fileCreatedAt ?? DateTime(2020, 1, 1),
        importedAt: DateTime(2020, 1, 1),
        isFavorite: Value(isFavorite),
        isTrashed: Value(isTrashed),
        isLocked: Value(isLocked),
        fileSizeBytes: Value(fileSizeBytes),
        linkedAssetId: Value(linkedAssetId),
        cameraMake: Value(cameraMake),
        cameraModel: Value(cameraModel),
      ));
}

void main() {
  group('AppDatabase.loadLibraryStats', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test(
        'zählt Fotos/Videos/Favoriten korrekt und ignoriert das verknüpfte '
        'Video eines Live-Photo-Paares', () async {
      await insertStatsAsset(db, 'img1', type: 'IMAGE');
      await insertStatsAsset(db, 'img2', type: 'IMAGE', isFavorite: true);
      await insertStatsAsset(db, 'vid1', type: 'VIDEO');
      // Live-Photo-Paar: beide Seiten zeigen aufeinander (siehe
      // AppDatabase.linkAssets), das Video-Gegenstück wird für die
      // Medienzahl bewusst nicht separat gezählt.
      await insertStatsAsset(db, 'imgLP', type: 'IMAGE', linkedAssetId: 'vidLP');
      await insertStatsAsset(db, 'vidLP', type: 'VIDEO', linkedAssetId: 'imgLP');

      final stats = await db.loadLibraryStats();

      expect(stats.imageCount, 3);
      expect(stats.videoCount, 1);
      expect(stats.totalCount, 4);
      expect(stats.favoriteCount, 1);
    });

    test(
        'Speicherplatz zählt alle nicht gelöschten/gesperrten Dateien inkl. '
        'des verknüpften Live-Photo-Videos, aber ohne Papierkorb/Sperre', () async {
      await insertStatsAsset(db, 'a', fileSizeBytes: 1000);
      await insertStatsAsset(db, 'b', fileSizeBytes: 500, isTrashed: true);
      await insertStatsAsset(db, 'c', fileSizeBytes: 300, isLocked: true);
      await insertStatsAsset(db, 'imgLP', type: 'IMAGE', fileSizeBytes: 200, linkedAssetId: 'vidLP');
      await insertStatsAsset(db, 'vidLP', type: 'VIDEO', fileSizeBytes: 800, linkedAssetId: 'imgLP');

      final stats = await db.loadLibraryStats();

      // 1000 (a) + 200 (imgLP) + 800 (vidLP) - b und c ausgeschlossen.
      expect(stats.totalSizeBytes, 2000);
    });

    test('trashedCount und lockedCount', () async {
      await insertStatsAsset(db, 'normal');
      await insertStatsAsset(db, 't1', isTrashed: true);
      await insertStatsAsset(db, 't2', isTrashed: true);
      await insertStatsAsset(db, 'l1', isLocked: true);

      final stats = await db.loadLibraryStats();

      expect(stats.trashedCount, 2);
      expect(stats.lockedCount, 1);
    });

    test('countsByYear und countsByMonth zählen korrekt', () async {
      // Uhrzeit bewusst NICHT auf Mitternacht: drift speichert DateTime als
      // UTC-Unixzeit, und strftime(..., 'unixepoch') liest wieder UTC – bei
      // 00:00 Lokalzeit in einer Zeitzone vor UTC (z.B. CET) würde die
      // UTC-Umrechnung sonst auf den Vortag zurückfallen und knapp den
      // Monats-/Jahreswechsel verpassen.
      await insertStatsAsset(db, 'a', fileCreatedAt: DateTime(2019, 6, 15, 12));
      await insertStatsAsset(db, 'b', fileCreatedAt: DateTime(2019, 12, 15, 12));
      await insertStatsAsset(db, 'c', fileCreatedAt: DateTime(2021, 6, 20, 12));

      final stats = await db.loadLibraryStats();

      expect(stats.countsByYear[2019], 2);
      expect(stats.countsByYear[2021], 1);
      expect(stats.countsByYear.containsKey(2020), isFalse);

      expect(stats.countsByMonth[6], 2);
      expect(stats.countsByMonth[12], 1);
      expect(stats.countsByMonth.containsKey(1), isFalse);
    });

    test('topCameras gruppiert nach Hersteller+Modell, absteigend sortiert', () async {
      await insertStatsAsset(db, 'c1', cameraMake: 'Apple', cameraModel: 'iPhone 15 Pro');
      await insertStatsAsset(db, 'c2', cameraMake: 'Apple', cameraModel: 'iPhone 15 Pro');
      await insertStatsAsset(db, 'c3', cameraMake: 'Apple', cameraModel: 'iPhone 15 Pro');
      await insertStatsAsset(db, 'c4', cameraMake: 'Canon', cameraModel: 'EOS R5');
      await insertStatsAsset(db, 'c5', cameraMake: 'Canon', cameraModel: 'EOS R5');
      await insertStatsAsset(db, 'c6'); // ohne Kamerainfo

      final stats = await db.loadLibraryStats();

      expect(stats.topCameras, hasLength(3));
      expect(stats.topCameras[0].count, 3);
      expect(stats.topCameras[0].make, 'Apple');
      expect(stats.topCameras[0].model, 'iPhone 15 Pro');
      expect(stats.topCameras[1].count, 2);
      expect(stats.topCameras[2].count, 1);
      expect(stats.topCameras[2].make, isNull);
      expect(stats.topCameras[2].label, 'Unbekannt');
    });
  });

  group('CameraStat.label', () {
    test('kombiniert Hersteller und Modell, wenn das Modell den Hersteller nicht enthält', () {
      expect(const CameraStat(make: 'Canon', model: 'EOS R5', count: 1).label, 'Canon EOS R5');
    });

    test('lässt den Hersteller weg, wenn er bereits Teil des Modellnamens ist', () {
      expect(const CameraStat(make: 'Apple', model: 'Apple iPhone 15 Pro', count: 1).label,
          'Apple iPhone 15 Pro');
    });

    test('fällt auf "Unbekannt" zurück, wenn weder Hersteller noch Modell bekannt sind', () {
      expect(const CameraStat(count: 1).label, 'Unbekannt');
    });
  });
}
