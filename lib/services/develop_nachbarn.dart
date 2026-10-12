import 'dart:math' as math;
import 'dart:ui' as ui;

import 'native_image_converter.dart';

/// Schärfe, Rauschminderung, Klarheit und Vignettierung auf der GPU.
///
/// Diese vier Regler brauchen Nachbarpixel, und der Entwickeln-Shader
/// (develop_adjustments.frag) sieht je Aufruf nur einen. Sie laufen
/// deshalb als eigene Stufen hinter ihm: Jede Stufe zeichnet ihr
/// Eingangsbild zuerst weich (develop_weich.frag, im linearen Licht) und
/// rechnet dann mit beiden (develop_nachbarn.frag).
///
/// **Vorbild ist Core Image**, das unter macOS das gespeicherte Ergebnis
/// rechnet (applyNonRawAdjustments in ImageConverter.swift). Apple
/// beschreibt die Filter nur in Worten; die Formeln hier sind deshalb an
/// Core-Image-Ausgaben gemessen und angepasst, an drei Fotos und einer
/// künstlichen Tafel mit Rauschfeldern bekannter Stärke. Mittlere
/// Abweichung in Stufen von 255, ohne Filter in Klammern:
///
/// | Regler | gemessen | Modell |
/// |---|---|---|
/// | Schärfe 0,25 / 1 | 0,4–1,3 / 1,2–3,3 (4–15) | Unschärfemaske der Helligkeit, σ 1,69 |
/// | Rauschen 0,1–1 | 0,2–1,6 (2,5–11,5) | Glätten mit σ 1,2 unterhalb einer Schwelle |
/// | Klarheit 0,5 / 1 | 0,3 / 0,6 (16 / 26) | Unschärfemaske mit σ = Radius 20 |
/// | Vignette | Faktor ±0,001 | exp(−I·(0,2235 r² + 0,01083 r⁴ + 0,0016 r⁶)) |
///
/// Alles rechnet im linearen Licht wie Core Image. Dieselbe Klarheit mit
/// einem Weichzeichner auf den sRGB-Werten wich im Mittel um 4 bis 11
/// Stufen ab.
class NachbarShader {
  NachbarShader._(this.weich, this.stufe);

  final ui.FragmentShader weich;
  final ui.FragmentShader stufe;

  void dispose() {
    weich.dispose();
    stufe.dispose();
  }
}

const nachbarWeichAsset = 'shaders/develop_weich.frag';
const nachbarStufeAsset = 'shaders/develop_nachbarn.frag';

/// Lädt beide Programme, oder `null`, wenn das nicht geht – dann fehlen
/// die vier Regler, der Rest der Entwicklung läuft weiter.
Future<NachbarShader?> ladeNachbarShader() async {
  try {
    final weich = await ui.FragmentProgram.fromAsset(nachbarWeichAsset);
    final stufe = await ui.FragmentProgram.fromAsset(nachbarStufeAsset);
    return NachbarShader._(weich.fragmentShader(), stufe.fragmentShader());
  } catch (_) {
    return null;
  }
}

/// Radius von CISharpenLuminance (Vorgabe von Core Image).
const schaerfeSigma = 1.69;

/// Glättungsradius von CINoiseReduction – gemessen: Rauschen gleich
/// welcher Stärke sinkt unterhalb der Schwelle auf das 0,24-Fache, das
/// entspricht einem Gauß mit σ 1,2.
const rauschenSigma = 1.2;

/// Klarheitsradius bei einer Bildkante von 1600 Punkten.
const klarheitRadiusBei1600 = 20.0;

/// Der Klarheitsradius für ein Bild dieser Grösse.
///
/// **Mit der Bildgrösse, nicht fest.** Die Vorschau rechnet mit 1600
/// Punkten Kante, das Speichern mit 4096. Bei festen 20 Pixeln wirkte die
/// Klarheit im gespeicherten Bild nur auf ein Sechstel der Fläche, die
/// man in der Vorschau beurteilt hat. Schärfe und Rauschminderung bleiben
/// in Pixeln: Sie arbeiten an der feinsten Struktur, die das Bild hat.
double klarheitSigma(int breite, int hoehe) =>
    klarheitRadiusBei1600 * math.max(breite, hoehe) / 1600;

/// Verstärkung der Schärfe-Stufe zum Regler (CISharpenLuminance mit
/// `inputSharpness = 2·s`; gemessen entspricht das genau dieser Zahl).
double schaerfeStaerke(double sharpness) => 2 * sharpness;

/// Stärke der Klarheit zum Regler.
///
/// Positiv wie unter macOS (CIUnsharpMask, Stärke 1,5·c). Negativ halb so
/// stark: −1 nimmt die Hälfte des Kontrasts über grössere Flächen weg.
/// Mit −1,5 bliebe nicht weniger, sondern ein umgekehrtes Detail übrig.
double klarheitStaerke(double clarity) =>
    clarity > 0 ? 1.5 * clarity : 0.5 * clarity;

/// Stärke der Vignette zum Regler, wie `CIVignette.inputIntensity`:
/// positiv dunkelt die Ränder ab, negativ hellt sie auf.
double vignettenStaerke(double vignette) => 2 * vignette;

