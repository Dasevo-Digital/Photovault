import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/histogram.dart';

/// Die Auswertung hinter der Beschneidungswarnung. Reine Rechnung auf den
/// Zählern des Histogramms – deshalb ohne Bild und ohne Oberfläche
/// prüfbar, dasselbe Vorgehen wie in `develop_color_test.dart`.
///
/// Anlass: Der Lichter-Regler kam mit 1.9.6 dazu. Ein Regler, der Lichter
/// zurückholt, ohne dass man sieht, wann sie zurück sind, ist ein Regler
/// ohne Rückmeldung.
void main() {
  /// Baut ein Histogramm, bei dem [anteil] der Pixel je genannter Stufe
  /// liegen und der Rest in der Mitte.
  HistogramData mit({
    int rot0 = 0,
    int gruen0 = 0,
    int blau0 = 0,
    int rot255 = 0,
    int gruen255 = 0,
    int blau255 = 0,
    int gesamt = 10000,
  }) {
    List<int> kanal(int unten, int oben) {
      final l = List<int>.filled(histogramBinCount, 0);
      l[0] = unten;
      l[histogramBinCount - 1] = oben;
      l[128] = gesamt - unten - oben;
      return l;
    }

    return HistogramData(
      luminance: kanal(0, 0),
      red: kanal(rot0, rot255),
      green: kanal(gruen0, gruen255),
      blue: kanal(blau0, blau255),
      sampleCount: gesamt,
    );
  }

  test('ein sauberes Bild warnt nicht', () {
    final b = beschneidungAus(mit());
    expect(b.irgendwas, isFalse);
  });

  test('noch nichts gemessen ist keine Warnung', () {
    // Der Unterschied, auf den es ankommt: leer heisst „unbekannt", nicht
    // „alles beschnitten".
    expect(beschneidungAus(HistogramData.empty()).irgendwas, isFalse);
  });

  test('ausgefressene Lichter werden je Kanal gemeldet', () {
    final b = beschneidungAus(mit(rot255: 500));
    expect(b.lichter, isTrue);
    expect(b.lichterRot, isTrue);
    expect(b.lichterGruen, isFalse);
    expect(b.lichterBlau, isFalse);
    expect(b.lichterNeutral, isFalse, reason: 'nur ein Kanal, nicht weiss');
    expect(b.tiefen, isFalse);
  });

  test('abgesoffene Tiefen ebenso', () {
    final b = beschneidungAus(mit(rot0: 500, gruen0: 500, blau0: 500));
    expect(b.tiefen, isTrue);
    expect(b.tiefenNeutral, isTrue, reason: 'alle drei Kanäle = wirklich schwarz');
    expect(b.lichter, isFalse);
  });

  test('einzelne Ausreisser lösen nichts aus', () {
    // Ein einzelnes schwarzes Pixel in einer Nachtaufnahme darf die
    // Warnung nicht dauerleuchten lassen – sonst schaut niemand mehr hin.
    final b = beschneidungAus(mit(rot0: 5, gesamt: 10000));
    expect(b.irgendwas, isFalse, reason: '5 von 10000 liegt unter einem Promille');
  });

  test('die Schwelle greift genau dort, wo sie steht', () {
    // Ein Promille von 10000 sind 10; „mehr als" heisst ab 11.
    expect(beschneidungAus(mit(rot255: 10)).lichterRot, isFalse);
    expect(beschneidungAus(mit(rot255: 11)).lichterRot, isTrue);
  });

  test('eine strengere Schwelle meldet früher', () {
    final daten = mit(rot255: 20);
    expect(beschneidungAus(daten, schwelle: 0.01).lichterRot, isFalse);
    expect(beschneidungAus(daten, schwelle: 0.001).lichterRot, isTrue);
  });
}
