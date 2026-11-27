/// Das Ausrichten einer Belichtungsreihe aus der Hand (#498): grob nach
/// Ward (2003) mit Schwellenbildern über eine Pyramide, dazu auf Wunsch
/// eine kleine Drehung, dann fein nach Gauss-Newton auf Bruchteile eines
/// Punkts.
///
/// **Warum Schwellenbilder und keine Merkmale.** Zwei Aufnahmen einer
/// Reihe unterscheiden sich um zwei, drei Blendenstufen: Was im einen Bild
/// Zeichnung hat, ist im anderen schwarz oder ausgefressen, und jede
/// Kante hat eine andere Helligkeit. Schneidet man aber jedes Bild an
/// einer *eigenen* Schwelle, kommt bei allen nahezu dasselbe Muster heraus,
/// mit den Grenzen an denselben Stellen. Punkte nahe an der Schwelle
/// wackeln mit dem Rauschen und zählen nicht mit (Ausschlussbild). Ward
/// nimmt als Schwelle den Median des ganzen Bilds; hier ist es das Mittel
/// der Umgebung (siehe [_Bitbild]).
///
/// **Gemessen** an künstlichen Reihen (±2 Blenden, verschoben und bis
/// 1,2° gedreht, 480 × 360 bis 6000 × 4000): Verschiebung auf 0,05 Punkte,
/// Drehung auf 0,01° genau. Bei 24 MP dauert das Ausrichten eines Bilds
/// gut eine halbe Sekunde.
///
/// **Grenzen.** Gesucht wird eine Verschiebung bis ±127 Punkte (bei
/// 24 MP gut 2 % der Breite) und eine Drehung bis ±2°. Eine Reihe, die
/// stärker verwackelt ist, oder ein Schwenk zwischen den Aufnahmen wird
/// nicht erkannt. Es gibt nur die starre Bewegung: Was sich in der Szene
/// selbst bewegt (Äste, Menschen, Wolken), bleibt verschieden und kann im
/// Ergebnis doppelt erscheinen.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'matrizen.dart';
import 'raster.dart';

/// Wie ein Foto auf dem Bezugsbild liegt: Ein Punkt p des Fotos gehört zum
/// Punkt R(winkel) · (p − m) + m + (dx, dy) des Bezugsbilds, m ist die
/// Bildmitte. [winkel] im Bogenmass.
class Lage {
  const Lage(this.dx, this.dy, [this.winkel = 0]);

  static const ruhe = Lage(0, 0);

  final double dx;
  final double dy;
  final double winkel;

  @override
  String toString() =>
      'Lage(${dx.toStringAsFixed(2)}, ${dy.toStringAsFixed(2)}, '
      '${(winkel * 180 / math.pi).toStringAsFixed(3)}°)';
}

/// Ein Schwellenbild einer Stufe: Bit 0 heisst „heller als die Umgebung",
/// Bit 1 „zählt mit" – deutlich weg vom Mittel der Umgebung und weder
/// abgesoffen noch ausgefressen.
///
/// **Die Umgebung statt des Medians.** Ward schneidet jedes Bild an seinem
/// Median. Das trägt, solange beide Bilder in der Mitte ihrer Helligkeiten
/// Zeichnung haben. Ist aber in der hellsten Aufnahme mehr als die Hälfte
/// ausgefressen, liegt ihr Median bei 255, das Schwellenbild ist überall
/// gleich, und jede Lage passt – im Versuch kamen 27 Punkte Fehler heraus.
/// Auch ein gemeinsamer anderer Anteil half nicht: Bei einem Himmel, der
/// von links nach rechts heller wird, bleibt dann nur eine einzige Grenze
/// übrig, und die sagt über eine Drehung fast nichts. Verglichen mit dem
/// Mittel der Umgebung (9 × 9 Punkte auf jeder Stufe) bleibt jede Kante
/// erhalten, wo sie Zeichnung hat – die Belichtung ändert die Reihenfolge
/// benachbarter Helligkeiten nicht. Was abgeschnitten ist, zählt nicht.
class _Bitbild {
  _Bitbild(this.breite, this.hoehe, this.code);

