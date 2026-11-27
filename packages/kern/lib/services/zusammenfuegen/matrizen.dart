/// Kleine lineare Algebra für das Zusammenfügen (#498): 3×3-Matrizen,
/// symmetrische Eigenzerlegung, lineare Gleichungssysteme, die beste
/// Drehung zwischen zwei Punktmengen und Homographien.
///
/// Alles als flache `Float64List` (zeilenweise), weil es nur um Matrizen
/// bis 9×9 geht und eine Bibliothek dafür mehr Gewicht brächte als
/// Nutzen.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Die Einheitsmatrix 3×3.
Float64List einheit3() => Float64List.fromList([1, 0, 0, 0, 1, 0, 0, 0, 1]);

/// [a] · [b] für 3×3.
Float64List mal3(Float64List a, Float64List b) {
  final c = Float64List(9);
  for (var i = 0; i < 3; i++) {
    for (var j = 0; j < 3; j++) {
      c[i * 3 + j] =
          a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j];
    }
  }
  return c;
}

/// Die Transponierte von [a] (3×3) – bei einer Drehung ihre Umkehrung.
Float64List transponiert3(Float64List a) => Float64List.fromList([
  a[0],
  a[3],
  a[6],
  a[1],
  a[4],
  a[7],
  a[2],
  a[5],
  a[8],
]);

/// [a] · ([x], [y], [z]).
(double, double, double) wende3(Float64List a, double x, double y, double z) =>
    (
      a[0] * x + a[1] * y + a[2] * z,
      a[3] * x + a[4] * y + a[5] * z,
      a[6] * x + a[7] * y + a[8] * z,
    );

/// Die Umkehrung einer 3×3-Matrix, `null` wenn sie singulär ist.
Float64List? invers3(Float64List m) {
  final a = m[0], b = m[1], c = m[2];
  final d = m[3], e = m[4], f = m[5];
  final g = m[6], h = m[7], i = m[8];
  final co0 = e * i - f * h;
  final co1 = f * g - d * i;
  final co2 = d * h - e * g;
  final det = a * co0 + b * co1 + c * co2;
  if (det.abs() < 1e-300 || !det.isFinite) return null;
  final r = 1 / det;
  return Float64List.fromList([
    co0 * r,
    (c * h - b * i) * r,
    (b * f - c * e) * r,
    co1 * r,
    (a * i - c * g) * r,
    (c * d - a * f) * r,
    co2 * r,
    (b * g - a * h) * r,
    (a * e - b * d) * r,
  ]);
}

/// Die Drehung um die senkrechte Achse (y) um [winkel] im Bogenmass –
/// für Tests und als Hilfe beim Aufrichten.
Float64List drehungUmY(double winkel) {
  final c = math.cos(winkel), s = math.sin(winkel);
  return Float64List.fromList([c, 0, s, 0, 1, 0, -s, 0, c]);
}

/// Eigenwerte und -vektoren einer symmetrischen [n]×[n]-Matrix nach Jacobi.
/// Die Vektoren stehen als Spalten in `vektoren` (zeilenweise abgelegt):
/// Komponente k des i-ten Vektors ist `vektoren[k * n + i]`.
({Float64List werte, Float64List vektoren}) eigenSymmetrisch(
  Float64List m,
  int n,
) {
  final a = Float64List.fromList(m);
  final v = Float64List(n * n);
  for (var i = 0; i < n; i++) {
    v[i * n + i] = 1;
  }
  for (var runde = 0; runde < 64; runde++) {
    var neben = 0.0;
    var gesamt = 0.0;
    for (var p = 0; p < n; p++) {
      for (var q = 0; q < n; q++) {
        final x = a[p * n + q] * a[p * n + q];
        gesamt += x;
        if (p != q) neben += x;
      }
    }
    if (neben <= 1e-30 * (gesamt + 1e-300)) break;
    for (var p = 0; p < n - 1; p++) {
      for (var q = p + 1; q < n; q++) {
        final apq = a[p * n + q];
        if (apq.abs() < 1e-300) continue;
        final theta = (a[q * n + q] - a[p * n + p]) / (2 * apq);
        final t =
            (theta >= 0 ? 1.0 : -1.0) /
            (theta.abs() + math.sqrt(theta * theta + 1));
        final c = 1 / math.sqrt(t * t + 1);
        final s = t * c;
        for (var k = 0; k < n; k++) {
          final akp = a[k * n + p], akq = a[k * n + q];
          a[k * n + p] = c * akp - s * akq;
          a[k * n + q] = s * akp + c * akq;
        }
        for (var k = 0; k < n; k++) {
          final apk = a[p * n + k], aqk = a[q * n + k];
          a[p * n + k] = c * apk - s * aqk;
          a[q * n + k] = s * apk + c * aqk;
        }
        for (var k = 0; k < n; k++) {
          final vkp = v[k * n + p], vkq = v[k * n + q];
          v[k * n + p] = c * vkp - s * vkq;
          v[k * n + q] = s * vkp + c * vkq;
        }
      }
    }
  }
  final werte = Float64List(n);
  for (var i = 0; i < n; i++) {
    werte[i] = a[i * n + i];
  }
  return (werte: werte, vektoren: v);
}

