import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/services/blur_detection.dart';

/// Prüft [computeBlurScore] anhand synthetischer Testbilder: ein
/// Schachbrettmuster (hochfrequent, "scharf") muss einen deutlich höheren
/// Score liefern als eine einfarbige Fläche ("unscharf" – keinerlei
/// Kantenübergänge, Laplace-Varianz theoretisch exakt 0).
void main() {
  test('Schachbrettmuster liefert einen deutlich höheren Score als eine einfarbige Fläche', () {
    final checkerboard = img.Image(width: 200, height: 200);
    for (var y = 0; y < checkerboard.height; y++) {
      for (var x = 0; x < checkerboard.width; x++) {
        final isLight = ((x ~/ 8) + (y ~/ 8)).isEven;
        final value = isLight ? 255 : 0;
        checkerboard.setPixelRgb(x, y, value, value, value);
      }
    }

    final flat = img.Image(width: 200, height: 200);
    for (var y = 0; y < flat.height; y++) {
      for (var x = 0; x < flat.width; x++) {
        flat.setPixelRgb(x, y, 128, 128, 128);
      }
    }

    final sharpScore = computeBlurScore(checkerboard);
    final blurryScore = computeBlurScore(flat);

    expect(blurryScore, 0);
    expect(sharpScore, greaterThan(blurryScore));
    expect(sharpScore, greaterThan(blurryScoreThreshold));
  });

  test('sehr kleine Bilder (< 3px Kante) liefern 0 statt eines Fehlers', () {
    final tiny = img.Image(width: 2, height: 2);
    expect(computeBlurScore(tiny), 0);
  });

  group('renderFocusPeakingOverlayPng', () {
    test('liefert ein PNG derselben Auflösung wie das Eingabebild', () {
      final checkerboard = img.Image(width: 64, height: 48);
      for (var y = 0; y < checkerboard.height; y++) {
        for (var x = 0; x < checkerboard.width; x++) {
          final isLight = ((x ~/ 4) + (y ~/ 4)).isEven;
          final value = isLight ? 255 : 0;
          checkerboard.setPixelRgb(x, y, value, value, value);
        }
      }

      final pngBytes = renderFocusPeakingOverlayPng(checkerboard);
      final decoded = img.decodePng(pngBytes);

      expect(decoded, isNotNull);
      expect(decoded!.width, 64);
      expect(decoded.height, 48);
      expect(decoded.numChannels, 4);
    });

    test('markiert Kanten im Schachbrettmuster, aber keine Fläche in einem einfarbigen Bild', () {
      final checkerboard = img.Image(width: 64, height: 48);
      for (var y = 0; y < checkerboard.height; y++) {
        for (var x = 0; x < checkerboard.width; x++) {
          final isLight = ((x ~/ 4) + (y ~/ 4)).isEven;
          final value = isLight ? 255 : 0;
          checkerboard.setPixelRgb(x, y, value, value, value);
        }
      }
      final flat = img.Image(width: 64, height: 48);
      for (var y = 0; y < flat.height; y++) {
        for (var x = 0; x < flat.width; x++) {
          flat.setPixelRgb(x, y, 128, 128, 128);
        }
      }

      final checkerboardOverlay = img.decodePng(renderFocusPeakingOverlayPng(checkerboard))!;
      final flatOverlay = img.decodePng(renderFocusPeakingOverlayPng(flat))!;

      var checkerboardHighlightedPixels = 0;
      var flatHighlightedPixels = 0;
      for (var y = 0; y < checkerboardOverlay.height; y++) {
        for (var x = 0; x < checkerboardOverlay.width; x++) {
          if (checkerboardOverlay.getPixel(x, y).a > 0) checkerboardHighlightedPixels++;
          if (flatOverlay.getPixel(x, y).a > 0) flatHighlightedPixels++;
        }
      }

      expect(flatHighlightedPixels, 0);
      expect(checkerboardHighlightedPixels, greaterThan(0));
    });
  });
}
