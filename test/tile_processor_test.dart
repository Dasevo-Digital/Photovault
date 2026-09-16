import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/services/tile_processor.dart';

/// Reine Zerlegungs-/Zusammensetzungs-Tests, unabhängig von ONNX/Real-ESRGAN
/// (siehe RestoreService, das processInTiles nur mit einer echten
/// Inferenz-Funktion füttert). [infer] ist hier immer eine reine
/// Identitäts-/Skalierungsfunktion.
void main() {
  img.Image gradientImage(int width, int height) {
    final image = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixelRgb(x, y, (x * 255 / (width - 1)).round(), (y * 255 / (height - 1)).round(), 128);
      }
    }
    return image;
  }

  group('splitIntoTiles', () {
    test('deckt das gesamte Bild ohne Lücken ab', () {
      final source = gradientImage(200, 150);
      final tiles = splitIntoTiles(source, tileSize: 64, overlap: 16);

      final covered = List.generate(source.height, (_) => List.filled(source.width, false));
      for (final tile in tiles) {
        for (var y = 0; y < tile.image.height; y++) {
          for (var x = 0; x < tile.image.width; x++) {
            covered[tile.y + y][tile.x + x] = true;
          }
        }
      }
      expect(covered.every((row) => row.every((c) => c)), isTrue);
    });

    test('Bild kleiner als tileSize ergibt genau eine Kachel in Originalgröße', () {
      final source = gradientImage(40, 30);
      final tiles = splitIntoTiles(source, tileSize: 512, overlap: 16);
      expect(tiles, hasLength(1));
      expect(tiles.single.image.width, 40);
      expect(tiles.single.image.height, 30);
    });

    test('jede Kachel ist höchstens tileSize groß', () {
      final source = gradientImage(300, 300);
      final tiles = splitIntoTiles(source, tileSize: 100, overlap: 20);
      for (final tile in tiles) {
        expect(tile.image.width, lessThanOrEqualTo(100));
        expect(tile.image.height, lessThanOrEqualTo(100));
      }
    });
  });

  group('processInTiles: Identitäts-Rekonstruktion', () {
    test('scaleFactor=1 mit Identitäts-Inferenz reproduziert das Original pixelgenau', () async {
      final source = gradientImage(128, 96);
      final result = await processInTiles(
        source,
        tileSize: 32,
        overlap: 8,
        scaleFactor: 1,
        infer: (tile) async => tile,
      );

      expect(result.width, source.width);
      expect(result.height, source.height);
      for (var y = 0; y < source.height; y += 5) {
        for (var x = 0; x < source.width; x += 5) {
          final expected = source.getPixel(x, y);
          final actual = result.getPixel(x, y);
          expect(actual.r, expected.r, reason: 'x=$x y=$y (r)');
          expect(actual.g, expected.g, reason: 'x=$x y=$y (g)');
          expect(actual.b, expected.b, reason: 'x=$x y=$y (b)');
        }
      }
    });

    test('einzelne, gleichförmige Kachel (Bild kleiner als tileSize) bleibt unverändert', () async {
      final source = gradientImage(50, 40);
      final result = await processInTiles(
        source,
        tileSize: 512,
        overlap: 16,
        scaleFactor: 1,
        infer: (tile) async => tile,
      );
      expect(result.getPixel(10, 10).r, source.getPixel(10, 10).r);
    });
  });

  group('processInTiles: Kachel-Nahtstellen', () {
    test('scaleFactor=2 mit einfacher Verdopplungs-Inferenz hat keine sichtbaren Sprünge an Kachelgrenzen', () async {
      final source = gradientImage(128, 128);
      final result = await processInTiles(
        source,
        tileSize: 32,
        overlap: 8,
        scaleFactor: 2,
        infer: (tile) async => img.copyResize(tile, width: tile.width * 2, height: tile.height * 2,
            interpolation: img.Interpolation.linear),
      );

      expect(result.width, 256);
      expect(result.height, 256);

      // Bei einem glatten Verlauf darf sich der Helligkeitswert zwischen
      // direkt benachbarten Ausgabe-Pixeln nirgendwo sprunghaft ändern –
      // eine harte Kachel-Naht würde hier als große Differenz auffallen.
      var maxJump = 0;
      for (var y = 0; y < result.height; y++) {
        for (var x = 1; x < result.width; x++) {
          final diff = (result.getPixel(x, y).r - result.getPixel(x - 1, y).r).abs().toInt();
          if (diff > maxJump) maxJump = diff;
        }
      }
      expect(maxJump, lessThan(10));
    });

    test('bricht bei isCancelled sauber ab, ohne zu hängen', () async {
      final source = gradientImage(128, 128);
      var callCount = 0;
      final result = await processInTiles(
        source,
        tileSize: 32,
        overlap: 8,
        scaleFactor: 1,
        infer: (tile) async {
          callCount++;
          return tile;
        },
        isCancelled: () => callCount >= 2,
      );
      expect(callCount, 2);
      expect(result.width, source.width); // Ergebnis existiert, ist aber unvollständig – Aufrufer verwirft es.
    });
  });

  test('onProgress wird für jede Kachel mit steigendem done-Zähler aufgerufen', () async {
    final source = gradientImage(96, 64);
    final progressCalls = <(int, int)>[];
    await processInTiles(
      source,
      tileSize: 32,
      overlap: 8,
      scaleFactor: 1,
      infer: (tile) async => tile,
      onProgress: (done, total) => progressCalls.add((done, total)),
    );
    expect(progressCalls, isNotEmpty);
    expect(progressCalls.last.$1, progressCalls.last.$2); // letzter Aufruf: done == total
    for (var i = 1; i < progressCalls.length; i++) {
      expect(progressCalls[i].$1, progressCalls[i - 1].$1 + 1);
    }
  });
}
