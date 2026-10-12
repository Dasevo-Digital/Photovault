import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:photo_vault/services/native_image_converter.dart';

/// Eine künstliche Prüftafel für Schärfe, Rauschminderung, Klarheit und
/// Vignette – für den Abgleich zwischen Core Image (macOS) und dem
/// GPU-Weg von Linux und Windows.
///
/// **Neutralgrau mit Absicht.** Core Image gibt in Display P3 aus, der
/// GPU-Weg in sRGB. Beide nutzen dieselbe Tonwertkurve und denselben
/// Weißpunkt; für Grau sind die Zahlen deshalb gleich, für Farben nicht.
/// So misst der Vergleich die Filter und nicht die Farbräume.
///
/// Inhalt: oben links vier Rauschfelder bekannter Stärke (Rauschminderung),
/// daneben eine harte Kante (Schärfe, Kantenerhalt), rechts ein feines
/// Schachbrett (Schärfe); darunter ein grossflächiges Muster (Klarheit)
/// mit Verlauf. Das Rauschen kommt aus einem festen Zufallsgenerator,
/// damit die Tafel auf jedem Rechner dieselbe ist.
img.Image entwickelnTafel({int breite = 400, int hoehe = 250}) {
  final bild = img.Image(width: breite, height: hoehe);
  final zufall = _Gauss(20261012);
  final drittel = breite ~/ 3;
  final mitte = hoehe ~/ 2;
  for (var y = 0; y < hoehe; y++) {
    for (var x = 0; x < breite; x++) {
      double v;
      if (y < mitte && x < drittel) {
        // Vier Felder mit Rauschen der Streuung 3, 6, 12 und 24 Stufen.
        final feld = (x * 2 ~/ drittel) + 2 * (y * 2 ~/ mitte);
        v = 128 + zufall.naechste() * (3 << feld);
      } else if (y < mitte && x < 2 * drittel) {
        v = x < drittel + drittel ~/ 2 ? 60 : 190;
        if (y > mitte * 3 ~/ 4 && (x ~/ 2) % 3 == 0) v = 140;
      } else if (y < mitte) {
        v = ((x ~/ 3 + y ~/ 3) % 2 == 0) ? 100 : 150;
      } else {
        v =
            40 +
            150 * x / breite +
            40 *
                math.sin(2 * math.pi * x / 120) *
                math.sin(2 * math.pi * y / 90);
      }
      final w = v.round().clamp(0, 255);
      bild.setPixelRgb(x, y, w, w, w);
    }
  }
  return bild;
}

/// Eine Maske, wie die App sie speichert: deckend, Graustufen, weiß =
/// ausgewählt. Hier die linke Hälfte, mit weichem Übergang.
img.Image entwickelnTafelMaske({int breite = 400, int hoehe = 250}) {
  final maske = img.Image(width: breite, height: hoehe);
  for (var y = 0; y < hoehe; y++) {
    for (var x = 0; x < breite; x++) {
      final w = (255 * (1 - ((x - breite * 0.45) / (breite * 0.1))))
          .round()
          .clamp(0, 255);
      maske.setPixelRgb(x, y, w, w, w);
    }
  }
  return maske;
}

/// Die verglichenen Fälle. Je Regler zwei Werte, dazu alle vier
/// zusammen. Der Maskenfall steht gesondert, er braucht die Maskendatei.
const entwickelnFaelle = <String, DevelopAdjustments>{
  'schaerfe_05': DevelopAdjustments(sharpness: 0.5),
  'schaerfe_10': DevelopAdjustments(sharpness: 1.0),
  'rauschen_01': DevelopAdjustments(noiseReduction: 0.1),
  'rauschen_04': DevelopAdjustments(noiseReduction: 0.4),
  'klarheit_p06': DevelopAdjustments(clarity: 0.6),
  'klarheit_m06': DevelopAdjustments(clarity: -0.6),
  'vignette_p06': DevelopAdjustments(vignette: 0.6),
  'vignette_m06': DevelopAdjustments(vignette: -0.6),
  'alle_vier': DevelopAdjustments(
    sharpness: 0.4,
    noiseReduction: 0.2,
    clarity: 0.4,
    vignette: 0.3,
  ),
};

/// Maskenfall: global heller, in der Maske wieder dunkler und geschärft.
/// Belichtung, weil Shader und Core Image sie exakt gleich rechnen – ein
/// Unterschied hier liegt dann an der Maske, nicht am Regler.
const maskenfallGlobal = DevelopAdjustments(exposure: 0.5);
const maskenfallMaske = DevelopAdjustments(exposure: -0.5, sharpness: 0.6);

/// Mittlere und grösste Abweichung zweier gleich grosser Bilder in Stufen
/// von 255, über alle drei Farbkanäle.
({double mittel, int groesste}) abweichung(img.Image a, img.Image b) {
  assert(a.width == b.width && a.height == b.height);
  final pa = a.convert(numChannels: 3).getBytes(order: img.ChannelOrder.rgb);
  final pb = b.convert(numChannels: 3).getBytes(order: img.ChannelOrder.rgb);
  return _abweichung(pa, pb);
}

({double mittel, int groesste}) _abweichung(Uint8List a, Uint8List b) {
  var summe = 0;
  var groesste = 0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    summe += d;
    if (d > groesste) groesste = d;
  }
  return (mittel: summe / a.length, groesste: groesste);
}

/// Normalverteilte Zufallszahlen aus einem festen Startwert (Box-Muller
/// über einen linearen Kongruenzgenerator) – auf jeder Plattform gleich.
class _Gauss {
  _Gauss(this._zustand);
  int _zustand;
  double? _vorrat;

  double _gleich() {
    _zustand = (_zustand * 1103515245 + 12345) & 0x7fffffff;
    return (_zustand + 1) / 0x80000001;
  }

  double naechste() {
    final v = _vorrat;
    if (v != null) {
      _vorrat = null;
      return v;
    }
    final r = math.sqrt(-2 * math.log(_gleich()));
    final w = 2 * math.pi * _gleich();
    _vorrat = r * math.sin(w);
    return r * math.cos(w);
  }
}