/// Der Eigenvektor zum kleinsten (bzw. mit [groesster] zum grössten)
/// Eigenwert von [m].
Float64List eigenvektor(Float64List m, int n, {bool groesster = false}) {
  final e = eigenSymmetrisch(m, n);
  var beste = 0;
  for (var i = 1; i < n; i++) {
    if (groesster ? e.werte[i] > e.werte[beste] : e.werte[i] < e.werte[beste]) {
      beste = i;
    }
  }
  return Float64List.fromList([
    for (var k = 0; k < n; k++) e.vektoren[k * n + beste],
  ]);
}

/// Löst [a] · x = [b] ([n]×[n], zeilenweise) nach Gauss mit
/// Spaltenpivotsuche; `null`, wenn das System singulär ist. Verändert
/// weder [a] noch [b].
Float64List? loese(Float64List a, Float64List b, int n) {
  final m = Float64List.fromList(a);
  final r = Float64List.fromList(b);
  for (var k = 0; k < n; k++) {
    var p = k;
    var gross = m[k * n + k].abs();
    for (var i = k + 1; i < n; i++) {
      final x = m[i * n + k].abs();
      if (x > gross) {
        gross = x;
        p = i;
      }
    }
    if (gross < 1e-12) return null;
    if (p != k) {
      for (var j = 0; j < n; j++) {
        final t = m[k * n + j];
        m[k * n + j] = m[p * n + j];
        m[p * n + j] = t;
      }
      final t = r[k];
      r[k] = r[p];
      r[p] = t;
    }
    final d = m[k * n + k];
    for (var i = k + 1; i < n; i++) {
      final f = m[i * n + k] / d;
      if (f == 0) continue;
      for (var j = k; j < n; j++) {
        m[i * n + j] -= f * m[k * n + j];
      }
      r[i] -= f * r[k];
    }
  }
  final x = Float64List(n);
  for (var i = n - 1; i >= 0; i--) {
    var s = r[i];
    for (var j = i + 1; j < n; j++) {
      s -= m[i * n + j] * x[j];
    }
    x[i] = s / m[i * n + i];
  }
  for (final w in x) {
    if (!w.isFinite) return null;
  }
  return x;
}

/// Die Drehung R, die die Richtungen [von] möglichst genau auf [nach]
/// abbildet (nach ≈ R · von), nach Horn (1987) über die Quaternion zum
/// grössten Eigenwert. Beide Listen tragen je drei Werte je Richtung;
/// [gewichte] wiegt jede Richtung.
///
/// Geschlossen und ohne Startwert: Es gibt kein Konvergenzproblem, und
/// schon drei Paare bestimmen die Drehung.
Float64List besteDrehung(
  Float64List von,
  Float64List nach, {
  Float64List? gewichte,
}) {
  var sxx = 0.0, sxy = 0.0, sxz = 0.0;
  var syx = 0.0, syy = 0.0, syz = 0.0;
  var szx = 0.0, szy = 0.0, szz = 0.0;
  final n = von.length ~/ 3;
  for (var i = 0; i < n; i++) {
    final w = gewichte == null ? 1.0 : gewichte[i];
    final ax = von[i * 3] * w, ay = von[i * 3 + 1] * w, az = von[i * 3 + 2] * w;
    final bx = nach[i * 3], by = nach[i * 3 + 1], bz = nach[i * 3 + 2];
    sxx += ax * bx;
    sxy += ax * by;
    sxz += ax * bz;
    syx += ay * bx;
    syy += ay * by;
    syz += ay * bz;
    szx += az * bx;
    szy += az * by;
    szz += az * bz;
  }
  final nm = Float64List.fromList([
    sxx + syy + szz, syz - szy, szx - sxz, sxy - syx, //
    syz - szy, sxx - syy - szz, sxy + syx, szx + sxz,
    szx - sxz, sxy + syx, -sxx + syy - szz, syz + szy,
    sxy - syx, szx + sxz, syz + szy, -sxx - syy + szz,
  ]);
  final q = eigenvektor(nm, 4, groesster: true);
  final laenge = math.sqrt(
    q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3],
  );
  final q0 = q[0] / laenge, qx = q[1] / laenge;
  final qy = q[2] / laenge, qz = q[3] / laenge;
  return Float64List.fromList([
    1 - 2 * (qy * qy + qz * qz),
    2 * (qx * qy - q0 * qz),
    2 * (qx * qz + q0 * qy),
    2 * (qx * qy + q0 * qz),
    1 - 2 * (qx * qx + qz * qz),
    2 * (qy * qz - q0 * qx),
    2 * (qx * qz - q0 * qy),
    2 * (qy * qz + q0 * qx),
    1 - 2 * (qx * qx + qy * qy),
  ]);
}

