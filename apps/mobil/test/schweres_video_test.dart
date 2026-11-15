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

  group('Stillstand (#395)', () {
    final t0 = DateTime(2026, 11, 15, 12);
    VideoPlayerValue bei(int sekunde, {bool spielt = true}) => VideoPlayerValue(
      duration: const Duration(seconds: 30),
      position: Duration(seconds: sekunde),
      isPlaying: spielt,
    );
    DateTime nach(int s) => t0.add(Duration(seconds: s));

    test('steht erst nach der Grenze, auch wenn isPlaying falsch ist', () {
      final w = Stillstand();
      // Unter Android beim Puffern: isPlaying falsch, Position steht.
      expect(
        w.steht(bei(0, spielt: false), angehalten: false, jetzt: t0),
        isFalse,
      );
      expect(
        w.steht(bei(0, spielt: false), angehalten: false, jetzt: nach(5)),
        isFalse,
      );
      expect(
        w.steht(bei(0, spielt: false), angehalten: false, jetzt: nach(6)),
        isTrue,
      );
    });

    test('stockt es mittendrin, zählt die Zeit ab dem letzten Fortschritt', () {
      final w = Stillstand();
      expect(w.steht(bei(0), angehalten: false, jetzt: t0), isFalse);
      expect(w.steht(bei(4), angehalten: false, jetzt: nach(4)), isFalse);
      expect(w.steht(bei(4), angehalten: false, jetzt: nach(9)), isFalse);
      expect(w.steht(bei(4), angehalten: false, jetzt: nach(10)), isTrue);
    });

    test('angehalten oder am Ende steht nichts', () {
      final w = Stillstand();
      expect(w.steht(bei(3), angehalten: true, jetzt: t0), isFalse);
      expect(w.steht(bei(3), angehalten: true, jetzt: nach(60)), isFalse);
      // Weiter: Die Frist beginnt neu.
      expect(w.steht(bei(3), angehalten: false, jetzt: nach(61)), isFalse);
      expect(w.steht(bei(3), angehalten: false, jetzt: nach(66)), isFalse);
      expect(w.steht(bei(3), angehalten: false, jetzt: nach(67)), isTrue);

      final ende = Stillstand();
      for (var s = 0; s < 20; s++) {
        expect(
          ende.steht(bei(30, spielt: false), angehalten: false, jetzt: nach(s)),
          isFalse,
        );
      }
    });
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
