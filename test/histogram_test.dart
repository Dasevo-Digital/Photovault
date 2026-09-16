import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/services/histogram.dart';

/// Erzeugt ein einfarbiges Bild.
img.Image _solid(int width, int height, int r, int g, int b) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return image;
}

void main() {
  test('einfarbig Schwarz landet komplett im untersten Tonwert', () {
    final histogram = computeHistogram(_solid(32, 32, 0, 0, 0));

    expect(histogram.sampleCount, 32 * 32);
    expect(histogram.luminance[0], 32 * 32);
    expect(histogram.red[0], 32 * 32);
    expect(histogram.green[0], 32 * 32);
    expect(histogram.blue[0], 32 * 32);
    // Sonst nirgends etwas.
    expect(histogram.luminance.skip(1).every((v) => v == 0), isTrue);
  });

  test('einfarbig Weiß landet komplett im obersten Tonwert', () {
    final histogram = computeHistogram(_solid(16, 16, 255, 255, 255));

    expect(histogram.luminance[255], 16 * 16);
    expect(histogram.red[255], 16 * 16);
    expect(histogram.green[255], 16 * 16);
    expect(histogram.blue[255], 16 * 16);
  });

  test('reines Rot trifft nur den Rot-Kanal, Luminanz folgt der Luma-Gewichtung', () {
    final histogram = computeHistogram(_solid(8, 8, 255, 0, 0));

    expect(histogram.red[255], 8 * 8);
    expect(histogram.green[0], 8 * 8);
    expect(histogram.blue[0], 8 * 8);
    // 0,299 * 255 = 76,2 -> gerundet 76. Ein ungewichteter Mittelwert läge
    // bei 85 – genau der Unterschied, den dieser Test absichert.
    expect(histogram.luminance[76], 8 * 8);
  });

  test('reines Grün ist heller als reines Blau (Luma-Gewichtung)', () {
    final green = computeHistogram(_solid(8, 8, 0, 255, 0));
    final blue = computeHistogram(_solid(8, 8, 0, 0, 255));

    // 0,587 * 255 = 149,7 -> 150 bzw. 0,114 * 255 = 29,07 -> 29.
    expect(green.luminance[150], 8 * 8);
    expect(blue.luminance[29], 8 * 8);
  });

  test('die Summe aller Zähler entspricht der Pixelzahl', () {
    final image = img.Image(width: 20, height: 10);
    // Waagerechter Verlauf über die volle Breite.
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final value = (255 * x / (image.width - 1)).round();
        image.setPixelRgb(x, y, value, value, value);
      }
    }
    final histogram = computeHistogram(image);

    expect(histogram.luminance.reduce((a, b) => a + b), 20 * 10);
    expect(histogram.red.reduce((a, b) => a + b), 20 * 10);
    expect(histogram.sampleCount, 20 * 10);
  });

  test('ein Verlauf verteilt sich über viele Tonwerte statt nur einen', () {
    final image = img.Image(width: 256, height: 4);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(x, y, x, x, x);
      }
    }
    final histogram = computeHistogram(image);

    final usedBins = histogram.luminance.where((v) => v > 0).length;
    expect(usedBins, greaterThan(200), reason: 'ein voller Verlauf sollte fast alle Stufen belegen');
  });

  test('große Bilder werden vor der Auswertung heruntergerechnet', () {
    final histogram = computeHistogram(_solid(2000, 1000, 128, 128, 128));

    // Nicht 2000*1000 – die Stichprobe ist auf 512px längste Kante begrenzt.
    expect(histogram.sampleCount, lessThan(2000 * 1000));
    expect(histogram.sampleCount, greaterThan(0));
    // Die Verteilung bleibt trotzdem korrekt: alles im selben Tonwert.
    expect(histogram.luminance[128], histogram.sampleCount);
  });

  test('peakOf liefert den höchsten Zähler über die gewählten Kanäle', () {
    final histogram = computeHistogram(_solid(10, 10, 255, 0, 0));

    expect(histogram.peakOf([histogram.red]), 100);
    expect(histogram.peakOf([histogram.red, histogram.green, histogram.blue]), 100);
  });

  test('leeres Histogramm meldet sich als leer', () {
    final empty = HistogramData.empty();

    expect(empty.isEmpty, isTrue);
    expect(empty.luminance, hasLength(histogramBinCount));
    expect(empty.peakOf([empty.luminance]), 0);
  });

  test('computeHistogramFromBytes dekodiert und wertet aus', () {
    final bytes = img.encodePng(_solid(12, 12, 0, 0, 0));

    final histogram = computeHistogramFromBytes(bytes);

    expect(histogram, isNotNull);
    expect(histogram!.luminance[0], 12 * 12);
  });

  test('computeHistogramFromBytes gibt null für undekodierbare Daten', () {
    expect(computeHistogramFromBytes(Uint8List.fromList('kein Bild'.codeUnits)), isNull);
  });

  // Der Entwickeln-Screen ruft die Berechnung über compute() auf, damit sie
  // den UI-Thread nicht blockiert. Das Ergebnis muss dafür zwischen Isolates
  // übertragbar sein – dieser Test würde fehlschlagen, falls HistogramData
  // je etwas Nicht-Übertragbares aufnimmt.
  test('das Ergebnis lässt sich über compute() aus einem Isolate zurückgeben', () async {
    final bytes = img.encodePng(_solid(24, 24, 10, 200, 30));

    final histogram = await compute(computeHistogramFromBytes, bytes);

    expect(histogram, isNotNull);
    expect(histogram!.sampleCount, 24 * 24);
    expect(histogram.green[200], 24 * 24);
  });
}
