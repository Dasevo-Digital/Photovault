/// Tonwertkurve und Farbmischer des Entwickeln-Bildschirms – die Mathematik
/// dahinter, und zwar **genau einmal**.
///
/// Beide Werkzeuge müssen an zwei völlig verschiedenen Stellen wirken: im
/// GPU-Shader für die Live-Vorschau (`shaders/develop_adjustments.frag`)
/// und in der Core-Image-Kette für das gespeicherte Ergebnis
/// (`ImageConverter.swift`). Der naheliegende Weg wäre, die Formeln in GLSL
/// und in Swift zu wiederholen – der Fahrplan nennt genau das als Risiko
/// ("Shader + native Seite doppelt zu pflegen").
///
/// Stattdessen rechnet dieses Modul beide Werkzeuge zu **Nachschlage-
/// tabellen** aus, die beide Renderpfade unverändert übernehmen: eine
/// 256er-Kurventabelle (`CIColorCurves` bzw. eine 256×1-Textur) und einen
/// Farbwürfel (`CIColorCube` bzw. eine 2D-Streifentextur). Damit gibt es
/// keine zweite Implementierung, die auseinanderlaufen könnte, und die
/// Mathematik ist ohne GPU und ohne Swift prüfbar.
///
/// **Farbraum:** Beide Tabellen wirken auf sRGB-Werten, nicht auf linearen.
/// Das ist die Konvention von Lightroom und darktable, und nur so
/// entspricht die gezeichnete Kurve dem, was der Nutzer auf dem Schirm
/// sieht. Im Shader heißt das: Nachschlagen erst **nach** `linearToSrgb`.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'cube_lut.dart';

/// Ein Kontrollpunkt der Tonwertkurve. Beide Achsen sind auf 0..1
/// normalisiert – links unten ist Schwarz, rechts oben Weiß.
class CurvePoint {
  final double input;
  final double output;

  const CurvePoint(this.input, this.output);

  Map<String, dynamic> toJson() => {'x': input, 'y': output};

  static CurvePoint fromJson(Map<String, dynamic> json) =>
      CurvePoint((json['x'] as num).toDouble(), (json['y'] as num).toDouble());

  @override
  bool operator ==(Object other) =>
      other is CurvePoint && other.input == input && other.output == output;

  @override
  int get hashCode => Object.hash(input, output);

  @override
  String toString() => 'CurvePoint($input, $output)';
}

/// Welcher Kanal einer Tonwertkurve bearbeitet wird.
enum CurveChannel { zusammen, rot, gruen, blau }

/// Die Identität: eine Gerade von Schwarz nach Weiß.
const _geradeKurve = [CurvePoint(0, 0), CurvePoint(1, 1)];

/// Anzahl der Stufen einer Kurventabelle – 8 Bit, wie das Histogramm auch
/// (siehe `histogramBinCount`).
const curveLutSize = 256;

/// Tonwertkurve mit je einer Punktfolge für den Zusammen-Kanal und die drei
/// Farbkanäle.
///
/// **Reihenfolge:** Erst wirkt die Kurve des jeweiligen Farbkanals, danach
/// die Zusammen-Kurve auf dem Ergebnis. Das entspricht Photoshop und
/// Lightroom; die umgekehrte Reihenfolge liefert für dieselben Punkte
/// sichtbar andere Bilder, sie ist deshalb keine Geschmacksfrage, sondern
/// muss festgelegt sein.
class ToneCurve {
  final List<CurvePoint> zusammen;
  final List<CurvePoint> rot;
  final List<CurvePoint> gruen;
  final List<CurvePoint> blau;

  const ToneCurve({
    this.zusammen = _geradeKurve,
    this.rot = _geradeKurve,
    this.gruen = _geradeKurve,
    this.blau = _geradeKurve,
  });

  /// Alle vier Kanäle als Gerade – ändert nichts.
  static const neutral = ToneCurve();

