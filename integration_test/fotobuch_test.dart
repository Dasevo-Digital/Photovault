// ignore_for_file: avoid_print
// Das Fotobuch im laufenden Programm, mit dem Bildwandler der Plattform
// (macOS: Core Image, Linux und Windows: die mitgelieferten Werkzeuge).
//
// Was der Unittest nicht sehen kann: ob der Wandler die gedrehte Lage
// aus dem EXIF anwendet und in der verlangten Grösse liefert – und ob
// danach im PDF kein Aufnahmeort mehr steckt.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:kern/db/database.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/fotobuch.dart';
import 'package:photo_vault/services/native_image_converter.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/fotobuch_export.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Fotobuch mit dem Wandler der Plattform', (tester) async {
    await tester.runAsync(() async {
      final wurzel = Directory.systemTemp.createTempSync('pv_fotobuch_');
      final db = AppDatabase(NativeDatabase.memory());
      final paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'lib')),
      );
      final library = LibraryState()
        ..db = db
        ..paths = paths
        ..backupService = BackupService(db, paths);

      // Gespeichert quer (1200 × 800), laut EXIF um 90° gedreht – im Bild
      // also hoch. Mit Aufnahmeort.
      final bild = img.Image(width: 1200, height: 800);
      for (var y = 0; y < 800; y++) {
        for (var x = 0; x < 1200; x++) {
          bild.setPixelRgb(x, y, x * 255 ~/ 1200, y * 255 ~/ 800, 120);
        }
      }
      bild.exif.imageIfd.orientation = 6;
      bild.exif.gpsIfd.gpsLatitude = 52.370216;
      bild.exif.gpsIfd.gpsLongitude = 9.735603;
      for (final id in ['a', 'b']) {
        final datei = paths.absolute('originals/$id.jpg');
        await datei.parent.create(recursive: true);
        await datei.writeAsBytes(img.encodeJpg(bild, quality: 90));
        await db
            .into(db.assets)
            .insert(
              AssetsCompanion.insert(
                id: id,
                originalFileName: '$id.jpg',
                relativePath: 'originals/$id.jpg',
                checksum: 'pruef-$id',
                type: 'IMAGE',
                fileCreatedAt: DateTime(2025, 6, 1),
                importedAt: DateTime(2026),
                locationCity: const Value('Hannover'),
              ),
            );
      }

      final gedreht = await NativeImageConverter.convertToJpegBytes(
        paths.absolute('originals/a.jpg'),
        maxDimension: 600,
      );
      expect(gedreht, isNotNull, reason: 'kein Wandler');
      final groesse = jpegGroesse(jpegOhneBeipackzettel(gedreht!));
      print('FOTOBUCH gewandelt $groesse');
      expect(groesse, (400, 600), reason: 'gedreht und verkleinert');

      final ziel = File(p.join(wurzel.path, 'buch.pdf'));
      final uhr = Stopwatch()..start();
      final ergebnis = await erstelleFotobuch(
        library,
        await db.select(db.assets).get(),
        (
          titel: 'Sommer',
          format: Fotobuchformat.a4Hoch,
          jeSeite: 1,
          angaben: {Fotobuchangabe.datum, Fotobuchangabe.ort},
        ),
        ziel: ziel,
        untertitel: null,
        datum: (a) => '1. Juni 2025',
        sprache: 'de',
        fortschritt: (_) {},
        abbruch: () => false,
      );
      final pdf = await ziel.readAsBytes();
      final text = String.fromCharCodes(pdf);
      print(
        'FOTOBUCH $ergebnis, ${pdf.length} B in ${uhr.elapsedMilliseconds} ms',
      );
      expect(ergebnis, (seiten: 3, bilder: 2));
      expect(text, isNot(contains('Exif')));
      expect(text, contains('Garamond'));
      await db.close();
      wurzel.deleteSync(recursive: true);
    });
  });
}
