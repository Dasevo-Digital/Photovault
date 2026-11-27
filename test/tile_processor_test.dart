import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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
        image.setPixelRgb(
          x,
          y,
          (x * 255 / (width - 1)).round(),
          (y * 255 / (height - 1)).round(),
          128,
        );
      }
    }
    return image;
  }

  group('splitIntoTiles', () {
    test('deckt das gesamte Bild ohne Lücken ab', () {
      final source = gradientImage(200, 150);
      final tiles = splitIntoTiles(source, tileSize: 64, overlap: 16);

      final covered = List.generate(
        source.height,
        (_) => List.filled(source.width, false),
      );
      for (final tile in tiles) {
        for (var y = 0; y < tile.image.height; y++) {
          for (var x = 0; x < tile.image.width; x++) {
            covered[tile.y + y][tile.x + x] = true;
          }
        }
      }
      expect(covered.every((row) => row.every((c) => c)), isTrue);
    });

    test(
      'Bild kleiner als tileSize ergibt genau eine Kachel in Originalgröße',
      () {
        final source = gradientImage(40, 30);
        final tiles = splitIntoTiles(source, tileSize: 512, overlap: 16);
        expect(tiles, hasLength(1));
        expect(tiles.single.image.width, 40);
        expect(tiles.single.image.height, 30);
      },
    );

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
    test(
      'scaleFactor=1 mit Identitäts-Inferenz reproduziert das Original pixelgenau',
      () async {
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
      },
    );

    test(
      'einzelne, gleichförmige Kachel (Bild kleiner als tileSize) bleibt unverändert',
      () async {
        final source = gradientImage(50, 40);
        final result = await processInTiles(
          source,
          tileSize: 512,
          overlap: 16,
          scaleFactor: 1,
          infer: (tile) async => tile,
        );
        expect(result.getPixel(10, 10).r, source.getPixel(10, 10).r);
      },
    );
  });

  group('processInTiles: Kachel-Nahtstellen', () {
    test(
      'scaleFactor=2 mit einfacher Verdopplungs-Inferenz hat keine sichtbaren Sprünge an Kachelgrenzen',
      () async {
        final source = gradientImage(128, 128);
        final result = await processInTiles(
          source,
          tileSize: 32,
          overlap: 8,
          scaleFactor: 2,
          infer: (tile) async => img.copyResize(
            tile,
            width: tile.width * 2,
            height: tile.height * 2,
            interpolation: img.Interpolation.linear,
          ),
        );

        expect(result.width, 256);
        expect(result.height, 256);

        // Bei einem glatten Verlauf darf sich der Helligkeitswert zwischen
        // direkt benachbarten Ausgabe-Pixeln nirgendwo sprunghaft ändern –
        // eine harte Kachel-Naht würde hier als große Differenz auffallen.
        var maxJump = 0;
        for (var y = 0; y < result.height; y++) {
          for (var x = 1; x < result.width; x++) {
            final diff = (result.getPixel(x, y).r - result.getPixel(x - 1, y).r)
                .abs()
                .toInt();
            if (diff > maxJump) maxJump = diff;
          }
        }
        expect(maxJump, lessThan(10));
      },
    );

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
      expect(
        result.width,
        source.width,
      ); // Ergebnis existiert, ist aber unvollständig – Aufrufer verwirft es.
    });
  });

  test(
    'onProgress wird für jede Kachel mit steigendem done-Zähler aufgerufen',
    () async {
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
      expect(
        progressCalls.last.$1,
        progressCalls.last.$2,
      ); // letzter Aufruf: done == total
      for (var i = 1; i < progressCalls.length; i++) {
        expect(progressCalls[i].$1, progressCalls[i - 1].$1 + 1);
      }
    },
  );
  // Die Referenzpixel stammen aus der Zusammensetzung vor #500, die
  // Summen und Gewichte für jedes Ausgabepixel hielt. Hier rechnet sie
  // [_vollstaendig] mit der damaligen Aufteilung nach – damit ist belegt,
  // dass diese Nachbildung genau die alte Zusammensetzung ist. Die neue
  // muss mit derselben Aufteilung bitgleich herauskommen.
  test(
    'Bandweise Zusammensetzung erhält die bisherigen Referenzpixel bei ungleichen und großen Überlappungen',
    () async {
      final referenzen = [
        (
          (73, 59, 24, 7, 1),
          'd639ab1ea7db54e05576540e2ad2bdf2edb7546316fe91adf8ef575640424c9b',
        ),
        (
          (73, 59, 24, 13, 2),
          'e34152b7a5347cb150246c77023249d8d4f90fb23593e44212be0971022ebcf8',
        ),
        (
          (11, 9, 24, 7, 3),
          'c6f1e16ae8528418db97e35243904aaa1d6db9d0f3e4506c61bcb84c76b5e42f',
        ),
      ];
      for (final (abmessungen, hash) in referenzen) {
        final (w, h, t, o, skala) = abmessungen;
        final quelle = _muster(w, h);
        final alt = await _vollstaendig(
          quelle,
          xs: _alteAnfaenge(w, t, t - o),
          ys: _alteAnfaenge(h, t, t - o),
          tw: math.min(t, w),
          th: math.min(t, h),
          overlap: o,
          s: skala,
          infer: _versetzt(skala),
        );
        expect(
          sha256.convert(alt.getBytes()).toString(),
          hash,
          reason: 'Nachbildung der alten Zusammensetzung $abmessungen',
        );
      }
    },
  );

  test('die neue Zusammensetzung ist bitgleich mit der vollständigen, auch bei '
      'Überlappung über mehrere Kacheln', () async {
    for (final (w, h, t, o, skala) in [
      (73, 59, 24, 7, 1),
      (73, 59, 24, 13, 2),
      (11, 9, 24, 7, 3),
      (301, 203, 64, 16, 4),
      (130, 97, 32, 8, 2),
      (65, 33, 64, 16, 4),
    ]) {
      final quelle = _muster(w, h);
      final raster = Kachelraster(w, h, tileSize: t, overlap: o);
      final erwartet = await _vollstaendig(
        quelle,
        xs: raster.anfaengeX,
        ys: raster.anfaengeY,
        tw: raster.breite,
        th: raster.hoehe,
        overlap: o,
        s: skala,
        infer: _versetzt(skala),
      );
      final neu = await processInTiles(
        quelle,
        tileSize: t,
        overlap: o,
        scaleFactor: skala,
        infer: _versetzt(skala),
      );
      expect(
        sha256.convert(neu.getBytes()).toString(),
        sha256.convert(erwartet.getBytes()).toString(),
        reason: '${(w, h, t, o, skala)}',
      );
    }
  });

  group('Aufteilung (#500)', () {
    test(
      '4032 × 3024: gleich viele Kacheln, aber fast keine doppelte Fläche',
      () {
        for (final (kachel, alteFlaeche, neueFlaeche) in [
          (512, 1.36, 1.07),
          (256, 1.19, 1.14),
        ]) {
          final raster = Kachelraster(
            4032,
            3024,
            tileSize: kachel,
            overlap: 16,
          );
          final xs = _alteAnfaenge(4032, kachel, kachel - 16);
          final ys = _alteAnfaenge(3024, kachel, kachel - 16);
          final alt = xs.length * ys.length * kachel * kachel / (4032 * 3024);
          final neu = raster.flaeche / (4032 * 3024);
          expect(raster.anzahl, xs.length * ys.length, reason: '$kachel');
          expect(alt, closeTo(alteFlaeche, 0.01), reason: '$kachel');
          expect(neu, lessThan(neueFlaeche), reason: '$kachel');
        }
        final mac = Kachelraster(4032, 3024, tileSize: 512, overlap: 16);
        expect((mac.anfaengeX.length, mac.anfaengeY.length), (9, 7));
        expect((mac.breite, mac.hoehe), (463, 446));
      },
    );

    test('deckt jedes Bild ab, mit mindestens der Überlappung', () {
      for (final laenge in [1, 7, 24, 25, 39, 40, 41, 100, 511, 512, 513]) {
        for (final (t, o) in [(24, 7), (24, 13), (512, 16), (40, 39)]) {
          final raster = Kachelraster(laenge, 1, tileSize: t, overlap: o);
          final a = raster.anfaengeX;
          final k = raster.breite;
          final grund = '$laenge/$t/$o';
          expect(k, lessThanOrEqualTo(t), reason: grund);
          expect(a.first, 0, reason: grund);
          expect(a.last + k, laenge, reason: grund);
          for (var i = 1; i < a.length; i++) {
            expect(a[i], greaterThan(a[i - 1]), reason: grund);
            expect(
              a[i - 1] + k - a[i],
              greaterThanOrEqualTo(math.min(o, k)),
              reason: grund,
            );
          }
          // Nie mehr Kacheln als mit der alten Aufteilung.
          expect(
            a.length,
            lessThanOrEqualTo(_alteAnfaenge(laenge, t, t - o).length),
            reason: grund,
          );
        }
      }
    });

    test('ein Bild bis zur Kachelgrösse ist eine Kachel in seiner Grösse', () {
      final raster = Kachelraster(512, 300, tileSize: 512, overlap: 16);
      expect(raster.anzahl, 1);
      expect((raster.breite, raster.hoehe), (512, 300));
    });

    test('ein Vielfaches rundet die Kachel auf, statt sie aufzufüllen', () {
      final raster = Kachelraster(
        4032,
        3024,
        tileSize: 512,
        overlap: 32,
        vielfaches: 16,
      );
      expect(raster.breite % 16, 0);
      expect(raster.hoehe % 16, 0);
      expect(raster.breite, lessThanOrEqualTo(512));
      expect(raster.anfaengeX.last + raster.breite, 4032);
    });

    test('jede Kachel eines Bildes hat dieselbe Grösse', () async {
      final groessen = <(int, int)>{};
      await processInTiles(
        gradientImage(301, 203),
        tileSize: 64,
        overlap: 16,
        scaleFactor: 1,
        infer: (k) async {
          groessen.add((k.width, k.height));
          return k;
        },
      );
      expect(groessen, hasLength(1));
    });

    test(
      'ein punktweises Modell gibt mit alter und neuer Aufteilung dasselbe',
      () async {
        final quelle = _muster(301, 203);
        Future<img.Image> naechster(img.Image k) async => img.copyResize(
          k,
          width: k.width * 2,
          height: k.height * 2,
          interpolation: img.Interpolation.nearest,
        );
        final alt = await _vollstaendig(
          quelle,
          xs: _alteAnfaenge(301, 64, 48),
          ys: _alteAnfaenge(203, 64, 48),
          tw: 64,
          th: 64,
          overlap: 16,
          s: 2,
          infer: naechster,
        );
        final neu = await processInTiles(
          quelle,
          tileSize: 64,
          overlap: 16,
          scaleFactor: 2,
          infer: naechster,
        );
        expect(neu.getBytes(), alt.getBytes());
      },
    );
  });

  group('Speicher der Überblendung (#500)', () {
    test('bei 16384 Pixeln Breite kein Zeilenband von 537 MB mehr', () {
      // 4× auf 16384 × 6100: die breiteste erlaubte Vergrösserung.
      final plan = tileMemoryPlan(
        img.Image(width: 4096, height: 1525),
        tileSize: 512,
        overlap: 16,
        scaleFactor: 4,
      );
      const alt = 16384 * 512 * 4 * 16;
      expect(alt, greaterThan(536 * 1000 * 1000));
      expect(plan.bandBytes, lessThan(64 * 1000 * 1000));
    });

    test('die vierfache Zwischenkachel zählt mit', () {
      final quelle = img.Image(width: 4000, height: 3000);
      final direkt = tileMemoryPlan(
        quelle,
        tileSize: 512,
        overlap: 16,
        scaleFactor: 2,
      );
      final ueberVier = tileMemoryPlan(
        quelle,
        tileSize: 512,
        overlap: 16,
        scaleFactor: 2,
        modellfaktor: 4,
      );
      expect(ueberVier.outputBytes, direkt.outputBytes);
      expect(ueberVier.tileBytes, greaterThan(3 * direkt.tileBytes));
    });
  });

  test(
    'Speicherbudget stoppt vor der ersten Inferenz und erhält die Quelle',
    () async {
      final quelle = gradientImage(300, 200);
      final vorher = sha256.convert(quelle.getBytes()).toString();
      var aufrufe = 0;
      await expectLater(
        processInTiles(
          quelle,
          tileSize: 64,
          overlap: 8,
          scaleFactor: 4,
          maxWorkingBytes: 1024,
          infer: (kachel) async {
            aufrufe++;
            return kachel;
          },
        ),
        throwsA(isA<TileMemoryLimit>()),
      );
      expect(aufrufe, 0);
      expect(sha256.convert(quelle.getBytes()).toString(), vorher);
    },
  );

  test(
    'Ungültige Kachelparameter und abweichende Inferenzgröße werden abgefangen',
    () async {
      final quelle = gradientImage(30, 20);
      expect(
        () => splitIntoTiles(quelle, tileSize: 16, overlap: 16),
        throwsArgumentError,
      );
      await expectLater(
        processInTiles(
          quelle,
          tileSize: 16,
          overlap: -1,
          scaleFactor: 1,
          infer: (t) async => t,
        ),
        throwsArgumentError,
      );
      await expectLater(
        processInTiles(
          quelle,
          tileSize: 16,
          overlap: 4,
          scaleFactor: 2,
          infer: (t) async => t,
        ),
        throwsStateError,
      );
    },
  );
}

