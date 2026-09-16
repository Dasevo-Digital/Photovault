import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/export_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/services/textstellen.dart';

void main() {
  test('Datenschutzexport verändert den Gesichtsbereich', () {
    final source = img.Image(width: 100, height: 100);
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        source.setPixelRgb(x, y, x * 2, y * 2, (x + y) % 255);
      }
    }
    final before = Uint8List.fromList(img.encodeJpg(source, quality: 100));
    final result = verdeckeGesichter((
      bytes: before,
      boxen: const [(0.25, 0.25, 0.5, 0.5)],
    ));
    final decoded = img.decodeJpg(result)!;
    final original = img.decodeJpg(before)!;
    expect(decoded.getPixel(50, 50), isNot(original.getPixel(50, 50)));
    expect(result, isNotEmpty);
  });

  test('nur kennzeichentypische OCR-Zeilen werden ausgewählt', () {
    final json = textstellenNachJson(const [
      Textstelle(text: 'B AB 1234', links: .1, oben: .2, breite: .4, hoehe: .1),
      Textstelle(text: 'SOMMER', links: .1, oben: .5, breite: .4, hoehe: .1),
      Textstelle(text: 'A1', links: .1, oben: .7, breite: .4, hoehe: .1),
    ]);
    expect(kennzeichenBoxen(json), [(0.1, 0.2, 0.4, 0.1)]);
  });

  /// **Der Datenschutzexport verspricht etwas – und muss es halten.**
  ///
  /// „JPEG bis 2048 Pixel, ohne EXIF, GPS oder XMP" steht in der Auswahl.
  /// Erreicht wird das durch **Neurendern**; was sich nicht rendern lässt,
  /// kann diesen Weg nicht gehen. Vorher fiel genau das auf den Zweig
  /// „dann eben die Originaldatei kopieren" zurück, und ein Video ging
  /// bitgleich mit Ort, Gerät und Zeit hinaus. Der Satz „ein Export soll
  /// nichts auslassen" stimmt für eine Grössenvorgabe und kehrt sich bei
  /// einer Zusage um.
  group('Datenschutzexport hält seine Zusage', () {
    late Directory wurzel;
    late AppDatabase db;
    late StoragePaths paths;
    late Directory ziel;

    setUp(() async {
      wurzel = Directory.systemTemp.createTempSync('pv_datenschutz_');
      db = AppDatabase(NativeDatabase.memory());
      paths = await StoragePaths.forTesting(
          Directory(p.join(wurzel.path, 'library')));
      ziel = Directory(p.join(wurzel.path, 'aus'))..createSync();
    });

    tearDown(() async {
      await db.close();
      wurzel.deleteSync(recursive: true);
    });

    Future<AssetData> aufnahme(String id, String name, String typ) async {
      final relativ = 'originals/$id${p.extension(name)}';
      final datei = paths.absolute(relativ);
      await datei.parent.create(recursive: true);
      datei.writeAsBytesSync(List<int>.generate(2048, (i) => i % 251));
      await db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: name,
            relativePath: relativ,
            checksum: 'c_$id',
            type: typ,
            fileCreatedAt: DateTime(2026, 5, 1),
            importedAt: DateTime(2026, 5, 2),
          ));
      return (db.select(db.assets)..where((t) => t.id.equals(id))).getSingle();
    }

    test('ein Video wird ausgelassen statt unverändert ausgeliefert',
        () async {
      final video = await aufnahme('v1', 'strand.mp4', 'VIDEO');

      await expectLater(
        ExportService(paths).exportAsset(video, ziel.path,
            vorgabe: Exportvorgabe.datenschutz()),
        throwsA(isA<DatenschutzNichtMoeglich>()
            .having((e) => e.dateiname, 'dateiname', 'strand.mp4')),
      );
      expect(ziel.listSync(), isEmpty,
          reason: 'Am Zielort darf nichts liegen – auch keine halbe Kopie.');
    });

    test('die Gegenprobe: eine Grössenvorgabe kopiert dasselbe Video sehr wohl',
        () async {
      final video = await aufnahme('v2', 'strand.mp4', 'VIDEO');

      final name = await ExportService(paths).exportAsset(video, ziel.path,
          vorgabe: const Exportvorgabe(nachJpeg: true, maxKante: 2048));

      final ergebnis = File(p.join(ziel.path, name));
      expect(ergebnis.existsSync(), isTrue);
      expect(ergebnis.readAsBytesSync(),
          paths.absolute(video.relativePath).readAsBytesSync(),
          reason: 'Ohne Datenschutzvorgabe bleibt „nichts auslassen" richtig: '
              'Ein Video, das keine Grössenvorgabe annehmen kann, geht '
              'unverändert mit.');
    });
  });
}
