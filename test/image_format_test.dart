import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:kern/db/database.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/raw_formats.dart';
import 'package:kern/services/storage_paths.dart';

import 'fixtures/sample_images.dart';

/// Prüft die Formatkette mit ECHTEN Bilddaten statt nur mit Dateinamen –
/// die Testbilder werden dafür zur Laufzeit erzeugt (siehe
/// fixtures/sample_images.dart), es liegt also kein fremdes Bildmaterial im
/// Repository.
///
/// Bewusst NICHT abgedeckt: HEIC/HEIF und RAW. Beide lassen sich weder mit
/// dem reinen Dart-Paket `image` erzeugen noch dekodieren; sie laufen über
/// die native macOS-Schicht (macos/Runner/ImageConverter.swift), die in
/// `flutter test` gar nicht existiert. Dafür gibt es
/// `tool/fetch_format_samples.sh` plus die Anleitung in
/// test/fixtures/README.md.
void main() {
  late Directory tempRoot;
  late Directory sourceDir;
  late AppDatabase db;
  late StoragePaths paths;
  late ImportService importService;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('photo_vault_format_test_');
    sourceDir = Directory(p.join(tempRoot.path, 'incoming'))..createSync();
    paths = await StoragePaths.forTesting(
      Directory(p.join(tempRoot.path, 'library')),
    );
    db = AppDatabase(NativeDatabase.memory());
    importService = ImportService(db, paths);
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  File writeSample(String name, String extension) {
    final file = File(p.join(sourceDir.path, name))
      ..writeAsBytesSync(sampleBytes(extension));
    return file;
  }

  group('synthetisch erzeugbare Formate', () {
    for (final extension in encodableSampleFormats) {
      test(
        '$extension wird erkannt, importiert und bekommt ein Thumbnail',
        () async {
          final file = writeSample('probe$extension', extension);

          expect(
            importService.isSupported(file.path),
            isTrue,
            reason: '$extension muss als Bildformat gelten',
          );

          final result = await importService.importFile(file.path);
          expect(
            result.outcome,
            ImportOutcome.imported,
            reason: 'Import von $extension schlug fehl: ${result.error}',
          );

          final assets = await db.select(db.assets).get();
          expect(assets, hasLength(1));
          final asset = assets.single;

          // Die Maße müssen aus den echten Bilddaten stammen, nicht geraten sein.
          expect(asset.widthPx, 64);
          expect(asset.heightPx, 48);

          // Original liegt unverändert in der Bibliothek …
          expect(
            File(paths.absolute(asset.relativePath).path).existsSync(),
            isTrue,
          );
          // … und das Thumbnail wurde tatsächlich erzeugt und ist dekodierbar.
          final thumbPath = asset.thumbnailRelativePath;
          expect(thumbPath, isNotNull, reason: 'kein Thumbnail für $extension');
          final thumbBytes = File(
            paths.absolute(thumbPath!).path,
          ).readAsBytesSync();
          expect(
            img.decodeImage(thumbBytes),
            isNotNull,
            reason: 'Thumbnail für $extension ist nicht dekodierbar',
          );
        },
      );
    }
  });

  test('PSD: importiert, mit Miniatur und JPEG-Vorschau', () async {
    // Photoshop-Dateien liest `image`, Flutter zeigt sie aber nicht an.
    // Deshalb muss neben der Miniatur immer eine Vorschau entstehen –
    // auch ohne nativen Wandler, wie hier im Test.
    final file = File(p.join(sourceDir.path, 'probe.psd'))
      ..writeAsBytesSync(File('test/fixtures/psd/probe.psd').readAsBytesSync());
    expect(importService.isSupported(file.path), isTrue);
    expect(unterstuetztesFormat('IMG_2258.PSD'), isTrue);
    expect(unterstuetztesFormat('IMG_2258.xyz'), isFalse);

    final result = await importService.importFile(file.path);
    expect(result.outcome, ImportOutcome.imported, reason: result.error);
    final asset = (await db.select(db.assets).get()).single;
    expect((asset.widthPx, asset.heightPx), (48, 32));
    expect(asset.dateiformat, 'psd');
    for (final pfad in [
      asset.thumbnailRelativePath,
      asset.previewRelativePath,
    ]) {
      expect(pfad, isNotNull);
      final bild = img.decodeJpg(
        File(paths.absolute(pfad!).path).readAsBytesSync(),
      );
      expect(bild, isNotNull, reason: '$pfad ist kein JPEG');
    }
    final vorschau = img.decodeJpg(
      File(paths.absolute(asset.previewRelativePath!).path).readAsBytesSync(),
    )!;
    expect((vorschau.width, vorschau.height), (48, 32));
    // Die Farben stammen aus der Datei: links oben blau, rechts unten gelb.
    final lo = vorschau.getPixel(0, 0);
    final ru = vorschau.getPixel(47, 31);
    expect(lo.b > lo.r && lo.b > lo.g, isTrue, reason: '$lo');
    expect(ru.r > ru.b && ru.g > ru.b, isTrue, reason: '$ru');
  });

  test(
    'erzeugte Beispieldateien tragen wirklich die passende Formatsignatur',
    () {
      // Schützt davor, dass der Generator still auf ein anderes Format
      // ausweicht (dann würde die Formatprüfung oben nur JPEG testen).
      final signatures = <String, List<int>>{
        '.png': [0x89, 0x50, 0x4E, 0x47],
        '.jpg': [0xFF, 0xD8, 0xFF],
        '.bmp': [0x42, 0x4D],
        '.gif': [0x47, 0x49, 0x46],
      };
      signatures.forEach((extension, magic) {
        final bytes = sampleBytes(extension);
        expect(
          bytes.take(magic.length).toList(),
          magic,
          reason: 'falsche Signatur für $extension',
        );
      });
    },
  );

  test(
    'nicht erzeugbare Formate melden das klar, statt still auszuweichen',
    () {
      expect(() => sampleBytes('.heic'), throwsArgumentError);
      expect(() => sampleBytes('.arw'), throwsArgumentError);
    },
  );

  test('alle RAW-Endungen gelten als unterstützt', () {
    for (final extension in rawImageExtensions) {
      expect(
        importService.isSupported('kamera$extension'),
        isTrue,
        reason: '$extension fehlt in den unterstützten Bildformaten',
      );
    }
  });

  test(
    'HEIC/HEIF gelten als unterstützt, auch wenn sie hier nicht dekodierbar sind',
    () {
      expect(importService.isSupported('foto.heic'), isTrue);
      expect(importService.isSupported('foto.HEIF'), isTrue);
    },
  );

  test('fremde Dateitypen werden abgelehnt', () {
    for (final name in [
      'notiz.txt',
      'archiv.zip',
      'tabelle.csv',
      'ohne_endung',
    ]) {
      expect(
        importService.isSupported(name),
        isFalse,
        reason: '$name darf nicht importierbar sein',
      );
    }
  });
}
