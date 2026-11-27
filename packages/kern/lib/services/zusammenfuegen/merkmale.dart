/// Merkmale für das Panorama (#498): Ecken nach FAST-9, geordnet nach der
/// Harris-Antwort, beschrieben mit 256 Bit nach BRIEF, zugeordnet mit
/// Ratio-Test und Gegenprobe, geprüft mit RANSAC über eine Homographie.
///
/// **Aufrecht, ohne Drehung des Deskriptors.** ORB dreht jedes Muster
/// nach der Schwerpunktrichtung seiner Umgebung, damit Merkmale auch in
/// gedrehten Bildern wiedererkannt werden. Bei einem Schwenk aus der Hand
/// kippt die Kamera aber nur wenige Grad, und ein aufrechtes Muster
/// unterscheidet dann besser (die Richtung ist bei flachen Ecken selbst
/// ein Rauschwert). BRIEF verträgt bis etwa 10–15° Drehung.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'matrizen.dart';
import 'raster.dart';

/// Die Merkmale eines Bilds: Lage (x, y je Merkmal) und Deskriptor (acht
/// 32-Bit-Wörter je Merkmal).
class Merkmale {
  const Merkmale(this.punkte, this.deskriptoren);

  final Float64List punkte;
  final Uint32List deskriptoren;

  int get anzahl => punkte.length ~/ 2;
}

/// Die 16 Punkte des Bresenham-Kreises mit Radius 3, im Uhrzeigersinn ab
/// oben.
const _kreisX = [0, 1, 2, 3, 3, 3, 2, 1, 0, -1, -2, -3, -3, -3, -2, -1];
const _kreisY = [-3, -3, -2, -1, 0, 1, 2, 3, 3, 3, 2, 1, 0, -1, -2, -3];

/// Halbe Kantenlänge des Musterfelds; Punkte näher am Rand bekommen keinen
/// Deskriptor.
const _rand = 18;

/// Die 256 Vergleichspaare von BRIEF: Gauss-verteilt um die Mitte
/// (σ = 31/5) und auf ±13 begrenzt, damit das 5 × 5-Mittel um jeden Punkt
/// im Feld bleibt. Fester Startwert – dieselben Paare in jedem Lauf und auf
/// jedem Rechner.
final Int8List _paare = () {
  final z = math.Random(4981);
  double gauss() {
    final u = 1 - z.nextDouble(), v = z.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }

  int wert() => (gauss() * 31 / 5).round().clamp(-13, 13);
  return Int8List.fromList([for (var i = 0; i < 256 * 4; i++) wert()]);
}();

