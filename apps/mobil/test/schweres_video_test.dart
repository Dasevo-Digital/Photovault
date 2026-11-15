import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:photo_vault_mobil/seiten/videospieler.dart';
import 'package:video_player/video_player.dart';

/// Ein schweres Original kommt über die leichte Fassung des Servers
/// (#393). Ein 4K-Video vom iPhone mit HDR hat rund 54 Mbit/s; über den
/// Upload daheim lief es nicht an, und die Seite blieb schwarz.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<AssetData> video(String id, {int? bytes, double? sekunden}) async {
    await db.insertAsset(
      AssetsCompanion.insert(
        id: id,
        originalFileName: '$id.mov',
        relativePath: 'originals/$id.mov',
        checksum: 'pruef-$id',
        type: 'VIDEO',
        fileCreatedAt: DateTime(2026, 11, 14),
        importedAt: DateTime(2026, 11, 14),
        fileSizeBytes: bytes == null ? const Value.absent() : Value(bytes),
        durationSeconds: Value(sekunden),
      ),
    );
    return (await db.assetById(id))!;
  }

  test('iPhone 4K HDR ist schwer, ein gewöhnliches Video nicht', () async {
    expect(
      istSchweresVideo(await video('iphone', bytes: 154338552, sekunden: 22.7)),
      isTrue,
    );
    expect(
      istSchweresVideo(await video('klein', bytes: 6000000, sekunden: 8)),
      isFalse,
    );
    // Genau an der Grenze noch nicht.
    expect(
      istSchweresVideo(await video('grenze', bytes: 25000000, sekunden: 10)),
      isFalse,
    );
  });

  test('ohne Dauer oder Grösse gilt nichts als schwer', () async {
    expect(
      istSchweresVideo(await video('ohne_dauer', bytes: 1 << 30)),
      isFalse,
    );
    expect(
      istSchweresVideo(await video('dauer_null', bytes: 1 << 30, sekunden: 0)),
      isFalse,
    );
    expect(istSchweresVideo(await video('ohne_groesse', sekunden: 3)), isFalse);
  });

  test('die leichte Fassung erkennt der Betrachter an ihrer Adresse', () {
    final leicht = VideoPlayerController.networkUrl(
      Uri.parse('https://fotos.example.de/api/v1/aufnahmen/a%201/abspielbar'),
    );
    final original = VideoPlayerController.networkUrl(
      Uri.parse(
        'https://fotos.example.de/api/v1/dateien/originals/2026/11/a.mov',
      ),
    );
    final hier = VideoPlayerController.asset('videos/abspielbar');
    expect(spieltLeichteFassung(leicht), isTrue);
    expect(spieltLeichteFassung(original), isFalse);
    expect(spieltLeichteFassung(hier), isFalse);
  });
}