/// Ein Bild, in dem jedes Pixel anders ist.
img.Image _muster(int w, int h) {
  final quelle = img.Image(width: w, height: h);
  for (final p in quelle) {
    p.setRgb(
      (p.x * 41 + p.y * 13) % 256,
      (p.x * 7 + p.y * 19) % 256,
      (p.x * 17 + p.y * 3) % 256,
    );
  }
  return quelle;
}

/// Ein „Modell“, das vergrössert und jede Kachel ein wenig anders tönt –
/// sonst wäre jede Überblendung unsichtbar.
Future<img.Image> Function(img.Image) _versetzt(int skala) {
  var aufruf = 0;
  return (kachel) async {
    final r = img.copyResize(
      kachel,
      width: kachel.width * skala,
      height: kachel.height * skala,
      interpolation: img.Interpolation.nearest,
    );
    final offset = (aufruf++ % 5) * 3;
    for (final p in r) {
      p.r = (p.r + offset).clamp(0, 255);
      p.g = (p.g - offset).clamp(0, 255);
    }
    return r;
  };
}

/// Die Aufteilung vor #500: volle Kacheln, die letzte bündig an den Rand.
List<int> _alteAnfaenge(int length, int tileSize, int stride) {
  if (length <= tileSize) return [0];
  final starts = <int>[];
  var pos = 0;
  while (pos + tileSize < length) {
    starts.add(pos);
    pos += stride;
  }
  starts.add(length - tileSize);
  return starts;
}