/// Findet höchstens [hoechstens] Merkmale in [g] und beschreibt sie.
///
/// Gleichmässig verteilt: Erst bekommt jede Zelle eines 8 × 6-Rasters
/// ihren Anteil der stärksten Ecken, dann füllen die stärksten übrigen
/// auf. Ohne das sammeln sich die Merkmale an einem einzigen kontrastreichen
/// Fleck, und gerade die Überlappung am Bildrand geht leer aus.
Merkmale findeMerkmale(Graubild g, {int hoechstens = 500, int schwelle = 12}) {
  final w = g.breite, h = g.hoehe;
  if (w <= 2 * _rand || h <= 2 * _rand) {
    return Merkmale(Float64List(0), Uint32List(0));
  }
  final q = g.werte;
  final staerke = Float32List(w * h);
  final kandidaten = <int>[];
  for (var y = _rand; y < h - _rand; y++) {
    for (var x = _rand; x < w - _rand; x++) {
      final i = y * w + x;
      if (!_istEcke(q, w, i, schwelle)) continue;
      final r = _harris(q, w, x, y);
      if (r <= 0) continue;
      staerke[i] = r;
      kandidaten.add(i);
    }
  }
  // Nur die stärkste Ecke in ihrer 5 × 5-Nachbarschaft bleibt.
  final ecken = <int>[];
  for (final i in kandidaten) {
    final s = staerke[i];
    var max = true;
    for (var dy = -2; dy <= 2 && max; dy++) {
      for (var dx = -2; dx <= 2; dx++) {
        if (dx == 0 && dy == 0) continue;
        final t = staerke[i + dy * w + dx];
        if (t > s || (t == s && dy * w + dx < 0)) {
          max = false;
          break;
        }
      }
    }
    if (max) ecken.add(i);
  }
  ecken.sort((a, b) => staerke[b].compareTo(staerke[a]));
  const sx = 8, sy = 6;
  final anteil = math.max(1, hoechstens ~/ (sx * sy));
  final jeZelle = Int32List(sx * sy);
  final gewaehlt = <int>[];
  final genommen = <int>{};
  for (final i in ecken) {
    final zelle =
        ((i ~/ w) * sy ~/ h).clamp(0, sy - 1) * sx +
        ((i % w) * sx ~/ w).clamp(0, sx - 1);
    if (jeZelle[zelle] >= anteil) continue;
    jeZelle[zelle]++;
    gewaehlt.add(i);
    genommen.add(i);
  }
  for (final i in ecken) {
    if (gewaehlt.length >= hoechstens) break;
    if (genommen.add(i)) gewaehlt.add(i);
  }
  if (gewaehlt.length > hoechstens) gewaehlt.length = hoechstens;

  // BRIEF auf 5 × 5-Mitteln aus dem Summenbild.
  final summe = Int32List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var zeile = 0;
    for (var x = 0; x < w; x++) {
      zeile += q[y * w + x];
      summe[(y + 1) * (w + 1) + x + 1] = summe[y * (w + 1) + x + 1] + zeile;
    }
  }
  int mittel(int x, int y) {
    final a = (y + 3) * (w + 1) + x + 3, b = (y - 2) * (w + 1) + x + 3;
    final c = (y + 3) * (w + 1) + x - 2, d = (y - 2) * (w + 1) + x - 2;
    return summe[a] - summe[b] - summe[c] + summe[d];
  }

  final punkte = Float64List(gewaehlt.length * 2);
  final desk = Uint32List(gewaehlt.length * 8);
  for (var k = 0; k < gewaehlt.length; k++) {
    final i = gewaehlt[k];
    final x = i % w, y = i ~/ w;
    punkte[k * 2] = x.toDouble();
    punkte[k * 2 + 1] = y.toDouble();
    for (var b = 0; b < 256; b++) {
      final p = b * 4;
      if (mittel(x + _paare[p], y + _paare[p + 1]) <
          mittel(x + _paare[p + 2], y + _paare[p + 3])) {
        desk[k * 8 + (b >> 5)] |= 1 << (b & 31);
      }
    }
  }
  return Merkmale(punkte, desk);
}

/// FAST-9: Mindestens neun zusammenhängende Punkte des Kreises sind alle
/// um mehr als [t] heller oder alle dunkler als die Mitte.
bool _istEcke(Uint8List q, int w, int i, int t) {
  final p = q[i];
  final hell = p + t, dunkel = p - t;
  // Schnelltest an den vier Himmelsrichtungen: Ein Bogen aus neun Punkten
  // trifft mindestens zwei davon.
  // Ausgeschrieben statt über eine Liste: Der Test läuft für jeden Punkt
  // des Bilds, und eine Liste je Punkt war dort der grösste Posten.
  final n = q[i - 3 * w], o = q[i + 3], s = q[i + 3 * w], we = q[i - 3];
  final heller =
      (n > hell ? 1 : 0) +
      (o > hell ? 1 : 0) +
      (s > hell ? 1 : 0) +
      (we > hell ? 1 : 0);
  final dunkler =
      (n < dunkel ? 1 : 0) +
      (o < dunkel ? 1 : 0) +
      (s < dunkel ? 1 : 0) +
      (we < dunkel ? 1 : 0);
  if (heller < 2 && dunkler < 2) return false;
  var mh = 0, md = 0;
  for (var k = 0; k < 16; k++) {
    final v = q[i + _kreisY[k] * w + _kreisX[k]];
    if (v > hell) mh |= 1 << k;
    if (v < dunkel) md |= 1 << k;
  }
  return _neunAmStueck(mh) || _neunAmStueck(md);
}

bool _neunAmStueck(int maske) {
  if (maske == 0) return false;
  var m = maske | (maske << 16);
  for (var k = 1; k < 9; k++) {
    m &= m >> 1;
  }
  // Nach acht Verschiebungen bleibt ein Bit nur dort, wo neun in Folge
  // gesetzt waren; die verdoppelte Maske fängt den Bogen über die
  // Nahtstelle des Kreises.
  return (m & 0xFFFF) != 0;
}