/// Der Faktor, mit dem die Vignette das lineare Licht im Abstand [r] von
/// der Mitte malnimmt; [r] in halben kurzen Bildseiten. Dieselbe Rechnung
/// wie im Shader, hier für die Tests.
double vignettenFaktor(double r, double vignette) {
  final r2 = r * r;
  final abfall = r2 * (0.2235 + r2 * (0.01083 + r2 * 0.0016));
  return math.exp(-vignettenStaerke(vignette) * abfall);
}

/// Ob einer der vier Regler gesetzt ist.
bool brauchtNachbarn(DevelopAdjustments a) =>
    a.sharpness > 0 ||
    a.noiseReduction > 0 ||
    a.clarity != 0 ||
    a.vignette != 0;

/// Rechnet die vier Regler aus [a] auf [bild] und gibt das Ergebnis
/// zurück – oder [bild] selbst, wenn nichts zu tun ist.
///
/// Jedes neu erzeugte Bild, auch das Ergebnis, landet in [aufraeumen]; der
/// Aufrufer gibt sie frei, wenn er fertig ist.
///
/// [beschneidungZeigen] markiert beschnittene Stellen in der letzten
/// Stufe – nur für die Anzeige, nie für ein gespeichertes Bild.
Future<ui.Image> wendeNachbarnAn(
  ui.Image bild,
  DevelopAdjustments a,
  NachbarShader shader,
  List<ui.Image> aufraeumen, {
  bool beschneidungZeigen = false,
}) async {
  var x = bild;
  if (a.sharpness > 0) {
    final weich = await _weich(x, schaerfeSigma, shader, aufraeumen);
    x = await _stufe(
      x,
      weich,
      shader,
      aufraeumen,
      schaerfe: schaerfeStaerke(a.sharpness),
    );
  }
  if (a.noiseReduction > 0) {
    final weich = await _weich(x, rauschenSigma, shader, aufraeumen);
    x = await _stufe(x, weich, shader, aufraeumen, rauschen: a.noiseReduction);
  }
  if (a.clarity != 0 || a.vignette != 0 || beschneidungZeigen) {
    final weich = a.clarity != 0
        ? await _weich(x, klarheitSigma(x.width, x.height), shader, aufraeumen)
        : x;
    x = await _stufe(
      x,
      weich,
      shader,
      aufraeumen,
      klarheit: klarheitStaerke(a.clarity),
      vignette: vignettenStaerke(a.vignette),
      beschneidungZeigen: beschneidungZeigen,
    );
  }
  return x;
}

Future<ui.Image> _weich(
  ui.Image bild,
  double sigma,
  NachbarShader shader,
  List<ui.Image> aufraeumen,
) async {
  final waagerecht = await _durchgang(bild, shader.weich, (s) {
    s
      ..setFloat(2, 1)
      ..setFloat(3, 0)
      ..setFloat(4, sigma)
      // Bilinear: Ab σ ≈ 10 liegen die Stützstellen zwischen den Pixeln.
      ..setImageSampler(0, bild, filterQuality: ui.FilterQuality.low);
  });
  aufraeumen.add(waagerecht);
  final senkrecht = await _durchgang(bild, shader.weich, (s) {
    s
      ..setFloat(2, 0)
      ..setFloat(3, 1)
      ..setFloat(4, sigma)
      ..setImageSampler(0, waagerecht, filterQuality: ui.FilterQuality.low);
  });
  aufraeumen.add(senkrecht);
  return senkrecht;
}

Future<ui.Image> _stufe(
  ui.Image bild,
  ui.Image weich,
  NachbarShader shader,
  List<ui.Image> aufraeumen, {
  double schaerfe = 0,
  double rauschen = 0,
  double klarheit = 0,
  double vignette = 0,
  bool beschneidungZeigen = false,
}) async {
  final ergebnis = await _durchgang(bild, shader.stufe, (s) {
    s
      ..setFloat(2, schaerfe)
      ..setFloat(3, rauschen)
      ..setFloat(4, klarheit)
      ..setFloat(5, vignette)
      ..setFloat(6, beschneidungZeigen ? 1 : 0)
      ..setImageSampler(0, bild)
      ..setImageSampler(1, weich);
  });
  aufraeumen.add(ergebnis);
  return ergebnis;
}

/// Zeichnet [shader] einmal über die Fläche von [groesse] und gibt das
/// Bild zurück. Die Grösse belegt die ersten beiden Uniforms (`uSize`),
/// den Rest [belege].
///
/// `toImageSync` statt `toImage`: Das Bild entsteht erst auf dem
/// Rasterfaden, aber die nächste Stufe kann es sofort verwenden. Mit
/// `toImage` wartete jede der bis zu neun Stufen einen Umlauf zum
/// Rasterfaden ab; gemessen kostete das bei 1600 Punkten Kante mehr als
/// das Rechnen selbst.
Future<ui.Image> _durchgang(
  ui.Image groesse,
  ui.FragmentShader shader,
  void Function(ui.FragmentShader) belege,
) async {
  final breite = groesse.width;
  final hoehe = groesse.height;
  shader
    ..setFloat(0, breite.toDouble())
    ..setFloat(1, hoehe.toDouble());
  belege(shader);
  final aufnahme = ui.PictureRecorder();
  ui.Canvas(aufnahme).drawRect(
    ui.Rect.fromLTWH(0, 0, breite.toDouble(), hoehe.toDouble()),
    ui.Paint()..shader = shader,
  );
  final bild = aufnahme.endRecording();
  try {
    return bild.toImageSync(breite, hoehe);
  } finally {
    bild.dispose();
  }
}
