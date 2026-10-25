import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/export_service.dart';

/// Der Export am Rechner nimmt die Bearbeitung mit (#212) – wie das
/// Herunterladen als JPEG im Browser und auf dem Telefon. „Original“ bleibt
/// das unveränderte Original.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempRoot;
  late AppDatabase db;
  late StoragePaths paths;
  late Directory ziel;

  Uint8List jpeg(int r, int g, int b) {
    final bild = img.Image(width: 8, height: 8);
    img.fill(bild, color: img.ColorRgb8(r, g, b));
    return Uint8List.fromList(img.encodeJpg(bild));
  }

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_export_bearb_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(
      Directory(p.join(tempRoot.path, 'lib')),
    );
    ziel = Directory(p.join(tempRoot.path, 'ziel'))..createSync();
    // Der Bildwandler (macOS-Kanal bzw. Werkzeuge) gibt hier die Datei
    // zurück, die er bekommt – so zeigt das Ergebnis, woraus gerendert
    // wurde.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('photo_vault/image_convert'),
          (aufruf) async => switch (aufruf.method) {
            'convertToJpeg' => File(
              (aufruf.arguments as Map)['path'] as String,
            ).readAsBytesSync(),
            _ => null,
          },
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('photo_vault/image_convert'),
          null,
        );
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  test(
    'JPEG aus der Bearbeitung, mit Datum; Original bleibt Original',
    () async {
      final rein = File(p.join(tempRoot.path, 'hafen.jpg'))
        ..writeAsBytesSync(jpeg(200, 0, 0));
      final r = await ImportService(db, paths).importFile(rein.path);
      final id = r.assetId!;
      // Die gespeicherte Bearbeitung: blau statt rot.
      final entwickelt = paths.developedRelativePath(id);
      paths.absolute(entwickelt)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(jpeg(0, 0, 200));
      await (db.update(db.assets)..where((t) => t.id.equals(id))).write(
        AssetsCompanion(
          developedRelativePath: Value(entwickelt),
          fileCreatedAt: Value(DateTime(2024, 11, 13, 10, 48, 28)),
        ),
      );
      final a = (await db.assetById(id))!;
      final export = ExportService(paths);

      final jpegName = await export.exportAsset(
        a,
        ziel.path,
        vorgabe: const Exportvorgabe(nachJpeg: true),
      );
      final bild = img.decodeJpg(
        File(p.join(ziel.path, jpegName)).readAsBytesSync(),
      )!;
      final pixel = bild.getPixel(4, 4);
      expect(pixel.b, greaterThan(pixel.r), reason: 'aus der Bearbeitung');
      expect(
        bild.exif.exifIfd['DateTimeOriginal']?.toString(),
        '2024:11:13 10:48:28',
      );

      final originalName = await export.exportAsset(a, ziel.path);
      expect(
        File(p.join(ziel.path, originalName)).readAsBytesSync(),
        rein.readAsBytesSync(),
        reason: '„Original“ kopiert die unveränderte Datei',
      );
    },
  );
}