  List<CurvePoint> kanal(CurveChannel c) => switch (c) {
        CurveChannel.zusammen => zusammen,
        CurveChannel.rot => rot,
        CurveChannel.gruen => gruen,
        CurveChannel.blau => blau,
      };

  ToneCurve mitKanal(CurveChannel c, List<CurvePoint> punkte) => ToneCurve(
        zusammen: c == CurveChannel.zusammen ? punkte : zusammen,
        rot: c == CurveChannel.rot ? punkte : rot,
        gruen: c == CurveChannel.gruen ? punkte : gruen,
        blau: c == CurveChannel.blau ? punkte : blau,
      );

  /// Ob die Kurve nichts bewirkt. Wird sie hier erkannt, entfällt der
  /// Filter bzw. die Textur komplett, statt eine Identität mitzurechnen.
  bool get istNeutral => CurveChannel.values.every((c) => _istGerade(kanal(c)));

  static bool _istGerade(List<CurvePoint> punkte) {
    if (punkte.length != 2) return false;
    return punkte[0].input == 0 &&
        punkte[0].output == 0 &&
        punkte[1].input == 1 &&
        punkte[1].output == 1;
  }

  Map<String, dynamic> toJson() => {
        for (final c in CurveChannel.values)
          if (!_istGerade(kanal(c)))
            c.name: [for (final p in kanal(c)) p.toJson()],
      };

  static ToneCurve fromJson(Map<String, dynamic> json) {
    List<CurvePoint> lies(CurveChannel c) {
      final roh = json[c.name];
      if (roh is! List || roh.length < 2) return _geradeKurve;
      return [
        for (final e in roh) CurvePoint.fromJson(e as Map<String, dynamic>),
      ];
    }

    return ToneCurve(
      zusammen: lies(CurveChannel.zusammen),
      rot: lies(CurveChannel.rot),
      gruen: lies(CurveChannel.gruen),
      blau: lies(CurveChannel.blau),
    );
  }

  String encode() => jsonEncode(toJson());

  static ToneCurve decode(String quelle) =>
      fromJson(jsonDecode(quelle) as Map<String, dynamic>);

  /// Wertgleichheit ist hier kein Beiwerk: Die Live-Vorschau baut ihre
  /// Texturen nur neu, wenn sich Kurve oder Mischer geändert haben. Ohne
  /// diesen Vergleich wäre das ein Identitätsvergleich – und der Würfel
  /// entstünde bei jedem einzelnen Bildaufbau neu.
  @override
  bool operator ==(Object other) =>
      other is ToneCurve &&
      CurveChannel.values.every((c) => _gleich(kanal(c), other.kanal(c)));

  @override
  int get hashCode => Object.hashAll([
        for (final c in CurveChannel.values) Object.hashAll(kanal(c)),
      ]);

