import 'dart:math' as math;

import 'package:kern/services/zusammenfuegen/raster.dart';

/// Künstliche Szenen für die Tests des Zusammenfügens (#498): Muster aus
/// Zellen dreier Grössen mit zufälligen, aber festen Helligkeiten – Kanten
/// und Ecken auf allen Massstäben, wie sie Ausrichtung und Merkmale
/// brauchen, und kein Muster, das sich wiederholt.

double _streuwert(int x, int y) {
  var h = x * 374761393 + y * 668265263;
  h = (h ^ (h >> 13)) * 1274126177;
  return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0;
}

double _muster(double x, double y, double z1, double z2, double z3, int saat) {
  var t = 0.0;
  t += _streuwert((x / z1).floor() + saat, (y / z1).floor());
  t += _streuwert((x / z2).floor() + 1000 + saat, (y / z2).floor());
  t += _streuwert((x / z3).floor() + 2000 + saat, (y / z3).floor());
  return t / 3;
}

/// Die Strahlungsdichte einer Szene, die von links nach rechts über
/// [blenden] Blendenstufen heller wird (Mitte bei 2^-1), mit Muster.
double _szene(double x, double y, int breite, double blenden) {
  final basis = math.pow(2, -1 - blenden / 2 + blenden * x / breite);
  return basis * (0.3 + 0.7 * _muster(x, y, 9, 31, 97, 0));
}

/// Eine Aufnahme der Belichtungsszene mit [ev] Blendenstufen Korrektur.
/// Ein Punkt p des Fotos zeigt die Szene an R(winkel)(p − m) + m + (dx,
/// dy) – dieselbe Festlegung wie `Lage`. Gemittelt über 3 × 3 Punkte je
/// Bildpunkt, damit die Kanten wie in einer Kamera auf Bruchteile fallen;
/// Gamma 2,2 und Abschneiden bei Weiss wie ein JPEG aus der Kamera.
Farbbild belichtungsaufnahme(
  int breite,
  int hoehe,
  double ev, {
  double dx = 0,
  double dy = 0,
  double winkelGrad = 0,
  double blenden = 8,
}) {
  final b = Farbbild.leer(breite, hoehe);
  final w = winkelGrad * math.pi / 180;
  final c = math.cos(w), s = math.sin(w);
  final mx = (breite - 1) / 2, my = (hoehe - 1) / 2;
  final faktor = math.pow(2, ev);
  for (var y = 0; y < hoehe; y++) {
    for (var x = 0; x < breite; x++) {
      var l = 0.0;
      for (var a = -1; a <= 1; a++) {
        for (var e = -1; e <= 1; e++) {
          final px = x + a / 3 - mx, py = y + e / 3 - my;
          final sx = c * px - s * py + mx + dx;
          final sy = s * px + c * py + my + dy;
          l += _szene(sx + 0.5, sy + 0.5, breite, blenden);
        }
      }
      final v = math.pow((l / 9 * faktor).clamp(0.0, 1.0), 1 / 2.2) * 255;
      final o = (y * breite + x) * 3;
      // Ein wenig Farbe, damit die Sättigung etwas zu wiegen hat; Weiss
      // bleibt Weiss.
      b.rgb[o] = v.round();
      b.rgb[o + 1] = (v * 0.92 + 255 * 0.08 * (v / 255)).round().clamp(0, 255);
      b.rgb[o + 2] = (v * 0.8 + 255 * 0.2 * math.pow(v / 255, 4)).round().clamp(
        0,
        255,
      );
    }
  }
  return b;
}

/// Eine Aufnahme einer Umgebung um die Kamera (ein Muster auf der Kugel,
/// in Grad), mit einer Lochkamera der Brennweite [f] Punkte, um [gierGrad]
/// nach rechts gedreht und um [nickGrad] nach oben geneigt. [saat] wählt
/// eine andere Umgebung, [helligkeit] belichtet heller oder dunkler.
Farbbild schwenkaufnahme(
  int breite,
  int hoehe,
  double f,
  double gierGrad, {
  double nickGrad = 0,
  double helligkeit = 1,
  int saat = 0,
}) {
  final b = Farbbild.leer(breite, hoehe);
  final g = gierGrad * math.pi / 180, n = nickGrad * math.pi / 180;
  final cg = math.cos(g), sg = math.sin(g);
  final cn = math.cos(n), sn = math.sin(n);
  const grad = 180 / math.pi;
  for (var y = 0; y < hoehe; y++) {
    for (var x = 0; x < breite; x++) {
      var v = 0.0;
      for (var a = 0; a < 2; a++) {
        for (var e = 0; e < 2; e++) {
          final px = x + (a - 0.5) / 2 - (breite - 1) / 2;
          final py = y + (e - 0.5) / 2 - (hoehe - 1) / 2;
          // Erst nicken (um x), dann gieren (um y); y zeigt nach unten.
          final y1 = py * cn - f * sn, z1 = py * sn + f * cn;
          final dx = px * cg + z1 * sg, dz = -px * sg + z1 * cg;
          final waag = math.sqrt(dx * dx + dz * dz);
          final t = math.atan2(dx, dz) * grad;
          final h = math.atan2(y1, waag) * grad;
          v += _muster(t + 400, h + 400, 1.3, 4.1, 13.7, saat * 7919) / 4;
        }
      }
      final wert = ((v * 200 + 25) * helligkeit).round().clamp(0, 255);
      final o = (y * breite + x) * 3;
      b.rgb[o] = wert;
      b.rgb[o + 1] = (wert * 0.95).round();
      b.rgb[o + 2] = (wert * 0.85).round();
    }
  }
  return b;
}

/// Wie viel Zeichnung ein Bereich hat: die mittlere Abweichung jedes
/// Punkts vom Mittel seiner 9 × 9-Umgebung, in Stufen. Gemessen in den
/// Spalten [von] bis [bis] (Anteile der Breite).
double zeichnung(Farbbild b, double von, double bis) {
  final g = Graubild.aus(b);
  final w = b.breite, h = b.hoehe;
  final x0 = math.max(4, (von * w).round());
  final x1 = math.min(w - 4, (bis * w).round());
  var summe = 0.0;
  var n = 0;
  for (var y = 4; y < h - 4; y += 2) {
    for (var x = x0; x < x1; x += 2) {
      var m = 0.0;
      for (var dy = -4; dy <= 4; dy++) {
        for (var dx = -4; dx <= 4; dx++) {
          m += g.werte[(y + dy) * w + x + dx];
        }
      }
      summe += (g.werte[y * w + x] - m / 81).abs();
      n++;
    }
  }
  return summe / n;
}

/// Der Anteil der Punkte, deren Helligkeit [bedingung] erfüllt.
double anteil(Farbbild b, bool Function(int helligkeit) bedingung) {
  final g = Graubild.aus(b);
  var n = 0;
  for (final v in g.werte) {
    if (bedingung(v)) n++;
  }
  return n / g.werte.length;
}