  factory _Bitbild.aus(Graubild g, {int radius = 4, int toleranz = 3}) {
    final w = g.breite, h = g.hoehe;
    final q = g.werte;
    // Summenbild für das Mittel der Umgebung.
    final summe = Int32List((w + 1) * (h + 1));
    for (var y = 0; y < h; y++) {
      var zeile = 0;
      for (var x = 0; x < w; x++) {
        zeile += q[y * w + x];
        summe[(y + 1) * (w + 1) + x + 1] = summe[y * (w + 1) + x + 1] + zeile;
      }
    }
    final code = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      final y0 = y - radius < 0 ? 0 : y - radius;
      final y1 = y + radius + 1 > h ? h : y + radius + 1;
      for (var x = 0; x < w; x++) {
        final x0 = x - radius < 0 ? 0 : x - radius;
        final x1 = x + radius + 1 > w ? w : x + radius + 1;
        final s =
            summe[y1 * (w + 1) + x1] -
            summe[y0 * (w + 1) + x1] -
            summe[y1 * (w + 1) + x0] +
            summe[y0 * (w + 1) + x0];
        final n = (x1 - x0) * (y1 - y0);
        final v = q[y * w + x];
        final d = v * n - s;
        final zaehlt = v > 4 && v < 251 && d.abs() > toleranz * n;
        code[y * w + x] = (d > 0 ? 1 : 0) | (zaehlt ? 2 : 0);
      }
    }
    return _Bitbild(w, h, code);
  }

  final int breite;
  final int hoehe;
  final Uint8List code;
}

/// Der Anteil abweichender Punkte, wenn [b] mit der Lage (sx, sy, winkel)
/// auf [a] gelegt wird – gezählt nur, wo beide Punkte mitzählen, geteilt
/// durch die Zahl der überdeckten Punkte.
double _fehler(_Bitbild a, _Bitbild b, int sx, int sy, double winkel) {
  final w = a.breite;
  final h = a.hoehe;
  final ca = a.code;
  final cb = b.code;
  var fehler = 0;
  var deckung = 0;
  if (winkel == 0) {
    final x0 = math.max(0, sx), x1 = math.min(w, w + sx);
    final y0 = math.max(0, sy), y1 = math.min(h, h + sy);
    if (x1 <= x0 || y1 <= y0) return 1;
    for (var y = y0; y < y1; y++) {
      var i = y * w + x0;
      var j = (y - sy) * w + x0 - sx;
      for (var x = x0; x < x1; x++, i++, j++) {
        final p = ca[i], q = cb[j];
        // Beide zählen mit (Bit 1) und liegen auf verschiedenen Seiten
        // ihrer Schwelle (Bit 0).
        if ((p & q & 2) != 0 && ((p ^ q) & 1) != 0) fehler++;
      }
    }
    deckung = (x1 - x0) * (y1 - y0);
    return fehler / deckung;
  }
  // Mit Drehung: für jeden Punkt des Bezugs die Stelle im Foto, nächster
  // Nachbar. Je Zeile fortgeschrieben, ohne Winkelfunktionen in der
  // Schleife.
  final c = math.cos(winkel), s = math.sin(winkel);
  final mx = (w - 1) / 2, my = (h - 1) / 2;
  for (var y = 0; y < h; y++) {
    final ry = y - my - sy;
    final rx0 = -mx - sx;
    var xb = c * rx0 + s * ry + mx + 0.5;
    var yb = -s * rx0 + c * ry + my + 0.5;
    var i = y * w;
    for (var x = 0; x < w; x++, i++, xb += c, yb -= s) {
      if (xb < 0 || yb < 0) continue;
      final xi = xb.toInt(), yi = yb.toInt();
      if (xi >= w || yi >= h) continue;
      deckung++;
      final p = ca[i], q = cb[yi * w + xi];
      if ((p & q & 2) != 0 && ((p ^ q) & 1) != 0) fehler++;
    }
  }
  return deckung == 0 ? 1 : fehler / deckung;
}