  static bool _gleich(List<CurvePoint> a, List<CurvePoint> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Die acht Farbbänder des Mischers, mit ihrem Farbton-Mittelpunkt in Grad.
///
/// Dieselbe Einteilung wie in Lightroom. Die Abstände sind bewusst
/// ungleichmäßig – zwischen Rot, Orange und Gelb liegen je 30°, zwischen
/// Gelb und Grün 60°: dort, wo das Auge feiner unterscheidet, liegen die
/// Bänder dichter.
enum ColorBand {
  rot(0),
  orange(30),
  gelb(60),
  gruen(120),
  aqua(180),
  blau(240),
  violett(270),
  magenta(300);

  const ColorBand(this.mittelpunkt);

  /// Farbton-Mittelpunkt in Grad (0..360).
  final double mittelpunkt;
}

/// Die drei Einstellungen eines Farbbands, je -1..1, 0 = unverändert.
class BandAnpassung {
  /// Verschiebt den Farbton, bei ±1 um ±30° – eine halbe Bandbreite. Mehr
  /// würde die Farbe ins Nachbarband kippen, was kein Mischer, sondern ein
  /// Austausch wäre.
  final double farbton;

  /// Sättigung: -1 entfärbt vollständig, +1 verdoppelt.
  final double saettigung;

  /// Helligkeit: -1 führt nach Schwarz, +1 nach Weiß.
  final double helligkeit;

  const BandAnpassung({
    this.farbton = 0,
    this.saettigung = 0,
    this.helligkeit = 0,
  });

  static const neutral = BandAnpassung();

  bool get istNeutral => farbton == 0 && saettigung == 0 && helligkeit == 0;

  Map<String, dynamic> toJson() => {
        if (farbton != 0) 'h': farbton,
        if (saettigung != 0) 's': saettigung,
        if (helligkeit != 0) 'l': helligkeit,
      };

  static BandAnpassung fromJson(Map<String, dynamic> json) => BandAnpassung(
        farbton: (json['h'] as num?)?.toDouble() ?? 0,
        saettigung: (json['s'] as num?)?.toDouble() ?? 0,
        helligkeit: (json['l'] as num?)?.toDouble() ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is BandAnpassung &&
      other.farbton == farbton &&
      other.saettigung == saettigung &&
      other.helligkeit == helligkeit;

  @override
  int get hashCode => Object.hash(farbton, saettigung, helligkeit);
}

/// Kantenlänge des Farbwürfels. 32³ = 32768 Stützstellen; zwischen ihnen
/// interpolieren sowohl Core Image als auch der Shader trilinear. 16³ wäre
/// halb so groß, zeigt bei kräftigen Farbtonverschiebungen aber sichtbare
/// Stufen.
const colorCubeSize = 32;

/// Kantenlänge für die Live-Vorschau während des Regler-Ziehens.
///
/// Der Würfel wird bei jeder Reglerbewegung neu gebaut, und das kostet
/// gemessen 3,01 ms bei 32³ gegenüber 0,38 ms bei 16³ – bei einem
/// Bildbudget von 16,7 ms ist das der Unterschied zwischen spürbar und
/// unmerklich. Die gröbere Abstufung ist vertretbar, weil für das
/// gespeicherte Ergebnis ohnehin der native Renderpfad mit [colorCubeSize]
/// massgeblich ist (siehe develop_adjustments.frag).
const colorCubePreviewSize = 16;

/// Sättigungsschwelle, unterhalb derer der Mischer nicht mehr greift.
///
/// Der Grund ist keine Feinabstimmung, sondern Mathematik: Der Farbton
/// eines nahezu grauen Pixels ist numerisch instabil – winzige
/// Kanalunterschiede bestimmen ihn. Ohne diese Sperre würde ein Farbton-
/// Regler grauen Flächen und Rauschen eine Farbe geben.
const _saettigungsSperre = 0.15;

/// Farbmischer: acht Farbbänder mit je Farbton, Sättigung und Helligkeit.
class ColorMixer {
  final Map<ColorBand, BandAnpassung> baender;

  const ColorMixer(this.baender);

  static const neutral = ColorMixer({});

  BandAnpassung band(ColorBand b) => baender[b] ?? BandAnpassung.neutral;

  ColorMixer mitBand(ColorBand b, BandAnpassung a) =>
      ColorMixer({...baender, b: a});

  bool get istNeutral => baender.values.every((a) => a.istNeutral);

  Map<String, dynamic> toJson() => {
        for (final e in baender.entries)
          if (!e.value.istNeutral) e.key.name: e.value.toJson(),
      };

  static ColorMixer fromJson(Map<String, dynamic> json) => ColorMixer({
        for (final b in ColorBand.values)
          if (json[b.name] is Map)
            b: BandAnpassung.fromJson(json[b.name] as Map<String, dynamic>),
      });

  String encode() => jsonEncode(toJson());

  static ColorMixer decode(String quelle) =>
      fromJson(jsonDecode(quelle) as Map<String, dynamic>);

  /// Über [band] verglichen, nicht über die Map: Ein Eintrag mit lauter
  /// Nullen und ein fehlender Eintrag bedeuten dasselbe und dürfen keinen
  /// Neubau des Farbwürfels auslösen. Siehe [ToneCurve.==].
  @override
  bool operator ==(Object other) =>
      other is ColorMixer && ColorBand.values.every((b) => band(b) == other.band(b));

  @override
  int get hashCode => Object.hashAll([for (final b in ColorBand.values) band(b)]);
}

// --- Lesen aus der Datenbank ---------------------------------------------

/// Liest eine gespeicherte Kurve aus `DevelopSettings.toneCurveJson`.
///
/// `null`, leer **und unlesbar** ergeben die neutrale Kurve: Ein
/// beschädigter JSON-Text darf den Entwickeln-Bildschirm nicht am Öffnen
/// hindern. Dann fehlt eine Anpassung, statt dass das Foto unerreichbar
/// wird.
ToneCurve toneCurveAus(String? json) {
  if (json == null || json.isEmpty) return ToneCurve.neutral;
  try {
    return ToneCurve.decode(json);
  } catch (_) {
    return ToneCurve.neutral;
  }
}

/// Gegenstück zu [toneCurveAus] für `DevelopSettings.colorMixerJson`.
ColorMixer colorMixerAus(String? json) {
  if (json == null || json.isEmpty) return ColorMixer.neutral;
  try {
    return ColorMixer.decode(json);
  } catch (_) {
    return ColorMixer.neutral;
  }
}

// --- Tonwertkurve ---------------------------------------------------------

/// Wertet eine Punktfolge an der Stelle [x] aus – monotone kubische
/// Interpolation nach Fritsch–Carlson.
///
/// Bewusst **nicht** Catmull-Rom oder eine natürliche Spline: Beide
/// überschwingen zwischen eng gesetzten Punkten und kehren die Kurve dort
/// örtlich um. Auf einer Tonwertkurve heißt das, dass ein aufgehellter
/// Bereich plötzlich wieder dunkler wird – der klassische Fehler an dieser
/// Stelle, und einer, den man erst am fertigen Bild bemerkt. Fritsch–Carlson
/// dämpft die Steigungen genau so weit, dass das nicht passieren kann.
double evaluateCurve(List<CurvePoint> punkte, double x) {
  if (punkte.length < 2) return x.clamp(0.0, 1.0);

  final p = [...punkte]..sort((a, b) => a.input.compareTo(b.input));
  final n = p.length;

  if (x <= p.first.input) return p.first.output.clamp(0.0, 1.0);
  if (x >= p.last.input) return p.last.output.clamp(0.0, 1.0);

  // Sekantensteigungen zwischen benachbarten Punkten.
  final d = List<double>.filled(n - 1, 0);
  for (var i = 0; i < n - 1; i++) {
    final dx = p[i + 1].input - p[i].input;
    // Zwei Punkte auf derselben Senkrechten: Steigung undefiniert, als
    // waagerecht behandeln statt durch null zu teilen.
    d[i] = dx == 0 ? 0 : (p[i + 1].output - p[i].output) / dx;
  }

  // Ausgangstangenten: an den Enden die Sekante, dazwischen ihr Mittel.
  final m = List<double>.filled(n, 0);
  m[0] = d[0];
  m[n - 1] = d[n - 2];
  for (var i = 1; i < n - 1; i++) {
    m[i] = (d[i - 1] + d[i]) / 2;
  }

  // Die eigentliche Fritsch–Carlson-Dämpfung: Wo die Sekante waagerecht ist,
  // müssen beide angrenzenden Tangenten null sein; sonst wird das Paar auf
  // den Kreis mit Radius 3 zurückgezogen. Beides zusammen garantiert, dass
  // die Kurve zwischen zwei Punkten nie die Richtung wechselt.
  for (var i = 0; i < n - 1; i++) {
    if (d[i] == 0) {
      m[i] = 0;
      m[i + 1] = 0;
      continue;
    }
    final alpha = m[i] / d[i];
    final beta = m[i + 1] / d[i];
    final quadrat = alpha * alpha + beta * beta;
    if (quadrat > 9) {
      final tau = 3 / math.sqrt(quadrat);
      m[i] = tau * alpha * d[i];
      m[i + 1] = tau * beta * d[i];
    }
  }

  var k = 0;
  while (k < n - 2 && x > p[k + 1].input) {
    k++;
  }

  final h = p[k + 1].input - p[k].input;
  if (h == 0) return p[k + 1].output.clamp(0.0, 1.0);
  final t = (x - p[k].input) / h;
  final t2 = t * t;
  final t3 = t2 * t;

  final wert = (2 * t3 - 3 * t2 + 1) * p[k].output +
      (t3 - 2 * t2 + t) * h * m[k] +
      (-2 * t3 + 3 * t2) * p[k + 1].output +
      (t3 - t2) * h * m[k + 1];

  return wert.clamp(0.0, 1.0);
}

/// Rechnet [kurve] zu einer Tabelle aus: [curveLutSize] Stufen, je ein
/// Tripel Rot/Grün/Blau, verschachtelt abgelegt (R₀G₀B₀R₁G₁B₁…).
///
/// Genau dieses Format erwartet `CIColorCurves.inputCurvesData`; der Shader
/// liest dieselbe Tabelle als 256×1-Textur. Die Verschachtelung ist deshalb
/// keine Geschmacksfrage, sondern durch Core Image vorgegeben.
Float32List buildCurveLut(ToneCurve kurve) {
  final tabelle = Float32List(curveLutSize * 3);
  for (var i = 0; i < curveLutSize; i++) {
    final eingang = i / (curveLutSize - 1);
    // Erst der Farbkanal, dann der Zusammen-Kanal – siehe ToneCurve.
    tabelle[i * 3] = evaluateCurve(kurve.zusammen, evaluateCurve(kurve.rot, eingang));
    tabelle[i * 3 + 1] = evaluateCurve(kurve.zusammen, evaluateCurve(kurve.gruen, eingang));
    tabelle[i * 3 + 2] = evaluateCurve(kurve.zusammen, evaluateCurve(kurve.blau, eingang));
  }
  return tabelle;
}

// --- Farbmischer ----------------------------------------------------------

/// Gewicht jedes Farbbands für einen Farbton [grad] (0..360).
///
/// Zwischen zwei benachbarten Mittelpunkten wird linear geblendet, alle
/// übrigen Bänder sind null. Dadurch ergeben die Gewichte in **jedem** Fall
/// zusammen genau 1 – ein Pixel wird also nie doppelt angefasst, und ein
/// unangetastetes Band kann seine Nachbarn nicht beeinflussen. Eine
/// Glockenkurve je Band wäre weicher, summierte sich aber je nach Farbton
/// auf unterschiedliche Werte und würde die Farben verschieben, obwohl alle
/// Regler auf null stehen.
List<double> bandWeights(double grad) {
  final gewichte = List<double>.filled(ColorBand.values.length, 0);
  final h = grad % 360;

  for (var i = 0; i < ColorBand.values.length; i++) {
    final links = ColorBand.values[i].mittelpunkt;
    final j = (i + 1) % ColorBand.values.length;
    // Das letzte Band (Magenta, 300°) reicht über 360° hinweg zurück zu Rot.
    final rechts = j == 0 ? 360.0 : ColorBand.values[j].mittelpunkt;

    if (h >= links && h < rechts) {
      final t = (h - links) / (rechts - links);
      gewichte[i] = 1 - t;
      gewichte[j] = t;
      return gewichte;
    }
  }

  // Nur erreichbar, wenn h exakt 0 ist und die Schleife oben nicht greift.
  gewichte[0] = 1;
  return gewichte;
}

/// Wendet [mixer] auf eine einzelne sRGB-Farbe an (Komponenten 0..1).
///
/// Öffentlich, damit sich die Wirkung punktweise prüfen lässt, ohne den
/// ganzen Würfel zu bauen.
List<double> applyColorMixer(ColorMixer mixer, double r, double g, double b) {
  final hsl = _rgbZuHsl(r, g, b);
  var h = hsl[0], s = hsl[1], l = hsl[2];

  // Graue und fast graue Pixel bleiben unangetastet – siehe _saettigungsSperre.
  if (s < _saettigungsSperre) {
    final rand = s / _saettigungsSperre;
    if (rand <= 0) return [r, g, b];
    // Weicher Übergang, damit an der Schwelle keine Kante im Bild entsteht.
    return _blende(
      [r, g, b],
      _mische(mixer, h, s, l),
      rand * rand * (3 - 2 * rand),
    );
  }

  return _mische(mixer, h, s, l);
}

List<double> _mische(ColorMixer mixer, double h, double s, double l) {
  final gewichte = bandWeights(h);

  var farbton = 0.0, saettigung = 0.0, helligkeit = 0.0;
  for (var i = 0; i < ColorBand.values.length; i++) {
    final gewicht = gewichte[i];
    if (gewicht == 0) continue;
    final a = mixer.band(ColorBand.values[i]);
    farbton += gewicht * a.farbton;
    saettigung += gewicht * a.saettigung;
    helligkeit += gewicht * a.helligkeit;
  }

  final neuH = (h + farbton * 30) % 360;
  final neuS = (s * (1 + saettigung)).clamp(0.0, 1.0);
  // Nach oben gegen Weiß, nach unten gegen Schwarz – beide Formen sind von
  // sich aus begrenzt, ein Abschneiden am Rand kann also keine Farbe kippen.
  final neuL = helligkeit >= 0
      ? l + (1 - l) * helligkeit
      : l * (1 + helligkeit);

  return _hslZuRgb(neuH, neuS, neuL.clamp(0.0, 1.0));
}

List<double> _blende(List<double> a, List<double> b, double t) =>
    [for (var i = 0; i < 3; i++) a[i] + (b[i] - a[i]) * t];

/// Baut den Farbwürfel für [mixer]: [colorCubeSize]³ Stützstellen, je
/// RGBA-Fließkomma.
///
/// Reihenfolge der Einträge: Rot läuft am schnellsten, dann Grün, dann Blau
/// – so und nicht anders erwartet `CIColorCube` seine Daten. Der Alphawert
/// ist durchgehend 1; die Daten gelten damit zugleich als vorvervielfacht,
/// was Core Image ebenfalls voraussetzt.
/// [lut] ist eine eingelesene `.cube`-Tabelle, die NACH dem Mischer wirkt,
/// [lutStaerke] blendet sie von 0 (aus) bis 1 (voll) ein.
///
/// Die Reihenfolge ist nicht beliebig: Der Mischer ist eine Korrektur am
/// Bild, der Look kommt darüber. Andersherum verschöbe eine
/// Sättigungskorrektur die Farben, die der Look bereits gesetzt hat.
///
/// Dass der Look hier hineingerechnet wird und nicht als eigener Schritt in
/// die Kette kommt, ist der ganze Trick: Beide Renderpfade – Shader wie
/// Core Image – bekommen weiterhin genau einen Würfel und müssen nichts
/// dazulernen.
Float32List buildColorCube(
  ColorMixer mixer, {
  int size = colorCubeSize,
  CubeLut? lut,
  double lutStaerke = 1,
}) {
  final wuerfel = Float32List(size * size * size * 4);
  final letzter = size - 1;
  final staerke = lutStaerke.clamp(0.0, 1.0);
  final lookAktiv = lut != null && staerke > 0;
  var i = 0;

  for (var bi = 0; bi < size; bi++) {
    final b = bi / letzter;
    for (var gi = 0; gi < size; gi++) {
      final g = gi / letzter;
      for (var ri = 0; ri < size; ri++) {
        final r = ri / letzter;
        var aus = applyColorMixer(mixer, r, g, b);
        if (lookAktiv) {
          final look = lut.abtasten(aus[0], aus[1], aus[2]);
          aus = staerke >= 1 ? look : _blende(aus, look, staerke);
        }
        wuerfel[i++] = aus[0];
        wuerfel[i++] = aus[1];
        wuerfel[i++] = aus[2];
        wuerfel[i++] = 1;
      }
    }
  }
  return wuerfel;
}

// --- Verpacken für den Shader --------------------------------------------

/// Die Kurventabelle als RGBA-Bytes einer [curveLutSize]×1-Textur.
Uint8List packCurveLutForTexture(Float32List tabelle) {
  final bytes = Uint8List(curveLutSize * 4);
  for (var i = 0; i < curveLutSize; i++) {
    bytes[i * 4] = _zuByte(tabelle[i * 3]);
    bytes[i * 4 + 1] = _zuByte(tabelle[i * 3 + 1]);
    bytes[i * 4 + 2] = _zuByte(tabelle[i * 3 + 2]);
    bytes[i * 4 + 3] = 255;
  }
  return bytes;
}

/// Breite der Würfeltextur: alle Blau-Scheiben nebeneinander.
int colorCubeStripWidth(int size) => size * size;

/// Den Farbwürfel als RGBA-Bytes einer (size·size)×size-Textur.
///
/// Flutter-Shader kennen nur zweidimensionale Abtaster, ein echter
/// 3D-Würfel ist also nicht übertragbar. Übliche Lösung: die Blau-Scheiben
/// nebeneinanderlegen. Rot läuft innerhalb einer Scheibe waagerecht, Grün
/// senkrecht, Blau wählt die Scheibe – der Shader interpoliert zwischen zwei
/// benachbarten Scheiben von Hand.
Uint8List packColorCubeForTexture(Float32List wuerfel, {int size = colorCubeSize}) {
  final breite = colorCubeStripWidth(size);
  final bytes = Uint8List(breite * size * 4);

  for (var b = 0; b < size; b++) {
    for (var g = 0; g < size; g++) {
      for (var r = 0; r < size; r++) {
        final quelle = ((b * size + g) * size + r) * 4;
        final x = b * size + r;
        final ziel = (g * breite + x) * 4;
        bytes[ziel] = _zuByte(wuerfel[quelle]);
        bytes[ziel + 1] = _zuByte(wuerfel[quelle + 1]);
        bytes[ziel + 2] = _zuByte(wuerfel[quelle + 2]);
        bytes[ziel + 3] = 255;
      }
    }
  }
  return bytes;
}

int _zuByte(double wert) => (wert.clamp(0.0, 1.0) * 255).round();

// --- Farbraum-Umrechnung --------------------------------------------------

/// sRGB (0..1) nach HSL: Farbton in Grad, Sättigung und Helligkeit 0..1.
List<double> _rgbZuHsl(double r, double g, double b) {
  final max = math.max(r, math.max(g, b));
  final min = math.min(r, math.min(g, b));
  final l = (max + min) / 2;

  if (max == min) return [0, 0, l];

  final d = max - min;
  final s = l > 0.5 ? d / (2 - max - min) : d / (max + min);

  double h;
  if (max == r) {
    h = (g - b) / d + (g < b ? 6 : 0);
  } else if (max == g) {
    h = (b - r) / d + 2;
  } else {
    h = (r - g) / d + 4;
  }

  return [h * 60, s, l];
}

/// HSL zurück nach sRGB (0..1).
List<double> _hslZuRgb(double h, double s, double l) {
  if (s == 0) return [l, l, l];

  final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  final p = 2 * l - q;
  final hk = (h % 360) / 360;

  return [
    _kanal(p, q, hk + 1 / 3),
    _kanal(p, q, hk),
    _kanal(p, q, hk - 1 / 3),
  ];
}

double _kanal(double p, double q, double t) {
  var x = t;
  if (x < 0) x += 1;
  if (x > 1) x -= 1;
  if (x < 1 / 6) return p + (q - p) * 6 * x;
  if (x < 1 / 2) return q;
  if (x < 2 / 3) return p + (q - p) * (2 / 3 - x) * 6;
  return p;
}
