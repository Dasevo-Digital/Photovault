import 'package:photo_vault/services/library_location.dart';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:exif/exif.dart';
import 'package:kern/services/exif_gps.dart';
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
    LibraryLocation.nutzeFuerTests(anker: tempRoot);
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
    LibraryLocation.zuruecksetzenFuerTests();
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

  test('auch ein unbearbeitetes Foto behält Datum und Kamera (#403)', () async {
    // Der Wandler streift jeden EXIF-Anhang ab. Vorher kamen die
    // Aufnahmeangaben nur bei bearbeiteten Fotos zurück; ein unbearbeitetes
    // stand nach „Web – 2048 px“ im nächsten Programm am Exporttag.
    final rein = File(p.join(tempRoot.path, 'feld.jpg'))
      ..writeAsBytesSync(jpeg(0, 200, 0));
    final r = await ImportService(db, paths).importFile(rein.path);
    final id = r.assetId!;
    await (db.update(db.assets)..where((t) => t.id.equals(id))).write(
      AssetsCompanion(
        fileCreatedAt: Value(DateTime(2019, 6, 2, 14, 5, 9)),
        cameraMake: const Value('Beispielkamera'),
        cameraModel: const Value('Modell 1'),
        latitude: const Value(51.3),
        longitude: const Value(12.4),
      ),
    );
    final a = (await db.assetById(id))!;
    final name = await ExportService(paths).exportAsset(
      a,
      ziel.path,
      vorgabe: const Exportvorgabe(nachJpeg: true, maxKante: 2048),
    );
    final bild = img.decodeJpg(
      File(p.join(ziel.path, name)).readAsBytesSync(),
    )!;
    expect(
      bild.exif.exifIfd['DateTimeOriginal']?.toString(),
      '2019:06:02 14:05:09',
    );
    expect(bild.exif.imageIfd.make, 'Beispielkamera');
    expect(bild.exif.gpsIfd.isEmpty, isTrue, reason: 'der Ort bleibt daheim');
  });

  group('der Ort geht in Bild und Beilage gemeinsam hinaus (BEA-128)', () {
    Future<AssetData> mitOrt() async {
      final rein = File(p.join(tempRoot.path, 'gipfel.jpg'))
        ..writeAsBytesSync(jpeg(0, 0, 200));
      final r = await ImportService(db, paths).importFile(rein.path);
      await (db.update(db.assets)..where((t) => t.id.equals(r.assetId!))).write(
        const AssetsCompanion(
          latitude: Value(-33.856784),
          longitude: Value(151.215297),
        ),
      );
      return (await db.assetById(r.assetId!))!;
    }

    ({img.Image bild, String beilage}) lies(String name) => (
      bild: img.decodeJpg(File(p.join(ziel.path, name)).readAsBytesSync())!,
      beilage: File(
        p.setExtension(p.join(ziel.path, name), '.xmp'),
      ).readAsStringSync(),
    );

    test('„Web – 2048 px“: weder im Bild noch in der Beilage', () async {
      // Vorher trug das JPEG keinen Ort, die Beilage daneben aber GPS.
      final name = await ExportService(paths).exportAsset(
        await mitOrt(),
        ziel.path,
        vorgabe: Exportvorgabe.ausGroesse(Exportgroesse.web),
      );
      final aus = lies(name);
      expect(aus.bild.exif.gpsIfd.isEmpty, isTrue);
      expect(aus.beilage, isNot(contains('GPSLatitude')));
      expect(aus.beilage, isNot(contains('GPSLongitude')));
    });

    test('mit „Ort mitgeben“ in beiden', () async {
      final name = await ExportService(paths).exportAsset(
        await mitOrt(),
        ziel.path,
        vorgabe: const Exportvorgabe(
          nachJpeg: true,
          maxKante: 2048,
          ortMitgeben: true,
        ),
      );
      final aus = lies(name);
      // Gelesen wie beim Import: drei Brüche und die Himmelsrichtung.
      final ort = parseExifGps(
        await readExifFromBytes(
          File(p.join(ziel.path, name)).readAsBytesSync(),
        ),
      );
      expect(ort?.latitude, closeTo(-33.856784, 1e-5));
      expect(ort?.longitude, closeTo(151.215297, 1e-5));
      expect(aus.beilage, contains('exif:GPSLatitude="33,'));
      expect(aus.beilage, contains('exif:GPSLongitude="151,'));
    });

    test(
      'das unveränderte Original behält den Ort auch in der Beilage',
      () async {
        final name = await ExportService(
          paths,
        ).exportAsset(await mitOrt(), ziel.path);
        expect(lies(name).beilage, contains('exif:GPSLatitude="33,'));
      },
    );

    test('jede gerenderte Vorgabe und der Datenschutzexport ohne Ort', () {
      for (final g in Exportgroesse.values) {
        if (g == Exportgroesse.original) continue;
        expect(
          Exportvorgabe.ausGroesse(g).ortMitgeben,
          isFalse,
          reason: g.name,
        );
      }
      expect(Exportvorgabe.datenschutz().ortMitgeben, isFalse);
      expect(
        const Exportvorgabe(
          metadatenEntfernen: true,
          ortMitgeben: true,
        ).ortMitgeben,
        isFalse,
        reason: 'der Datenschutzexport gibt nie einen Ort mit',
      );
      ExportPresetData preset({required bool nachJpeg}) => ExportPresetData(
        id: 1,
        name: 'Vorgabe',
        nachJpeg: nachJpeg,
        maxKante: 1600,
        qualitaet: 0.8,
        namensmuster: '{name}',
        xmpDaneben: true,
        erstelltAm: DateTime(2026),
      );
      expect(
        Exportvorgabe.ausPreset(preset(nachJpeg: true)).ortMitgeben,
        isFalse,
      );
      expect(
        Exportvorgabe.ausPreset(preset(nachJpeg: false)).ortMitgeben,
        isTrue,
      );
    });
  });
}
