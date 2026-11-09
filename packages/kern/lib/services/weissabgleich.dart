import 'dart:math' as math;

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
/// Die Umkehrung von `whiteBalanceGain`: `Rot = t^-0.55`, `Blau = t^0.55` mit
/// `t = Temperatur / 6500`, und `Grün = 1 - Farbstich / 400`. Seit #356 gilt
/// diese eine Rechnung auf allen Renderwegen.
({double temperatur, double toenung})? weissabgleichFuer(
  double r,
  double g,
  double b, {
  double temperatur = 6500,
  double toenung = 0,
}) {
  for (final k in [r, g, b]) {
    if (k < 0.03 || k > 0.97) return null;
  }
  final rl = _linear(r), gl = _linear(g), bl = _linear(b);
  final neu = temperatur * math.exp(math.log(rl / bl) / 1.1);
  // Wie viel mehr Grün gebraucht wird, damit es zu Rot und Blau passt.
  final gruen = math.sqrt(rl * bl) / gl;
  final neuTon = 400 * (1 - (1 - toenung / 400) * gruen);
  return (
    temperatur: neu.clamp(2000.0, 12000.0).toDouble(),
    toenung: neuTon.clamp(-100.0, 100.0).toDouble(),
  );
}