/// Richtet [bild] an [bezug] aus (beide gleich gross) und gibt seine
/// [Lage]. Mit [drehung] wird auch eine Drehung bis ±2° gesucht.
///
/// **Zwei Schritte.** Die Schwellenbilder finden die Lage grob und ohne
/// Startwert, aber nur auf ganze Punkte und – wegen des nächsten Nachbarn
/// beim Drehen – mit einem Winkel, der im Versuch an 24 MP um 0,1° daneben
/// lag; an der Bildecke sind das fünf Punkte. Danach wird auf einer
/// mittleren Stufe (höchstens 1600 Punkte an der langen Seite) und, wo es
/// sie gibt, auf einer feineren (höchstens 3200) nach Gauss-Newton
/// nachgeschoben, auf Bildern, die je Punkt um das Mittel ihrer Umgebung
/// bereinigt und durch deren Streuung geteilt sind ([_normiert]). Das
/// macht die verschiedene Belichtung fast wirkungslos und liefert Bruchteile
/// eines Punkts.
///
/// Für mehrere Fotos gegen denselben Bezug [richteAusAn] mit einem
/// [Ausrichtbezug]: Dessen Stufen rechnet es nur einmal.
Lage richteAus(Graubild bezug, Graubild bild, {bool drehung = true}) =>
    glaetteLage(richteAusAn(Ausrichtbezug(bezug), bild, drehung: drehung).lage);

/// Das Bezugsbild einer Ausrichtung mit allem, was daran für jedes Foto
/// gleich ist: seine Stufen, ihre Schwellenbilder und die normierten
/// Fassungen für das Nachschieben.
///
/// Bisher rechnete [richteAus] all das je Foto neu – bei einer Reihe aus
/// neun Aufnahmen achtmal dieselbe Pyramide. Schwellenbilder und normierte
/// Fassungen entstehen hier erst, wenn eine Stufe sie braucht, und bleiben
/// dann.
class Ausrichtbezug {
  Ausrichtbezug(Graubild bezug) : stufen = _stufen(bezug);

  final List<Graubild> stufen;
  final _bits = <int, _Bitbild>{};
  final _norm = <int, Float32List>{};

  int get breite => stufen.first.breite;
  int get hoehe => stufen.first.hoehe;

  _Bitbild _bitbild(int l) => _bits[l] ??= _Bitbild.aus(stufen[l]);
  Float32List _normiertAuf(int l) => _norm[l] ??= _normiert(stufen[l]);

  int _lang(int l) => math.max(stufen[l].breite, stufen[l].hoehe);

  /// Die Stufe, auf der die Drehung grob gesucht wird: die feinste mit
  /// höchstens 512 Punkten an der langen Seite. Gröber verfälscht eine
  /// Drehung schon die Verschiebung, die von oben kommt (im Versuch um zwei
  /// Punkte); darum dort ein Fenster von ±2 statt ±1.
  int get _drehstufe {
    var l = 0;
    while (l < stufen.length - 1 && _lang(l) > 512) {
      l++;
    }
    return l;
  }

  /// Bis zu dieser Stufe (höchstens 1600 Punkte) laufen die
  /// Schwellenbilder; dort und eine Stufe feiner übernimmt [_verfeinere].
  int get _mittelstufe {
    var l = 0;
    while (l < stufen.length - 1 && _lang(l) > 1600) {
      l++;
    }
    return l;
  }
}

/// Stufen, bis die kürzere Seite unter 32 fiele, höchstens acht: Auf der
/// gröbsten Stufe ist ±1 dann bis zu 2^7 = 128 Punkte im Original (bei
/// 24 MP gut 2 % der Breite), bei kleinen Bildern entsprechend weniger.
List<Graubild> _stufen(Graubild g) {
  final p = <Graubild>[g];
  while (p.length < 8 && math.min(p.last.breite, p.last.hoehe) >= 64) {
    p.add(p.last.halb());
  }
  return p;
}

/// Ab dieser [richteAusAn]-Güte gilt eine Aufnahme einer Belichtungsreihe
/// als ausgerichtet. Gemessen an künstlichen Reihen bis ±3 Blenden, auch
/// verschoben und gedreht: ausgerichtet 0,93 bis 0,97; fremde Bilder und
/// solche, die weiter verschoben sind, als die Suche reicht, unter 0,03.
/// Echte Aufnahmen liegen wegen Rauschen und Bewegung in der Szene
/// niedriger – daher die Schwelle weit unten.
const ausrichtgueteMindestens = 0.2;

