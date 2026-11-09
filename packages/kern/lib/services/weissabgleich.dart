import 'dart:math' as math;

/// Welcher Renderweg die Regler umsetzt. Die beiden reagieren verschieden,
/// siehe [weissabgleichFuer].
enum Weissweg {
  /// Der Shader (`whiteBalanceGain` in develop_adjustments.frag).
  shader,

  /// `CITemperatureAndTint` auf dem Mac, für alles ausser RAW.
  coreImage,
}

double _linear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// Was `CITemperatureAndTint` an grauer Fläche tut, gemessen in linearem
/// Licht: Kelvin, ln(Rot/Blau) und ln(Grün/√(Rot·Blau)). Die Wirkung folgt
/// keiner einfachen Formel, zwischen 2000 und 3000 K ändert sie sich
/// zehnmal so schnell wie zwischen 10000 und 12000 K. Ein fester Exponent
/// schoss deshalb im Warmen über das Ziel und blieb im Kalten zu kurz.
const _coreImageKurve = <(double, double, double)>[
  (2000, 4.7275, 1.0418),
  (2500, 2.6834, 0.4083),
  (3000, 1.8545, 0.2561),
  (3500, 1.3406, 0.1723),
  (4000, 0.9683, 0.1234),
  (4500, 0.6823, 0.0859),
  (5000, 0.4578, 0.0586),
  (5500, 0.2750, 0.0342),
  (6000, 0.1253, 0.0152),
  (6500, 0, 0),
  (7000, -0.1060, -0.0143),
  (8000, -0.2761, -0.0355),
  (9000, -0.4035, -0.0552),
  (10000, -0.5050, -0.0682),
  (11000, -0.5847, -0.0802),
  (12000, -0.6494, -0.0904),
];

/// Um so viel ändert eine Einheit Farbstich dort ln(Grün/√(Rot·Blau)).
const _coreImageFarbstich = 0.0061;

/// Die Messwerte bei [kelvin].
(double, double) _kurveBei(double kelvin) {
  final k = _coreImageKurve;
  if (kelvin <= k.first.$1) return (k.first.$2, k.first.$3);
  for (var i = 1; i < k.length; i++) {
    if (kelvin <= k[i].$1) {
      final t = (kelvin - k[i - 1].$1) / (k[i].$1 - k[i - 1].$1);
      return (
        k[i - 1].$2 + (k[i].$2 - k[i - 1].$2) * t,
        k[i - 1].$3 + (k[i].$3 - k[i - 1].$3) * t,
      );
    }
  }
  return (k.last.$2, k.last.$3);
}

/// Die Temperatur, bei der ln(Rot/Blau) den Wert [wirkung] hat.
double _kelvinFuer(double wirkung) {
  final k = _coreImageKurve;
  if (wirkung >= k.first.$2) return k.first.$1;
  for (var i = 1; i < k.length; i++) {
    if (wirkung >= k[i].$2) {
      final t = (k[i - 1].$2 - wirkung) / (k[i - 1].$2 - k[i].$2);
      return k[i - 1].$1 + (k[i].$1 - k[i - 1].$1) * t;
    }
  }
  return k.last.$1;
}

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
/// Im Shader gilt `Rot = t^-0.55`, `Blau = t^0.55` mit `t = Temperatur /
/// 6500`, das lässt sich genau umstellen. Für Core Image steht die Wirkung
/// in [_coreImageKurve]. Der Farbstich hat dort das umgekehrte Vorzeichen
/// des Shaders, die Regler wirken also je nach Renderweg verschieden.
({double temperatur, double toenung})? weissabgleichFuer(
  double r,
  double g,
  double b, {
  double temperatur = 6500,
  double toenung = 0,
  Weissweg weg = Weissweg.shader,
}) {
  for (final k in [r, g, b]) {
    if (k < 0.03 || k > 0.97) return null;
  }
  final rl = _linear(r), gl = _linear(g), bl = _linear(b);
  final rotBlau = math.log(rl / bl);
  // Wie viel mehr Grün gebraucht wird, damit es zu Rot und Blau passt.
  final gruen = math.log(math.sqrt(rl * bl) / gl);
  final double neu;
  final double neuTon;
  if (weg == Weissweg.shader) {
    neu = temperatur * math.pow(math.e, rotBlau / 1.1);
    neuTon = 400 * (1 - (1 - toenung / 400) * math.exp(gruen));
  } else {
    final vorher = _kurveBei(temperatur);
    neu = _kelvinFuer(vorher.$1 - rotBlau);
    // Die Temperatur verschiebt das Grün dort schon mit.
    final schon = _kurveBei(neu).$2 - vorher.$2;
    neuTon = toenung + (gruen - schon) / _coreImageFarbstich;
  }
  return (
    temperatur: neu.clamp(2000.0, 12000.0).toDouble(),
    toenung: neuTon.clamp(-100.0, 100.0),
  );
}
