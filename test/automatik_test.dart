import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/histogram.dart';

/// Die Rechnung hinter dem Automatik-Knopf. Reine Auswertung der
/// Histogrammzähler – ohne Bild und ohne Oberfläche prüfbar.
///
/// Sie setzt die Regler, statt unsichtbar zu wirken: Wer sie benutzt,
/// sieht danach, was sie getan hat. Deshalb müssen die Werte plausibel
/// sein und nicht nur „irgendwie besser".
void main() {
  /// Ein Histogramm, dessen Helligkeit gleichmässig zwischen [von] und
  /// [bis] liegt.
  HistogramData spanne(int von, int bis, {int gesamt = 10000}) {
    final luma = List<int>.filled(histogramBinCount, 0);
    final stufen = bis - von + 1;
    for (var i = von; i <= bis; i++) {
      luma[i] = gesamt ~/ stufen;
    }
    return HistogramData(
      luminance: luma,
      red: luma,
      green: luma,
      blue: luma,
      sampleCount: gesamt,
    );
  }

  test('nichts gemessen heisst nichts verstellen', () {
    final w = automatikAus(HistogramData.empty());
    expect(w.belichtung, 0);
    expect(w.kontrast, 0);
  });

  test('ein Bild, das den vollen Umfang nutzt, bleibt unangetastet', () {
    final w = automatikAus(spanne(0, 255));
    expect(w.kontrast, closeTo(0, 0.05), reason: 'nichts zu strecken');
    expect(w.belichtung, closeTo(0, 0.1), reason: 'die Mitte liegt schon richtig');
  });

  test('ein flaues Bild bekommt Kontrast', () {
    // Nutzt nur die Hälfte des Umfangs – das lässt sich strecken.
    final w = automatikAus(spanne(64, 191));
    expect(w.kontrast, greaterThan(0.5));
    expect(w.belichtung, closeTo(0, 0.1),
        reason: 'die Mitte liegt bereits bei mittlerem Grau');
  });

  test('ein zu dunkles Bild wird aufgehellt', () {
    final w = automatikAus(spanne(0, 100));
    expect(w.belichtung, greaterThan(0.5), reason: 'muss heller werden');
  });

  test('ein zu helles Bild wird abgedunkelt', () {
    final w = automatikAus(spanne(180, 255));
    expect(w.belichtung, lessThan(0), reason: 'muss dunkler werden');
  });

  test('Ausreisser an den Raendern bestimmen nicht die Belichtung', () {
    // Der Grund fuer die Perzentile: Ein einzelnes weisses Pixel - eine
    // Spiegelung, ein Sensorfehler - darf nicht die ganze Rechnung
    // uebernehmen.
    final ohne = automatikAus(spanne(0, 100));
    final mit = spanne(0, 100);
    final luma = List<int>.from(mit.luminance);
    luma[255] = 3; // drei von 10000 = weit unter einem halben Prozent
    final w = automatikAus(HistogramData(
      luminance: luma,
      red: luma,
      green: luma,
      blue: luma,
      sampleCount: mit.sampleCount + 3,
    ));
    expect(w.belichtung, closeTo(ohne.belichtung, 0.15),
        reason: 'drei Pixel duerfen die Belichtung nicht kippen');
  });

  test('eine einfarbige Flaeche laesst sich nicht strecken', () {
    final luma = List<int>.filled(histogramBinCount, 0);
    luma[128] = 10000;
    final w = automatikAus(HistogramData(
      luminance: luma, red: luma, green: luma, blue: luma, sampleCount: 10000));
    expect(w.kontrast, 0, reason: 'kein Umfang, nichts zu tun');
    expect(w.belichtung, 0);
  });

  test('die Werte bleiben in den Grenzen der Regler', () {
    // Ein extrem dunkles Bild darf keine Belichtung jenseits von +3 EV
    // vorschlagen - der Regler nimmt sie gar nicht an.
    final luma = List<int>.filled(histogramBinCount, 0);
    luma[1] = 10000;
    final w = automatikAus(HistogramData(
      luminance: luma, red: luma, green: luma, blue: luma, sampleCount: 10000));
    expect(w.belichtung, lessThanOrEqualTo(3.0));
    expect(w.belichtung, greaterThanOrEqualTo(-3.0));
    expect(w.kontrast, inInclusiveRange(0.0, 1.0));
  });
}