/// Die Harris-Antwort det − 0,04 · spur² des Strukturtensors über 7 × 7
/// Punkte um (x, y), Ableitungen nach Sobel.
double _harris(Uint8List q, int w, int x, int y) {
  var xx = 0.0, yy = 0.0, xy = 0.0;
  for (var dy = -3; dy <= 3; dy++) {
    final z = (y + dy) * w + x;
    for (var dx = -3; dx <= 3; dx++) {
      final i = z + dx;
      final gx =
          (q[i - w + 1] + 2 * q[i + 1] + q[i + w + 1]) -
          (q[i - w - 1] + 2 * q[i - 1] + q[i + w - 1]);
      final gy =
          (q[i + w - 1] + 2 * q[i + w] + q[i + w + 1]) -
          (q[i - w - 1] + 2 * q[i - w] + q[i - w + 1]);
      xx += gx * gx;
      yy += gy * gy;
      xy += gx * gy;
    }
  }
  final spur = xx + yy;
  return xx * yy - xy * xy - 0.04 * spur * spur;
}

int _bits(int v) {
  v = v - ((v >> 1) & 0x55555555);
  v = (v & 0x33333333) + ((v >> 2) & 0x33333333);
  return ((((v + (v >> 4)) & 0x0F0F0F0F) * 0x01010101) & 0xFFFFFFFF) >> 24;
}

/// Ordnet die Merkmale von [a] denen von [b] zu: je Merkmal das nächste
/// nach Hamming-Abstand, wenn es deutlich näher ist als das zweitnächste
/// (Ratio-Test nach Lowe, 0,8), höchstens [hoechstensAbstand] Bit entfernt
/// und umgekehrt ebenso das nächste (Gegenprobe). Gibt Paare von
/// Merkmalsnummern (a, b) zurück.
List<(int, int)> ordneZu(
  Merkmale a,
  Merkmale b, {
  double verhaeltnis = 0.8,
  int hoechstensAbstand = 64,
}) {
  final na = a.anzahl, nb = b.anzahl;
  if (na < 2 || nb < 2) return const [];
  final da = a.deskriptoren, db = b.deskriptoren;
  final bestAB = Int32List(na)..fillRange(0, na, -1);
  final abstandAB = Int32List(na);
  final zweitAB = Int32List(na);
  final bestBA = Int32List(nb)..fillRange(0, nb, -1);
  final abstandBA = Int32List(nb)..fillRange(0, nb, 1 << 20);
  for (var i = 0; i < na; i++) {
    var d1 = 1 << 20, d2 = 1 << 20, j1 = -1;
    final oi = i * 8;
    for (var j = 0; j < nb; j++) {
      final oj = j * 8;
      var d = 0;
      for (var k = 0; k < 8; k++) {
        d += _bits(da[oi + k] ^ db[oj + k]);
      }
      if (d < d1) {
        d2 = d1;
        d1 = d;
        j1 = j;
      } else if (d < d2) {
        d2 = d;
      }
      if (d < abstandBA[j]) {
        abstandBA[j] = d;
        bestBA[j] = i;
      }
    }
    bestAB[i] = j1;
    abstandAB[i] = d1;
    zweitAB[i] = d2;
  }
  final paare = <(int, int)>[];
  for (var i = 0; i < na; i++) {
    final j = bestAB[i];
    if (j < 0 || abstandAB[i] > hoechstensAbstand) continue;
    if (abstandAB[i] >= verhaeltnis * zweitAB[i]) continue;
    if (bestBA[j] != i) continue;
    paare.add((i, j));
  }
  return paare;
}

/// Das Ergebnis von [ransacHomographie]: die Homographie (a → b) und die
/// Nummern der Paare, die zu ihr passen.
class Homographiebefund {
  const Homographiebefund(this.h, this.passend);

  final Float64List h;
  final List<int> passend;
}