/// Wie [richteAus] gegen einen schon vorbereiteten [bezug], dazu die Güte
/// der gefundenen Lage: die Korrelation der normierten Bilder ([_normiert])
/// auf der mittleren Stufe, nur wo beide weder abgesoffen noch
/// ausgefressen sind. Nahe eins heisst deckungsgleich, nahe null, dass
/// nichts zueinander passt (siehe [ausrichtgueteMindestens]).
///
/// [gueteRuhe] ist dieselbe Güte für [Lage.ruhe]: Liegt das Foto schon
/// deckungsgleich (vom Stativ), ist eine Suche, die etwas anderes findet,
/// ein Fehlgriff.
///
/// Die Lage ist noch nicht geglättet ([glaetteLage]): Wer sie auf eine
/// andere Grösse umrechnet, glättet erst danach.
({Lage lage, double guete, double gueteRuhe}) richteAusAn(
  Ausrichtbezug bezug,
  Graubild bild, {
  bool drehung = true,
}) {
  if (bezug.breite != bild.breite || bezug.hoehe != bild.hoehe) {
    throw ArgumentError('Ungleiche Grösse');
  }
  final gb = _stufen(bild);
  final n = bezug.stufen.length;
  final drehstufe = bezug._drehstufe;
  final mittelstufe = bezug._mittelstufe;
  var sx = 0, sy = 0;
  var winkel = 0.0;
  const grad = math.pi / 180;
  for (var l = n - 1; l >= mittelstufe; l--) {
    if (l < n - 1) {
      sx *= 2;
      sy *= 2;
    }
    final a = bezug._bitbild(l);
    final b = _Bitbild.aus(gb[l]);
    // Die beste Verschiebung im Fenster ±[r] um die bisherige.
    (int, int, double) besteVerschiebung(double w, [int r = 1]) {
      var bx = sx, by = sy;
      var bf = double.infinity;
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          final f = _fehler(a, b, sx + dx, sy + dy, w);
          if (f < bf - 1e-12) {
            bf = f;
            bx = sx + dx;
            by = sy + dy;
          }
        }
      }
      return (bx, by, bf);
    }

    if (drehung && l == drehstufe) {
      final ohne = besteVerschiebung(0, 2);
      var best = ohne;
      var bestWinkel = 0.0;
      // Grob: −2° … 2° in Schritten von 0,25°, dann ±0,25° in 0,05°.
      for (final (bereich, weite) in const [(2.0, 0.25), (0.25, 0.05)]) {
        final mitte = bestWinkel;
        final schritte = (bereich / weite).round();
        for (var k = -schritte; k <= schritte; k++) {
          if (k == 0) continue;
          final w = mitte + k * weite * grad;
          final r = besteVerschiebung(w, 2);
          if (r.$3 < best.$3 - 1e-12) {
            best = r;
            bestWinkel = w;
          }
        }
      }
      winkel = bestWinkel;
      sx = best.$1;
      sy = best.$2;
      continue;
    }
    final r = besteVerschiebung(winkel);
    sx = r.$1;
    sy = r.$2;
  }
  // Nachschieben: auf der mittleren Stufe, dann eine feiner.
  var lage = Lage(sx.toDouble(), sy.toDouble(), winkel);
  for (var l = mittelstufe; l >= math.max(0, mittelstufe - 1); l--) {
    if (l < mittelstufe) {
      lage = Lage(lage.dx * 2, lage.dy * 2, lage.winkel);
    }
    lage = _verfeinere(
      bezug.stufen[l],
      bezug._normiertAuf(l),
      gb[l],
      lage,
      drehung: drehung,
      runden: l == mittelstufe ? 12 : 4,
    );
  }
  // Was noch an Stufen fehlt, ist nur noch Massstab.
  final faktor = 1 << math.max(0, mittelstufe - 1);
  lage = Lage(lage.dx * faktor, lage.dy * faktor, lage.winkel);
  final nb = _normiert(gb[mittelstufe]);
  return (
    lage: lage,
    guete: _guete(bezug, gb[mittelstufe], nb, lage, mittelstufe),
    gueteRuhe: _guete(bezug, gb[mittelstufe], nb, Lage.ruhe, mittelstufe),
  );
}

