import 'dart:math' as math;

/// Die Temperatur, bei der der Weissabgleich nichts ändert.
const neutraleTemperatur = 6500.0;

/// Der Bereich des Temperaturreglers, in Kelvin.
///
/// **Höher ist wärmer** (seit Schema 102, #466), wie in Lightroom: Die Zahl
/// sagt, welche Lichtfarbe ausgeglichen wird. 3000 K gleicht Kunstlicht aus
/// und macht das Bild bläulicher, 9000 K gleicht Schatten aus und macht es
/// gelblicher.
///
/// Die Grenzen liegen um [neutraleTemperatur] gespiegelt:
/// `temperaturMin * temperaturMax == 6500²`. Die Wirkung an beiden Enden ist
/// deshalb gleich stark, und jeder vor der Umstellung gespeicherte Wert
/// (2000 … 12000 K in der alten Bedeutung) liegt nach der Umrechnung
/// ([temperaturAusFruehererBedeutung]) darin – die stärkste frühere
/// Erwärmung, 2000 K, wird zu 21125 K.
const temperaturMin = 2000.0;
const temperaturMax = neutraleTemperatur * neutraleTemperatur / temperaturMin;

/// Bis Schema 101 klemmten alle Renderer die gespeicherte Zahl auf diesen
/// Bereich.
const _frueherMin = 2000.0;
const _frueherMax = 12000.0;

/// Die Faktoren des Weissabgleichs je Kanal, in linearem Licht.
///
/// Dieselbe Rechnung steht als `whiteBalanceGain` in
/// shaders/develop_adjustments.frag (Vorschau, Linux, Windows, Handy), in
/// packages/server/web/entwickeln.js (Browser) und als `weissabgleich` in
/// macos/Runner/ImageConverter.swift. Hier steht sie für die Tests und als
/// Bezug für [weissabgleichFuer].
///
/// Mit `t = Temperatur / 6500`: Rot `t^0.55`, Blau `t^-0.55`, Grün
/// `1 - Farbstich / 400`. Unter 6500 K wird das Bild also blauer, darüber
/// gelber; ein höherer Farbstich nimmt Grün weg (magenta).
({double r, double g, double b}) weissabgleichFaktoren(
  double temperatur,
  double toenung,
) {
  final t = temperatur.clamp(temperaturMin, temperaturMax) / neutraleTemperatur;
  return (
    r: math.pow(t, 0.55).toDouble(),
    g: 1 - toenung.clamp(-100.0, 100.0) / 400,
    b: math.pow(1 / t, 0.55).toDouble(),
  );
}

/// Eine Temperatur aus der Zeit vor Schema 102 in der heutigen Bedeutung.
///
/// Bis dahin hiess „höher“ kühler (#356): Rot `t^-0.55`, Blau `t^0.55`. Die
/// heutige Rechnung ([weissabgleichFaktoren]) vertauscht nur die Exponenten.
/// Dasselbe Bild ergibt sich deshalb mit dem Kehrwert von `t`, also der
/// Spiegelung um 6500 K auf der logarithmischen Skala: `6500² / alt`.
///
/// Erst geklemmt wie in den alten Renderern: Ein Wert ausserhalb von 2000 …
/// 12000 K wirkte wie die nächste Grenze und soll das weiter tun.
///
/// Eine einzige Division statt `pow` oder `log`: Sie ist in IEEE 754 auf
/// jedem Gerät bitgleich. Server, Rechner und Handy rechnen ihre Kopien
/// unabhängig voneinander um und kommen dabei auf dieselbe Zahl.
///
/// **Genau einmal je Wert.** Zweimal angewandt kommt nicht der Ausgangswert
/// heraus (2000 → 21125 → 3520,8): Wer die Funktion aufruft, muss wissen,
/// dass der Wert noch die alte Bedeutung trägt – über die Schemastufe
/// (Schritt 102 der Migration) oder die Fassung eines gespeicherten
/// Entwicklungsstands.
double temperaturAusFruehererBedeutung(double alt) =>
    neutraleTemperatur *
    neutraleTemperatur /
    alt.clamp(_frueherMin, _frueherMax).toDouble();

double _linear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// Wie Temperatur und Farbstich stehen müssen, damit die Farbe [r], [g],
/// [b] (sRGB 0..1, so wie sie gerade angezeigt wird) neutral wird (#353).
///
/// [temperatur] und [toenung] sind die Werte, mit denen sie gerade
/// entstanden ist: Gerechnet wird von dort aus, darum verfeinert ein zweiter
/// Klick auf dieselbe Stelle das Ergebnis.
///
/// `null` für eine Stelle, die fast schwarz oder ausgebrannt ist. Dort sagt
/// das Verhältnis der Kanäle nichts mehr über das Licht.
///
/// Die Umkehrung von [weissabgleichFaktoren]: Rot zu Blau ändert sich mit
/// `t^1.1`. Eine zu warme Stelle (mehr Rot als Blau) braucht deshalb eine
/// niedrigere Temperatur, eine zu kalte eine höhere – wie in Lightroom.
({double temperatur, double toenung})? weissabgleichFuer(
  double r,
  double g,
  double b, {
  double temperatur = neutraleTemperatur,
  double toenung = 0,
}) {
  for (final k in [r, g, b]) {
    if (k < 0.03 || k > 0.97) return null;
  }
  final rl = _linear(r), gl = _linear(g), bl = _linear(b);
  final neu = temperatur * math.exp(math.log(bl / rl) / 1.1);
  // Wie viel mehr Grün gebraucht wird, damit es zu Rot und Blau passt.
  final gruen = math.sqrt(rl * bl) / gl;
  final neuTon = 400 * (1 - (1 - toenung / 400) * gruen);
  return (
    temperatur: neu.clamp(temperaturMin, temperaturMax).toDouble(),
    toenung: neuTon.clamp(-100.0, 100.0).toDouble(),
  );
}