/// Die Homographie aus genau vier Punktpaaren ([von] → [nach], je x, y)
/// mit h33 = 1 – der schnelle Fall für RANSAC. `null`, wenn die Punkte
/// entartet liegen.
Float64List? homographieAusVier(Float64List von, Float64List nach) {
  final a = Float64List(64);
  final b = Float64List(8);
  for (var i = 0; i < 4; i++) {
    final x = von[i * 2], y = von[i * 2 + 1];
    final u = nach[i * 2], v = nach[i * 2 + 1];
    final r1 = (2 * i) * 8;
    a[r1] = x;
    a[r1 + 1] = y;
    a[r1 + 2] = 1;
    a[r1 + 6] = -u * x;
    a[r1 + 7] = -u * y;
    b[2 * i] = u;
    final r2 = (2 * i + 1) * 8;
    a[r2 + 3] = x;
    a[r2 + 4] = y;
    a[r2 + 5] = 1;
    a[r2 + 6] = -v * x;
    a[r2 + 7] = -v * y;
    b[2 * i + 1] = v;
  }
  final h = loese(a, b, 8);
  if (h == null) return null;
  return Float64List.fromList([...h, 1]);
}

/// Die Homographie aus beliebig vielen Punktpaaren nach der normierten
/// DLT (Hartley): Schwerpunkt in den Ursprung, mittlerer Abstand √2, dann
/// der Eigenvektor zum kleinsten Eigenwert von AᵀA.
Float64List? homographieAusPaaren(Float64List von, Float64List nach) {
  final n = von.length ~/ 2;
  if (n < 4) return null;
  (double, double, double) norm(Float64List p) {
    var mx = 0.0, my = 0.0;
    for (var i = 0; i < n; i++) {
      mx += p[i * 2];
      my += p[i * 2 + 1];
    }
    mx /= n;
    my /= n;
    var d = 0.0;
    for (var i = 0; i < n; i++) {
      final dx = p[i * 2] - mx, dy = p[i * 2 + 1] - my;
      d += math.sqrt(dx * dx + dy * dy);
    }
    d /= n;
    return (mx, my, d > 1e-12 ? math.sqrt2 / d : 1.0);
  }

  final (ax, ay, sa) = norm(von);
  final (bx, by, sb) = norm(nach);
  final ata = Float64List(81);
  final zeile = Float64List(9);
  void addiere() {
    for (var i = 0; i < 9; i++) {
      final zi = zeile[i];
      if (zi == 0) continue;
      for (var j = 0; j < 9; j++) {
        ata[i * 9 + j] += zi * zeile[j];
      }
    }
  }

  for (var i = 0; i < n; i++) {
    final x = (von[i * 2] - ax) * sa, y = (von[i * 2 + 1] - ay) * sa;
    final u = (nach[i * 2] - bx) * sb, v = (nach[i * 2 + 1] - by) * sb;
    zeile
      ..fillRange(0, 9, 0)
      ..[0] = x
      ..[1] = y
      ..[2] = 1
      ..[6] = -u * x
      ..[7] = -u * y
      ..[8] = -u;
    addiere();
    zeile
      ..fillRange(0, 9, 0)
      ..[3] = x
      ..[4] = y
      ..[5] = 1
      ..[6] = -v * x
      ..[7] = -v * y
      ..[8] = -v;
    addiere();
  }
  final h = eigenvektor(ata, 9);
  // Entnormieren: H = Tb⁻¹ · Hn · Ta.
  final ta = Float64List.fromList([sa, 0, -sa * ax, 0, sa, -sa * ay, 0, 0, 1]);
  final tbInv = Float64List.fromList([1 / sb, 0, bx, 0, 1 / sb, by, 0, 0, 1]);
  final ergebnis = mal3(mal3(tbInv, h), ta);
  final s = ergebnis[8];
  if (s.abs() < 1e-300) return null;
  for (var i = 0; i < 9; i++) {
    ergebnis[i] /= s;
  }
  return ergebnis;
}

/// Wohin [h] den Punkt ([x], [y]) bringt; `null` hinter dem Horizont.
(double, double)? bildeAb(Float64List h, double x, double y) {
  final w = h[6] * x + h[7] * y + h[8];
  if (w.abs() < 1e-12) return null;
  return ((h[0] * x + h[1] * y + h[2]) / w, (h[3] * x + h[4] * y + h[5]) / w);
}