/// Eine Drehung unter 0,01° (bei 24 MP ein halber Punkt an der Ecke)
/// lohnt das Umrechnen nicht, eine Verschiebung bis 0,05 Punkte auch
/// nicht: Es kostete nur Schärfe und einen Rand. Darum wird [lage] dann auf
/// ganze Punkte ohne Drehung gelegt.
Lage glaetteLage(Lage lage) {
  if (lage.winkel.abs() >= 0.01 * math.pi / 180) return lage;
  double glatt(double v) {
    final r = v.roundToDouble();
    return (v - r).abs() < 0.05 ? r : v;
  }

  return Lage(glatt(lage.dx), glatt(lage.dy));
}

/// Die Güte von [lage] (in Punkten der Stufe 0) auf der Stufe [l], deren
/// Foto [b] mit seiner normierten Fassung [nb] ist: die Korrelation der
/// normierten Bilder, gezählt nur, wo beide Punkte mitzählen (weder ≤ 4
/// noch ≥ 251) und das Foto den Bezug deckt.
double _guete(
  Ausrichtbezug bezug,
  Graubild b,
  Float32List nb,
  Lage lage,
  int l,
) {
  final a = bezug.stufen[l];
  final w = a.breite, h = a.hoehe;
  if (w < 8 || h < 8) return 0;
  final na = bezug._normiertAuf(l);
  final qa = a.werte, qb = b.werte;
  final teil = 1 << l;
  final tx = lage.dx / teil, ty = lage.dy / teil;
  final c = math.cos(lage.winkel), s = math.sin(lage.winkel);
  final mx = (w - 1) / 2, my = (h - 1) / 2;
  final abstand = w * h > 1200000 ? 2 : 1;
  var sab = 0.0, saa = 0.0, sbb = 0.0;
  for (var y = 0; y < h; y += abstand) {
    final uy = y - my - ty;
    for (var x = 0; x < w; x += abstand) {
      final ia = y * w + x;
      final va = qa[ia];
      if (va <= 4 || va >= 251) continue;
      final ux = x - mx - tx;
      final xb = c * ux + s * uy + mx;
      final yb = -s * ux + c * uy + my;
      if (xb < 0 || yb < 0 || xb > w - 2 || yb > h - 2) continue;
      final x0 = xb.toInt(), y0 = yb.toInt();
      final i = y0 * w + x0;
      final vb = qb[i];
      if (vb <= 4 || vb >= 251) continue;
      final fx = xb - x0, fy = yb - y0;
      final wb =
          nb[i] * (1 - fx) * (1 - fy) +
          nb[i + 1] * fx * (1 - fy) +
          nb[i + w] * (1 - fx) * fy +
          nb[i + w + 1] * fx * fy;
      final wa = na[ia];
      sab += wa * wb;
      saa += wa * wa;
      sbb += wb * wb;
    }
  }
  if (saa <= 0 || sbb <= 0) return 0;
  return sab / math.sqrt(saa * sbb);
}

/// Ein Grauwertbild, je Punkt um das Mittel seiner Umgebung (9 × 9)
/// bereinigt und durch deren Streuung (+2 Stufen) geteilt. Eine andere
/// Belichtung verschiebt und streckt die Helligkeiten örtlich – beides
/// fällt hier heraus.
Float32List _normiert(Graubild g, {int radius = 4}) {
  final w = g.breite, h = g.hoehe;
  final q = g.werte;
  final s1 = Float64List((w + 1) * (h + 1));
  final s2 = Float64List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var z1 = 0.0, z2 = 0.0;
    for (var x = 0; x < w; x++) {
      final v = q[y * w + x].toDouble();
      z1 += v;
      z2 += v * v;
      final o = (y + 1) * (w + 1) + x + 1;
      s1[o] = s1[o - w - 1] + z1;
      s2[o] = s2[o - w - 1] + z2;
    }
  }
  final aus = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    final y0 = y - radius < 0 ? 0 : y - radius;
    final y1 = y + radius + 1 > h ? h : y + radius + 1;
    for (var x = 0; x < w; x++) {
      final x0 = x - radius < 0 ? 0 : x - radius;
      final x1 = x + radius + 1 > w ? w : x + radius + 1;
      final a = y1 * (w + 1) + x1, b = y0 * (w + 1) + x1;
      final c = y1 * (w + 1) + x0, d = y0 * (w + 1) + x0;
      final n = (x1 - x0) * (y1 - y0);
      final m = (s1[a] - s1[b] - s1[c] + s1[d]) / n;
      final v2 = (s2[a] - s2[b] - s2[c] + s2[d]) / n - m * m;
      aus[y * w + x] = (q[y * w + x] - m) / (math.sqrt(math.max(0, v2)) + 2);
    }
  }
  return aus;
}

