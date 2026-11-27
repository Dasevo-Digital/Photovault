import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/services/hochskalieren.dart';
import 'package:photo_vault/services/restore_service.dart';
import 'package:photo_vault/services/tile_processor.dart';

/// Was das Werkzeug „Hochskalieren“ rechnet (#500), ohne ONNX: Grenzen und
/// Zielgrösse, die Kennung der Aufträge, das flächentreue Verkleinern und
/// die kachelweise Rechnung mit einem „Modell“, das einfach vierfach
/// vergrössert.
void main() {
  img.Image zufallsbild(int breite, int hoehe, {int saat = 1}) {
    final zufall = math.Random(saat);
    final bild = img.Image(width: breite, height: hoehe);
    for (final p in bild) {
      p
        ..r = zufall.nextInt(256)
        ..g = zufall.nextInt(256)
        ..b = zufall.nextInt(256);
    }
    return bild;
  }

  /// Das Ersatzmodell: jedes Pixel wird ein Block aus 4 × 4 gleichen.
  Future<img.Image> vierfach(img.Image kachel) async => img.copyResize(
    kachel,
    width: kachel.width * 4,
    height: kachel.height * 4,
  );

  group('Grenzen und Zielgrösse', () {
    test('die Zielgrösse ist genau das Vielfache', () {
      for (final f in hochskalierFaktoren) {
        final ziel = hochskalierziel(4032, 3024, f);
        expect((ziel.breite, ziel.hoehe), (4032 * f, 3024 * f));
      }
      expect(hochskalierziel(4032, 3024, 2).sperre, isNull);
    });

    test('die Kante genau auf der Grenze geht, ein Pixel mehr nicht', () {
      expect(hochskalierziel(4096, 1000, 4).sperre, isNull);
      expect(hochskalierziel(4097, 1000, 4).sperre, Hochskaliersperre.kante);
      // Hochformat zählt genauso.
      expect(hochskalierziel(1000, 4097, 4).sperre, Hochskaliersperre.kante);
    });

    test('100 Megapixel gehen, eine Zeile mehr nicht', () {
      expect(hochskalierziel(5000, 5000, 2).sperre, isNull);
      expect(hochskalierziel(5000, 5001, 2).sperre, Hochskaliersperre.pixel);
    });

    test('ist beides zu gross, nennt die Sperre die Kante', () {
      expect(hochskalierziel(10000, 10000, 2).sperre, Hochskaliersperre.kante);
    });

    test('vorgewählt wird der grösste erlaubte Faktor', () {
      expect(groessterHochskalierfaktor(1000, 750), 4);
      // 3× gäbe 180 MP, 4× eine Kante von 20000 px.
      expect(groessterHochskalierfaktor(5000, 4000), 2);
      // Schon 2× gäbe eine Kante von 18000 px.
      expect(groessterHochskalierfaktor(9000, 6000), isNull);
    });

    // Die Begründung der Grenze in Zahlen: An der ungünstigsten Stelle
    // jedes Faktors – längste Kante und Bildpunkte ausgereizt – bleibt die
    // Zusammensetzung unter ihrem Budget, mit der Kachelgrösse von macOS
    // wie mit der der übrigen Rechner.
    test('an jeder Grenze bleibt die Zusammensetzung unter dem Budget', () {
      const budget = 1536 * 1024 * 1024;
      for (final f in hochskalierFaktoren) {
        final breite = hochskalierMaxKante ~/ f;
        final hoehe = hochskalierMaxPixel ~/ (breite * f) ~/ f;
        expect(hochskalierziel(breite, hoehe, f).sperre, isNull);
        expect(hochskalierziel(breite, hoehe + 1, f).sperre, isNotNull);
        final quelle = img.Image(width: breite, height: hoehe);
        for (final kachel in [
          RestoreService.kachelGroesse(macos: true),
          RestoreService.kachelGroesse(macos: false),
        ]) {
          final plan = tileMemoryPlan(
            quelle,
            tileSize: kachel,
            overlap: RestoreService.overlap,
            scaleFactor: f,
          );
          expect(plan.totalBytes, lessThan(budget), reason: '$f× / $kachel');
        }
      }
    });

    // Gegenprobe zum Weg über die Kachel: Bei 2× an der Grenze sprengte
    // ein vierfaches Zwischenbild des ganzen Fotos das Budget.
    test('ein vierfaches Zwischenbild des ganzen Fotos passte nicht', () {
      const budget = 1536 * 1024 * 1024;
      final breite = hochskalierMaxKante ~/ 2;
      final hoehe = hochskalierMaxPixel ~/ (breite * 2) ~/ 2;
      final plan = tileMemoryPlan(
        img.Image(width: breite, height: hoehe),
        tileSize: RestoreService.kachelGroesse(macos: true),
        overlap: RestoreService.overlap,
        scaleFactor: 4,
      );
      expect(plan.totalBytes, greaterThan(budget));
    });
  });

  group('Kennung und Name', () {
    test('die Kennung trägt den Faktor', () {
      for (final f in hochskalierFaktoren) {
        expect(hochskalierfaktor(hochskalierAuftragsId(f)), f);
      }
      expect(
        hochskalierAuftragsId(2),
        isNot(hochskalierAuftragsId(2)),
        reason: 'jede Kennung ist neu',
      );
    });

    test('eine Restaurierung ist kein Hochskalieren', () {
      expect(hochskalierfaktor('6f1c0c1e-2b3a-4d5e-8f90-123456789abc'), isNull);
      expect(hochskalierfaktor('hochskalieren-5x-abc'), isNull);
      expect(hochskalierfaktor('hochskalieren-x-abc'), isNull);
    });

    test('der Name sagt den Faktor und endet auf .jpg', () {
      expect(hochskalierName('IMG_1234.HEIC', 4), 'IMG_1234 (4×).jpg');
      expect(hochskalierName('Oma 1962.tif', 2), 'Oma 1962 (2×).jpg');
      expect(hochskalierName(r'a\b.jpg', 3), 'a_b (3×).jpg');
    });

    test('die Masse eines JPEG kommen aus dem Kopf', () {
      final jpeg = img.encodeJpg(img.Image(width: 37, height: 21));
      expect(jpegMasse(jpeg), (breite: 37, hoehe: 21));
      expect(jpegMasse(img.encodePng(img.Image(width: 2, height: 2))), isNull);
    });
  });

  group('flächentreu verkleinern', () {
    test('4 → 2 und 4 → 3 treffen die Masse genau', () {
      final gross = zufallsbild(4 * 37, 4 * 23);
      for (final f in [2, 3]) {
        final klein = verkleinereFlaechig(gross, 37 * f, 23 * f);
        expect((klein.width, klein.height), (37 * f, 23 * f));
      }
    });

    test('2 : 1 ist das gerundete Mittel jedes 2 × 2-Blocks', () {
      final gross = zufallsbild(8, 6, saat: 7);
      final klein = verkleinereFlaechig(gross, 4, 3);
      for (var y = 0; y < 3; y++) {
        for (var x = 0; x < 4; x++) {
          var summe = 0;
          for (final (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)]) {
            summe += gross.getPixel(2 * x + dx, 2 * y + dy).r.toInt();
          }
          expect(klein.getPixel(x, y).r, (summe / 4).round(), reason: '$x,$y');
        }
      }
    });

    test('4 → 3 rechnet angeschnittene Pixel mit ihrem Anteil', () {
      // Zielpixel 2 deckt ein Drittel von Pixel 2 und Pixel 3 ganz:
      // 255 · 1 / (4/3) = 191,25.
      final zeile = img.Image(width: 4, height: 1);
      zeile.setPixelRgb(3, 0, 255, 255, 255);
      final klein = verkleinereFlaechig(zeile, 3, 1);
      expect([for (var x = 0; x < 3; x++) klein.getPixel(x, 0).r], [0, 0, 191]);
    });

    test('die mittlere Helligkeit bleibt erhalten', () {
      final gross = zufallsbild(4 * 31, 4 * 17, saat: 3);
      final klein = verkleinereFlaechig(gross, 3 * 31, 3 * 17);
      double mittel(img.Image b) {
        var s = 0.0;
        for (final p in b) {
          s += p.r + p.g + p.b;
        }
        return s / (b.width * b.height * 3);
      }

      expect((mittel(klein) - mittel(gross)).abs(), lessThan(0.5));
    });

    test('vergrössern ist kein Verkleinern', () {
      final bild = zufallsbild(10, 10);
      expect(() => verkleinereFlaechig(bild, 11, 10), throwsArgumentError);
      expect(identical(verkleinereFlaechig(bild, 10, 10), bild), isTrue);
    });
  });

  group('kachelweise hochskalieren', () {
    test('2×, 3× und 4× treffen die Masse genau', () async {
      final quelle = zufallsbild(301, 203);
      for (final f in hochskalierFaktoren) {
        final aus = await hochskaliereInKacheln(
          quelle,
          tileSize: 128,
          overlap: 16,
          modellfaktor: 4,
          zielfaktor: f,
          infer: vierfach,
        );
        expect((aus.width, aus.height), (301 * f, 203 * f), reason: '$f×');
      }
    });

    test(
      'je Kachel verkleinert gleicht dem verkleinerten Gesamtbild',
      () async {
        final quelle = zufallsbild(301, 203, saat: 5);
        final gesamt = await processInTiles(
          quelle,
          tileSize: 128,
          overlap: 16,
          scaleFactor: 4,
          infer: vierfach,
        );
        for (final f in [2, 3]) {
          final erwartet = verkleinereFlaechig(gesamt, 301 * f, 203 * f);
          final jeKachel = await hochskaliereInKacheln(
            quelle,
            tileSize: 128,
            overlap: 16,
            modellfaktor: 4,
            zielfaktor: f,
            infer: vierfach,
          );
          var abweichung = 0;
          for (final p in jeKachel) {
            final e = erwartet.getPixel(p.x, p.y);
            abweichung = math.max(abweichung, (p.r - e.r).abs().toInt());
            abweichung = math.max(abweichung, (p.g - e.g).abs().toInt());
            abweichung = math.max(abweichung, (p.b - e.b).abs().toInt());
          }
          expect(abweichung, lessThanOrEqualTo(1), reason: '$f×');
        }
      },
    );

    test('Fortschritt zählt die Kacheln, Abbrechen hält an', () async {
      final quelle = zufallsbild(300, 200);
      final stand = <(int, int)>[];
      await hochskaliereInKacheln(
        quelle,
        tileSize: 128,
        overlap: 16,
        modellfaktor: 4,
        zielfaktor: 2,
        infer: vierfach,
        onProgress: (f, g) => stand.add((f, g)),
      );
      expect(stand.last.$1, stand.last.$2);
      var gerechnet = 0;
      await hochskaliereInKacheln(
        quelle,
        tileSize: 128,
        overlap: 16,
        modellfaktor: 4,
        zielfaktor: 2,
        infer: (k) {
          gerechnet++;
          return vierfach(k);
        },
        isCancelled: () => gerechnet >= 2,
      );
      expect(gerechnet, 2);
    });

    test('ein Modell mit falscher Ausgabe fällt auf', () async {
      await expectLater(
        hochskaliereInKacheln(
          zufallsbild(64, 64),
          tileSize: 128,
          overlap: 16,
          modellfaktor: 4,
          zielfaktor: 2,
          infer: (k) async =>
              img.copyResize(k, width: k.width * 3, height: k.height * 3),
        ),
        throwsStateError,
      );
      expect(
        () => hochskaliereInKacheln(
          zufallsbild(8, 8),
          tileSize: 128,
          overlap: 16,
          modellfaktor: 4,
          zielfaktor: 5,
          infer: vierfach,
        ),
        throwsArgumentError,
      );
    });
  });
}
