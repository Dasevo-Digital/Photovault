import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/state/library_state.dart';

/// Ein Bild aus einem Video als Foto: an der richtigen Stelle gegriffen,
/// mit Zeit und Ort des Videos.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<AssetData> anlegen(String id, String typ) async {
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.mov',
            relativePath: 'originals/$id',
            checksum: 'pruef-$id',
            type: typ,
            fileCreatedAt: DateTime.utc(2025, 7, 14, 10),
            importedAt: DateTime(2026),
            durationSeconds: Value(typ == 'VIDEO' ? 120 : null),
            latitude: const Value(47.4),
            longitude: const Value(10.98),
            locationCity: const Value('Garmisch-Partenkirchen'),
            cameraMake: const Value('Apple'),
            cameraModel: const Value('iPhone 15'),
            zeitversatzMinuten: const Value(120),
            datumGeschaetzt: const Value(false),
          ),
        );
    return (await db.assetById(id))!;
  }

  test('ungeschnitten: Anteil und Uhrzeit aus der Position', () async {
    final video = await anlegen('v', 'VIDEO');
    final s = videobildStelle(video, null, const Duration(seconds: 30));
    expect(s.anteil, closeTo(0.25, 1e-9));
    expect(s.wann.toUtc(), DateTime.utc(2025, 7, 14, 10, 0, 30));
  });

  test('geschnitten: die Position zählt ab dem Schnittanfang', () async {
    final video = await anlegen('v', 'VIDEO');
    final schnitt = VideoTrimData(
      assetId: 'v',
      startSeconds: 60,
      endSeconds: 100,
      updatedAt: DateTime(2026),
    );
    final s = videobildStelle(video, schnitt, const Duration(seconds: 10));
    expect(s.anteil, closeTo(0.25, 1e-9), reason: '10 von 40 Sekunden');
    expect(s.wann.toUtc(), DateTime.utc(2025, 7, 14, 10, 1, 10));
  });

  test('ohne bekannte Länge vom Anfang, über das Ende nicht hinaus', () async {
    final video = (await anlegen(
      'v',
      'VIDEO',
    )).copyWith(durationSeconds: const Value(null));
    expect(videobildStelle(video, null, const Duration(seconds: 5)).anteil, 0);
    final lang = await anlegen('w', 'VIDEO');
    expect(videobildStelle(lang, null, const Duration(minutes: 5)).anteil, 1.0);
  });

  test('das Standbild bekommt Zeit, Ort und Kamera des Videos', () async {
    final video = await anlegen('v', 'VIDEO');
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'f',
            originalFileName: 'v-0m30s.jpg',
            relativePath: 'originals/f.jpg',
            checksum: 'pruef-f',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 10, 9),
            importedAt: DateTime(2026, 10, 9),
            datumGeschaetzt: const Value(true),
          ),
        );
    final wann = DateTime.utc(2025, 7, 14, 10, 0, 30);
    await db.uebernimmVideoangaben('f', video, wann);
    final foto = (await db.assetById('f'))!;
    expect(foto.fileCreatedAt.toUtc(), wann);
    expect(foto.datumGeschaetzt, isFalse);
    expect(foto.latitude, 47.4);
    expect(foto.locationCity, 'Garmisch-Partenkirchen');
    expect(foto.cameraModel, 'iPhone 15');
    expect(foto.zeitversatzMinuten, 120);
  });
}
