import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/services/histogram.dart';

/// Die Waveform.
///
/// Der Grund, warum sie eine eigene Auswertung braucht und nicht bloss eine
/// andere Zeichnung des Histogramms ist: Ein Histogramm zählt über das
/// ganze Bild und wirft dabei die Bildposition weg. Genau die ist hier die
/// waagerechte Achse. Diese Prüfungen halten fest, dass sie auch wirklich
/// erhalten bleibt – eine Waveform, die für jede Spalte dasselbe zeigt,
/// wäre ein aufwendig gezeichnetes Histogramm.
void main() {
  /// Ein Bild, dessen linke Hälfte schwarz und rechte Hälfte weiss ist.
  img.Image halbeHalbe(int breite, int hoehe) {
    final bild = img.Image(width: breite, height: hoehe);
    for (var y = 0; y < hoehe; y++) {
      for (var x = 0; x < breite; x++) {
        final hell = x >= breite ~/ 2;
        bild.setPixelRgb(x, y, hell ? 255 : 0, hell ? 255 : 0, hell ? 255 : 0);
      }
    }
    return bild;
  }

  test('die Bildposition bleibt erhalten', () {
    final w = computeWaveform(halbeHalbe(200, 100));

    // Ganz links nur Schwarz, ganz rechts nur Weiss.
    expect(w.luminance.first[0], greaterThan(0));
    expect(w.luminance.first[255], 0);
    expect(w.luminance.last[255], greaterThan(0));
    expect(w.luminance.last[0], 0);
  });

  test('die Spaltenzahl richtet sich nach dem Bild, gedeckelt', () {
    // Ein breites Bild bekommt die volle Zahl.
    expect(computeWaveform(halbeHalbe(800, 100)).columnCount, waveformMaxColumns);
    // Ein schmales genau seine Breite – fest 256 zu nehmen liesse Spalten
    // leer, und die Lücken sähen wie Bildinhalt aus.
    expect(computeWaveform(halbeHalbe(64, 32)).columnCount, 64);
    for (final spalte in computeWaveform(halbeHalbe(64, 32)).luminance) {
      expect(spalte, hasLength(histogramBinCount));
    }
  });

  test('keine Spalte bleibt leer', () {
    for (final breite in [7, 64, 199, 256, 800]) {
      final w = computeWaveform(halbeHalbe(breite, 40));
      for (var x = 0; x < w.columnCount; x++) {
        final summe = w.luminance[x].fold<int>(0, (a, b) => a + b);
        expect(summe, greaterThan(0), reason: 'Breite $breite, Spalte $x');
      }
    }
  });

  test('die Farbkanäle werden getrennt gezählt', () {
    // Ein durchgehend rotes Bild: Rot ganz oben, Grün und Blau ganz unten.
    final bild = img.Image(width: 64, height: 8);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 64; x++) {
        bild.setPixelRgb(x, y, 255, 0, 0);
      }
    }
    final w = computeWaveform(bild);
    final mitte = computeWaveform(bild).columnCount ~/ 2;
    expect(w.red[mitte][255], greaterThan(0));
    expect(w.green[mitte][0], greaterThan(0));
    expect(w.blue[mitte][0], greaterThan(0));
  });

  test('die Spitze ist der höchste Zählerstand', () {
    final w = computeWaveform(halbeHalbe(200, 100));
    var groesster = 0;
    for (final spalte in w.luminance) {
      for (final wert in spalte) {
        if (wert > groesster) groesster = wert;
      }
    }
    expect(w.peak, groesster);
    expect(w.peak, greaterThan(0));
  });

  test('ein einspaltiges Bild bringt die Rechnung nicht durcheinander', () {
    // Die Abbildung auf Anzeigespalten teilt durch (Breite - 1).
    final schmal = img.Image(width: 1, height: 10);
    for (var y = 0; y < 10; y++) {
      schmal.setPixelRgb(0, y, 128, 128, 128);
    }
    expect(() => computeWaveform(schmal), returnsNormally);
    final w = computeWaveform(schmal);
    expect(w.peak, 10);
  });

  test('das Leere ist wirklich leer', () {
    final leer = WaveformData.empty();
    expect(leer.isEmpty, isTrue);
    expect(leer.luminance, hasLength(waveformMaxColumns));
  });

  test('Histogramm und Waveform kommen aus einem Durchgang', () {
    // Getrennt gerechnet könnten beim schnellen Reglerziehen zwei Stände
    // entstehen, die zu verschiedenen Vorschauen gehören.
    final bild = halbeHalbe(64, 32);
    final bytes = img.encodePng(bild);
    final auswertung = computeBildAuswertung(bytes);

    expect(auswertung, isNotNull);
    // Dieselbe Stichprobe: Die Gesamtzahl der Pixel muss übereinstimmen.
    var summeWaveform = 0;
    for (final spalte in auswertung!.waveform.luminance) {
      for (final wert in spalte) {
        summeWaveform += wert;
      }
    }
    expect(summeWaveform, auswertung.histogramm.sampleCount);
  });

  test('unlesbare Bytes ergeben null statt eines Absturzes', () {
    expect(computeBildAuswertung(img.encodePng(img.Image(width: 1, height: 1))),
        isNotNull);
  });
}
