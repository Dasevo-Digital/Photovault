import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault_mobil/offline_alben.dart';
import 'package:photo_vault_mobil/sitzung.dart';

void main() {
  late Directory ordner;
  late AppDatabase db;
  late StoragePaths paths;
  late File merkdatei;

  setUp(() async {
    ordner = Directory.systemTemp.createTempSync('pv_offline_alben_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(
      Directory(p.join(ordner.path, 'lib')),
    );
    merkdatei = File(p.join(ordner.path, 'offline_alben.json'));
  });

  tearDown(() async {
    await db.close();
    await ordner.delete(recursive: true);
  });

  Future<void> aufnahme(
    String id, {
    String? miniatur,
    String? vorschau,
    String? partner,
  }) => db.insertAsset(
    AssetsCompanion.insert(
      id: id,
      originalFileName: '$id.jpg',
      relativePath: 'originals/$id.jpg',
      thumbnailRelativePath: Value(miniatur),
      previewRelativePath: Value(vorschau),
      checksum: 'pruef-$id',
      type: 'IMAGE',
      fileCreatedAt: DateTime(2025),
      importedAt: DateTime(2026),
      linkedAssetId: Value(partner),
    ),
  );

  test('Auswahl bleibt lokal erhalten und lädt Album samt Partner', () async {
    await aufnahme(
      'foto',
      miniatur: 'thumbnails/foto.jpg',
      vorschau: 'previews/foto.jpg',
      partner: 'video',
    );
    await db.insertAsset(
      AssetsCompanion.insert(
        id: 'video',
        originalFileName: 'video.mov',
        relativePath: 'originals/video.mov',
        checksum: 'pruef-video',
        type: 'VIDEO',
        fileCreatedAt: DateTime(2025),
        importedAt: DateTime(2026),
        linkedAssetId: const Value('foto'),
      ),
    );
    await db.fuehreAus(AlbumAnlegen('urlaub', 'Urlaub', DateTime(2026)));
    await db.fuehreAus(const AlbumFuellen('urlaub', ['foto']));

    final geholt = <String>[];
    paths.beschaffe = (relativ) async {
      geholt.add(relativ);
      final f = paths.absolute(relativ);
      await f.create(recursive: true);
      await f.writeAsString(relativ);
    };

    final offline = await OfflineAlben.oeffne(merkdatei);
    await offline.setze('urlaub', true);
    expect(await offline.holeAlbum(db, paths, 'urlaub'), 2);
    expect(geholt.toSet(), {
      'originals/foto.jpg',
      'thumbnails/foto.jpg',
      'previews/foto.jpg',
      'originals/video.mov',
    });
    expect(await offline.geschuetztePfade(db), containsAll(geholt));

    final neu = await OfflineAlben.oeffne(merkdatei);
    expect(neu.enthaelt('urlaub'), isTrue);

    // Was das Album hier belegt: die geholten Dateien, sonst nichts (#220).
    var bytes = 0;
    for (final r in geholt) {
      bytes += await paths.absolute(r).length();
    }
    expect(await offline.belegt(db, paths, 'urlaub'), bytes);
  });

  test('die Pflege lädt angeheftete Alben nur im WLAN nach (#220)', () async {
    final offline = await OfflineAlben.oeffne(merkdatei);
    var wlan = false;
    final sitzung = Sitzung()
      ..db = db
      ..paths = paths
      ..offlineAlben = offline
      ..imWlan = () async => wlan;
    expect(
      await sitzung.darfOfflineNachladen(),
      isFalse,
      reason: 'nichts angeheftet',
    );
    await offline.setze('urlaub', true);
    expect(
      await sitzung.darfOfflineNachladen(),
      isFalse,
      reason: 'über Mobilfunk nicht von selbst',
    );
    wlan = true;
    expect(await sitzung.darfOfflineNachladen(), isTrue);
  });

  test(
    'unvollständige Auswahl bleibt für einen späteren Versuch gemerkt',
    () async {
      await aufnahme('foto');
      await db.fuehreAus(AlbumAnlegen('urlaub', 'Urlaub', DateTime(2026)));
      await db.fuehreAus(const AlbumFuellen('urlaub', ['foto']));
      paths.beschaffe = (_) async => throw const FileSystemException('offline');

      final offline = await OfflineAlben.oeffne(merkdatei);
      await offline.setze('urlaub', true);
      await expectLater(
        offline.holeAlbum(db, paths, 'urlaub'),
        throwsA(isA<FileSystemException>()),
      );
      expect((await OfflineAlben.oeffne(merkdatei)).enthaelt('urlaub'), isTrue);
    },
  );
}