/// Schiebt [start] nach Gauss-Newton nach, bis [bild] auf [bezug] am
/// besten deckt (kleinste Quadrate auf [_normiert], abgeschnittene Punkte
/// zählen nicht, grosse Abweichungen nur gedämpft). [na] ist
/// `_normiert(bezug)`, vom [Ausrichtbezug] einmal gerechnet.
Lage _verfeinere(
  Graubild bezug,
  Float32List na,
  Graubild bild,
  Lage start, {
  required bool drehung,
  int runden = 8,
}) {
  final w = bezug.breite, h = bezug.hoehe;
  if (w < 8 || h < 8) return start;
  final nb = _normiert(bild);
  final qa = bezug.werte, qb = bild.werte;
  final mx = (w - 1) / 2, my = (h - 1) / 2;
  var tx = start.dx, ty = start.dy, th = start.winkel;
  final p = drehung ? 3 : 2;
  final hm = Float64List(p * p);
  final gv = Float64List(p);
  final j = Float64List(3);
  // Bei vielen Punkten reicht jeder zweite in jeder Richtung.
  final abstand = w * h > 1200000 ? 2 : 1;
  for (var runde = 0; runde < runden; runde++) {
    hm.fillRange(0, hm.length, 0);
    gv.fillRange(0, gv.length, 0);
    final c = math.cos(th), s = math.sin(th);
    for (var y = 1; y < h - 1; y += abstand) {
      final uy = y - my - ty;
      for (var x = 1; x < w - 1; x += abstand) {
        final ia = y * w + x;
        final va = qa[ia];
        if (va <= 4 || va >= 251) continue;
        final ux = x - mx - tx;
        final xb = c * ux + s * uy + mx;
        final yb = -s * ux + c * uy + my;
        if (xb < 1 || yb < 1 || xb >= w - 2 || yb >= h - 2) continue;
        final x0 = xb.toInt(), y0 = yb.toInt();
        final fx = xb - x0, fy = yb - y0;
        final i = y0 * w + x0;
        final vb = qb[i];
        if (vb <= 4 || vb >= 251) continue;
        double wert(int k) =>
            nb[k] * (1 - fx) * (1 - fy) +
            nb[k + 1] * fx * (1 - fy) +
            nb[k + w] * (1 - fx) * fy +
            nb[k + w + 1] * fx * fy;
        final v = wert(i);
        // Steigung im Foto aus den Nachbarn (zentrale Differenzen).
        final gx = (wert(i + 1) - wert(i - 1)) / 2;
        final gy = (wert(i + w) - wert(i - w)) / 2;
        final r = v - na[ia];
        final g = r.abs() < 1.5 ? 1.0 : 1.5 / r.abs();
        // x_b = R(−θ)(x − m − t) + m: Ableitungen nach t und θ.
        j[0] = gx * -c + gy * s;
        j[1] = gx * -s + gy * -c;
        if (drehung) {
          j[2] = gx * (-s * ux + c * uy) + gy * (-c * ux - s * uy);
        }
        for (var a = 0; a < p; a++) {
          gv[a] += g * j[a] * r;
          for (var b = 0; b < p; b++) {
            hm[a * p + b] += g * j[a] * j[b];
          }
        }
      }
    }
    final schritt = loese(
      hm,
      Float64List.fromList([for (final v in gv) -v]),
      p,
    );
    if (schritt == null) break;
    tx += schritt[0];
    ty += schritt[1];
    if (drehung) th += schritt[2];
    // Nicht weiter als die Suche reicht: Ein Sprung über zwei Grad ist
    // kein Nachschieben mehr, sondern ein Fehlgriff.
    if (th.abs() > 2.5 * math.pi / 180 ||
        (tx - start.dx).abs() > 8 ||
        (ty - start.dy).abs() > 8) {
      return start;
    }
    final klein =
        schritt[0].abs() < 0.01 &&
        schritt[1].abs() < 0.01 &&
        (!drehung || schritt[2].abs() < 1e-5);
    if (klein) break;
  }
  return Lage(tx, ty, th);
}

