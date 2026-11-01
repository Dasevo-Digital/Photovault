import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/abgleich/dateibeschaffung.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault_mobil/bilder.dart';
import 'package:photo_vault_mobil/offline_alben.dart';

/// Der Betrachter zeigt jedes Foto in voller Auflösung (#256).
///
/// Bis 3.49.9 bekam das Handy von HEIC, RAW und DNG nur die Vorschau mit
/// 2048 Punkten an der langen Seite – und ein iPhone fotografiert in HEIC.
void main() {
  late Directory ordner;
  late AppDatabase db;
  late StoragePaths paths;

  setUp(() async {
    ordner = Directory.systemTemp.createTempSync('pv_vollbild_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(
      Directory(p.join(ordner.path, 'lib')),
    );
  });

  tearDown(() async {
    await db.close();
    await ordner.delete(recursive: true);
  });

  Future<AssetData> aufnahme(
    String id,
    String endung, {
    bool vorschau = true,
    String? entwickelt,
  }) async {
    await db.insertAsset(
      AssetsCompanion.insert(
        id: id,
        originalFileName: '$id.$endung',
        relativePath: 'originals/$id.$endung',
        thumbnailRelativePath: Value('thumbnails/$id.jpg'),
        previewRelativePath: Value(vorschau ? 'previews/$id.jpg' : null),
        developedRelativePath: Value(entwickelt),
        checksum: 'pruef-$id',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2025),
        importedAt: DateTime(2026),
      ),
    );
    return (await db.assetById(id))!;
  }

  String? relativ(ImageProvider? bild) =>
      bild == null ? null : (bild as BibliotheksBild).relativ;

  test('was der Betrachter für die volle Auflösung lädt', () async {
    final heic = await aufnahme('heic', 'heic');
    final jpeg = await aufnahme('jpeg', 'jpg', vorschau: false);
    final gross = await aufnahme('gross', 'jpg');
    final dng = await aufnahme('dng', 'dng', entwickelt: 'developed/dng.jpg');

    expect(
      relativ(vollesBild(paths, heic)),
      Dateibeschaffung.vollbildPfad(heic),
      reason: 'vom Server gewandelt',
    );
    expect(
      relativ(vollesBild(paths, gross)),
      'originals/gross.jpg',
      reason: 'ein JPEG mit Vorschau: das Original selbst',
    );
    expect(vollesBild(paths, jpeg), isNull, reason: 'zeigt schon das Original');
    expect(vollesBild(paths, dng), isNull, reason: 'die Entwicklung ist es');
  });

  test('die volle Auflösung kommt vom eigenen Abruf des Servers', () async {
    final heic = await aufnahme('a-b-c', 'heic');

    final pfad = Dateibeschaffung.vollbildPfad(heic);

    expect(pfad, startsWith('previews/voll/a-b-c/'));
    expect(Dateibeschaffung.adresse(pfad), 'api/v1/aufnahmen/a-b-c/voll');
    expect(
      Dateibeschaffung.adresse('previews/a-b-c.jpg'),
      'api/v1/dateien/previews/a-b-c.jpg',
    );

    // Wird das Foto restauriert, gilt die alte Fassung nicht mehr.
    final restauriert = heic.copyWith(
      restoredRelativePath: const Value('restored/a-b-c.tif'),
    );
    expect(Dateibeschaffung.vollbildPfad(restauriert), isNot(pfad));
  });

  test('ein Offline-Album hält die volle Auflösung mit', () async {
    final heic = await aufnahme('heic', 'heic');
    await aufnahme('jpeg', 'jpg', vorschau: false);
    await db.fuehreAus(AlbumAnlegen('urlaub', 'Urlaub', DateTime(2026)));
    await db.fuehreAus(const AlbumFuellen('urlaub', ['heic', 'jpeg']));
    final geholt = <String>[];
    paths.beschaffe = (relativ) async {
      geholt.add(relativ);
      await paths.absolute(relativ).create(recursive: true);
    };

    final offline = await OfflineAlben.oeffne(
      File(p.join(ordner.path, 'offline_alben.json')),
    );
    await offline.setze('urlaub', true);
    await offline.holeAlbum(db, paths, 'urlaub');

    final voll = Dateibeschaffung.vollbildPfad(heic);
    expect(geholt, contains(voll));
    expect(geholt.where((r) => r.startsWith('previews/voll/')), [
      voll,
    ], reason: 'ein JPEG braucht keine Wandlung');
    expect(await offline.geschuetztePfade(db), contains(voll));
  });
}