/// Die Zusammensetzung vor #500, mit Summen und Gewichten für jedes
/// Ausgabepixel – für eine beliebige Aufteilung.
Future<img.Image> _vollstaendig(
  img.Image source, {
  required List<int> xs,
  required List<int> ys,
  required int tw,
  required int th,
  required int overlap,
  required int s,
  required Future<img.Image> Function(img.Image) infer,
}) async {
  final outW = source.width * s, outH = source.height * s;
  final accum = Float32List(outW * outH * 3);
  final weightSum = Float32List(outW * outH);
  for (final ty in ys) {
    for (final tx in xs) {
      final w0 = math.min(tw, source.width - tx);
      final h0 = math.min(th, source.height - ty);
      final processed = await infer(
        img.copyCrop(source, x: tx, y: ty, width: w0, height: h0),
      );
      final width = processed.width, height = processed.height;
      final fx = (overlap * s).clamp(0, width ~/ 2);
      final fy = (overlap * s).clamp(0, height ~/ 2);
      final weights = Float32List(width * height);
      for (var y = 0; y < height; y++) {
        var wy = 1.0;
        if (ty != 0 && fy > 0 && y < fy) wy = (y + 1) / fy;
        if (ty + h0 < source.height && fy > 0 && y >= height - fy) {
          wy = math.min(wy, (height - y) / fy);
        }
        for (var x = 0; x < width; x++) {
          var wx = 1.0;
          if (tx != 0 && fx > 0 && x < fx) wx = (x + 1) / fx;
          if (tx + w0 < source.width && fx > 0 && x >= width - fx) {
            wx = math.min(wx, (width - x) / fx);
          }
          weights[y * width + x] = wx * wy;
        }
      }
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final w = weights[y * width + x];
          final px = processed.getPixel(x, y);
          final idx = (ty * s + y) * outW + tx * s + x;
          accum[idx * 3] += px.r * w;
          accum[idx * 3 + 1] += px.g * w;
          accum[idx * 3 + 2] += px.b * w;
          weightSum[idx] += w;
        }
      }
    }
  }
  final result = img.Image(width: outW, height: outH);
  for (var y = 0; y < outH; y++) {
    for (var x = 0; x < outW; x++) {
      final idx = y * outW + x;
      final w = weightSum[idx];
      if (w > 0) {
        result.setPixelRgb(
          x,
          y,
          (accum[idx * 3] / w).round().clamp(0, 255),
          (accum[idx * 3 + 1] / w).round().clamp(0, 255),
          (accum[idx * 3 + 2] / w).round().clamp(0, 255),
        );
      }
    }
  }
  return result;
}