/// Sucht mit RANSAC die Homographie, zu der die meisten Paare passen
/// (Abweichung unter [schwelle] Punkten), und rechnet sie aus allen
/// passenden nach. [von] und [nach] tragen x, y je Paar. `null`, wenn
/// keine Homographie mindestens [mindestens] Paare trägt.
///
/// Fester Startwert des Zufalls: Dasselbe Bildpaar ergibt in jedem Lauf
/// dieselbe Lage – sonst sähe ein zweites Zusammenfügen derselben Fotos
/// anders aus als das erste.
Homographiebefund? ransacHomographie(
  Float64List von,
  Float64List nach, {
  double schwelle = 3,
  int mindestens = 12,
  int hoechstensRunden = 1500,
}) {
  final n = von.length ~/ 2;
  if (n < math.max(4, mindestens)) return null;
  final zufall = math.Random(17 + n);
  final v4 = Float64List(8), n4 = Float64List(8);
  final s2 = schwelle * schwelle;
  // [bildeAb] ausgeschrieben: Es liefe je Runde für jedes Paar und legte
  // jedes Mal ein Ergebnis an – bis zu 1500 × 500 Stück je Bildpaar.
  List<int> passendZu(Float64List h) {
    final aus = <int>[];
    final h0 = h[0], h1 = h[1], h2 = h[2], h3 = h[3], h4 = h[4];
    final h5 = h[5], h6 = h[6], h7 = h[7], h8 = h[8];
    for (var i = 0; i < n; i++) {
      final x = von[i * 2], y = von[i * 2 + 1];
      final w = h6 * x + h7 * y + h8;
      if (w.abs() < 1e-12) continue;
      final dx = (h0 * x + h1 * y + h2) / w - nach[i * 2];
      final dy = (h3 * x + h4 * y + h5) / w - nach[i * 2 + 1];
      if (dx * dx + dy * dy < s2) aus.add(i);
    }
    return aus;
  }

  var beste = <int>[];
  var runden = hoechstensRunden;
  for (var r = 0; r < runden; r++) {
    final wahl = <int>{};
    while (wahl.length < 4) {
      wahl.add(zufall.nextInt(n));
    }
    var k = 0;
    for (final i in wahl) {
      v4[k * 2] = von[i * 2];
      v4[k * 2 + 1] = von[i * 2 + 1];
      n4[k * 2] = nach[i * 2];
      n4[k * 2 + 1] = nach[i * 2 + 1];
      k++;
    }
    final h = homographieAusVier(v4, n4);
    if (h == null || !_vernuenftig(h)) continue;
    final passend = passendZu(h);
    if (passend.length > beste.length) {
      beste = passend;
      // Wie viele Runden es braucht, um mit 99,5 % einmal vier passende
      // Paare zu ziehen, bei dem bisher besten Anteil.
      final anteil = passend.length / n;
      final p4 = math.pow(anteil, 4).toDouble();
      if (p4 >= 1) break;
      final noetig = (math.log(1 - 0.995) / math.log(1 - p4)).ceil();
      runden = math.min(hoechstensRunden, math.max(r + 1, noetig));
    }
  }
  if (beste.length < mindestens) return null;
  // Aus allen passenden nachrechnen, dann noch einmal zählen.
  var h = _ausPaaren(von, nach, beste);
  if (h == null) return null;
  var passend = passendZu(h);
  if (passend.length >= beste.length) {
    final h2 = _ausPaaren(von, nach, passend);
    if (h2 != null) {
      final p2 = passendZu(h2);
      if (p2.length >= passend.length) {
        h = h2;
        passend = p2;
      }
    }
  } else {
    passend = beste;
  }
  if (passend.length < mindestens || !_vernuenftig(h)) return null;
  return Homographiebefund(h, passend);
}

Float64List? _ausPaaren(Float64List von, Float64List nach, List<int> wahl) {
  final v = Float64List(wahl.length * 2), z = Float64List(wahl.length * 2);
  for (var k = 0; k < wahl.length; k++) {
    v[k * 2] = von[wahl[k] * 2];
    v[k * 2 + 1] = von[wahl[k] * 2 + 1];
    z[k * 2] = nach[wahl[k] * 2];
    z[k * 2 + 1] = nach[wahl[k] * 2 + 1];
  }
  return homographieAusPaaren(v, z);
}

/// Eine Homographie, wie sie zwischen zwei Aufnahmen eines Schwenks
/// vorkommen kann: nicht gespiegelt, nicht zu einem Strich gequetscht.
bool _vernuenftig(Float64List h) {
  final det = h[0] * h[4] - h[1] * h[3];
  if (!det.isFinite || det <= 0.1 || det > 10) return false;
  return h[6].abs() < 0.01 && h[7].abs() < 0.01;
}