/// Legt [b] mit [lage] in den Ausschnitt ([x0], [y0], [breite] × [hoehe])
/// des Bezugsbilds. Ganze Verschiebungen ohne Drehung kopieren nur, alles
/// andere wird bilinear umgerechnet. Punkte ausserhalb von [b] bleiben
/// schwarz – der Aufrufer wählt den Ausschnitt so, dass es keine gibt.
Farbbild lege(Farbbild b, Lage lage, int x0, int y0, int breite, int hoehe) {
  final aus = Farbbild.leer(breite, hoehe);
  final z = aus.rgb;
  final q = b.rgb;
  final w = b.breite, h = b.hoehe;
  final ganz =
      lage.winkel == 0 &&
      lage.dx == lage.dx.roundToDouble() &&
      lage.dy == lage.dy.roundToDouble();
  if (ganz) {
    final dx = lage.dx.toInt(), dy = lage.dy.toInt();
    for (var y = 0; y < hoehe; y++) {
      final yb = y + y0 - dy;
      if (yb < 0 || yb >= h) continue;
      for (var x = 0; x < breite; x++) {
        final xb = x + x0 - dx;
        if (xb < 0 || xb >= w) continue;
        final i = (yb * w + xb) * 3, o = (y * breite + x) * 3;
        z[o] = q[i];
        z[o + 1] = q[i + 1];
        z[o + 2] = q[i + 2];
      }
    }
    return aus;
  }
  final c = math.cos(lage.winkel), s = math.sin(lage.winkel);
  final mx = (w - 1) / 2, my = (h - 1) / 2;
  final wert = Float64List(3);
  for (var y = 0; y < hoehe; y++) {
    final ry = y + y0 - my - lage.dy;
    for (var x = 0; x < breite; x++) {
      final rx = x + x0 - mx - lage.dx;
      final xb = c * rx + s * ry + mx;
      final yb = -s * rx + c * ry + my;
      if (xb < 0 || yb < 0 || xb > w - 1 || yb > h - 1) continue;
      tasteAb(b, xb, yb, wert, 0);
      final o = (y * breite + x) * 3;
      z[o] = (wert[0] + 0.5).toInt();
      z[o + 1] = (wert[1] + 0.5).toInt();
      z[o + 2] = (wert[2] + 0.5).toInt();
    }
  }
  return aus;
}

/// Der Ausschnitt des Bezugsbilds ([breite] × [hoehe]), den alle Fotos
/// mit ihren [lagen] ganz bedecken: links, oben, Breite, Höhe. Vorsichtig
/// gerechnet – eine Drehung kostet an jeder Seite, was die Ecken
/// hineinwandern.
(int, int, int, int) gemeinsamerAusschnitt(
  List<Lage> lagen,
  int breite,
  int hoehe,
) {
  var links = 0.0, oben = 0.0;
  var rechts = breite.toDouble(), unten = hoehe.toDouble();
  for (final l in lagen) {
    final s = math.sin(l.winkel).abs();
    final c = math.cos(l.winkel);
    final rx = hoehe / 2 * s + breite / 2 * (1 - c);
    final ry = breite / 2 * s + hoehe / 2 * (1 - c);
    links = math.max(links, l.dx + rx);
    rechts = math.min(rechts, breite + l.dx - rx);
    oben = math.max(oben, l.dy + ry);
    unten = math.min(unten, hoehe + l.dy - ry);
  }
  final x0 = links.ceil(), y0 = oben.ceil();
  final x1 = rechts.floor(), y1 = unten.floor();
  return (x0, y0, math.max(1, x1 - x0), math.max(1, y1 - y0));
}
