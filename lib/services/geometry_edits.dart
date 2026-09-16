/// Freies Drehen und Perspektivkorrektur – die Geometrie dahinter.
///
/// Als eigener Dienst und nicht im Bildschirm: Beides sind Rechnungen, die
/// man an Zahlen prüfen kann, und beides geht auf eine Weise schief, die
/// man dem fertigen Bild nur schwer ansieht – ein um ein halbes Grad
/// verkantetes Foto oder eine Entzerrung, die die Ecken vertauscht.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:image/image.dart' as img;

/// Das grösste achsenparallele Rechteck, das nach einer Drehung um
/// [winkelRad] noch vollständig im Bild liegt.
///
/// Ohne diesen Zuschnitt hätte ein geradegezogenes Foto leere Ecken. Sie
/// stehenzulassen wäre keine Alternative: Ein schiefer Horizont wird
/// geradegezogen, damit das Bild fertig aussieht, nicht damit es vier
/// weisse Dreiecke bekommt.
///
/// Die Formel ist die bekannte Lösung für das flächengrösste einbeschriebene
/// Rechteck. Der Sonderfall in der ersten Verzweigung betrifft stark
/// gedrehte, sehr längliche Bilder – dort begrenzt die kurze Seite, nicht
/// der Winkel.
({double breite, double hoehe}) groesstesRechteckNachDrehung(
    double w, double h, double winkelRad) {
  if (w <= 0 || h <= 0) return (breite: 0, hoehe: 0);

  final sin = math.sin(winkelRad).abs();
  final cos = math.cos(winkelRad).abs();

  final langeSeite = math.max(w, h);
  final kurzeSeite = math.min(w, h);

  if (kurzeSeite <= 2 * sin * cos * langeSeite || (sin - cos).abs() < 1e-10) {
    final x = 0.5 * kurzeSeite;
    return w >= h
        ? (breite: sin == 0 ? w : x / sin, hoehe: cos == 0 ? h : x / cos)
        : (breite: cos == 0 ? w : x / cos, hoehe: sin == 0 ? h : x / sin);
  }

  final cos2a = cos * cos - sin * sin;
  return (
    breite: (w * cos - h * sin) / cos2a,
    hoehe: (h * cos - w * sin) / cos2a,
  );
}

/// Dreht [quelle] um [winkelGrad] und schneidet die leeren Ecken weg.
img.Image geradeziehen(img.Image quelle, double winkelGrad) {
  if (winkelGrad == 0) return quelle;
  final gedreht = img.copyRotate(quelle, angle: winkelGrad);

  final rad = winkelGrad * math.pi / 180;
  final mass = groesstesRechteckNachDrehung(
      quelle.width.toDouble(), quelle.height.toDouble(), rad);
  final breite = mass.breite.floor().clamp(1, gedreht.width);
  final hoehe = mass.hoehe.floor().clamp(1, gedreht.height);

  return img.copyCrop(
    gedreht,
    x: ((gedreht.width - breite) / 2).round(),
    y: ((gedreht.height - hoehe) / 2).round(),
    width: breite,
    height: hoehe,
  );
}

/// Die Homographie, die [quelle] (vier Punkte) auf [ziel] (vier Punkte)
/// abbildet – neun Werte, zeilenweise.
///
/// Gelöst wird das übliche 8×8-System per Gauss-Elimination. Neun Werte bei
/// acht Unbekannten, weil eine Homographie nur bis auf einen Faktor
/// bestimmt ist; der letzte wird auf 1 gesetzt.
///
/// Gibt `null` zurück, wenn die vier Punkte entartet sind (drei auf einer
/// Linie, zwei gleich) – dann gibt es keine eindeutige Abbildung, und ein
/// gerechnetes Ergebnis wäre Zufall.
Float64List? homographie(List<Offset> quelle, List<Offset> ziel) {
  if (quelle.length != 4 || ziel.length != 4) return null;

  // Zeilen des Gleichungssystems: je zwei pro Punktpaar.
  final a = List.generate(8, (_) => List<double>.filled(9, 0));
  for (var i = 0; i < 4; i++) {
    final x = quelle[i].dx, y = quelle[i].dy;
    final u = ziel[i].dx, v = ziel[i].dy;
    a[i * 2] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u];
    a[i * 2 + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v];
  }

  // Gauss mit Spaltenpivotisierung.
  for (var spalte = 0; spalte < 8; spalte++) {
    var beste = spalte;
    for (var zeile = spalte + 1; zeile < 8; zeile++) {
      if (a[zeile][spalte].abs() > a[beste][spalte].abs()) beste = zeile;
    }
    if (a[beste][spalte].abs() < 1e-12) return null; // entartet
    final tausch = a[spalte];
    a[spalte] = a[beste];
    a[beste] = tausch;

    final pivot = a[spalte][spalte];
    for (var k = spalte; k < 9; k++) {
      a[spalte][k] /= pivot;
    }
    for (var zeile = 0; zeile < 8; zeile++) {
      if (zeile == spalte) continue;
      final faktor = a[zeile][spalte];
      if (faktor == 0) continue;
      for (var k = spalte; k < 9; k++) {
        a[zeile][k] -= faktor * a[spalte][k];
      }
    }
  }

  final h = Float64List(9);
  for (var i = 0; i < 8; i++) {
    h[i] = a[i][8];
  }
  h[8] = 1;
  return h;
}

/// Wendet [h] auf einen Punkt an.
Offset abbilden(Float64List h, double x, double y) {
  final w = h[6] * x + h[7] * y + h[8];
  if (w == 0) return Offset.zero;
  return Offset((h[0] * x + h[1] * y + h[2]) / w, (h[3] * x + h[4] * y + h[5]) / w);
}

/// Entzerrt das von [ecken] aufgespannte Viereck auf ein Rechteck von
/// [zielBreite] × [zielHoehe].
///
/// [ecken] sind vier Punkte in Bildkoordinaten, im Uhrzeigersinn ab oben
/// links. Gerechnet wird rückwärts – für jeden Zielpunkt wird die Stelle in
/// der Quelle gesucht und dort bilinear abgetastet. Vorwärts zu rechnen
/// liesse Löcher im Ergebnis, weil sich benachbarte Quellpunkte auf
/// dieselbe Zielstelle abbilden können.
///
/// Gibt `null` zurück, wenn die Ecken entartet sind.
img.Image? perspektivischEntzerren(
  img.Image quelle,
  List<Offset> ecken,
  int zielBreite,
  int zielHoehe,
) {
  if (zielBreite < 1 || zielHoehe < 1) return null;
  // Rückwärts: vom Ziel-Rechteck auf das Quell-Viereck.
  final h = homographie(
    [
      Offset.zero,
      Offset(zielBreite - 1, 0),
      Offset(zielBreite - 1, zielHoehe - 1),
      Offset(0, zielHoehe - 1),
    ],
    ecken,
  );
  if (h == null) return null;

  final ziel = img.Image(width: zielBreite, height: zielHoehe);
  final maxX = quelle.width - 1;
  final maxY = quelle.height - 1;

  for (var y = 0; y < zielHoehe; y++) {
    for (var x = 0; x < zielBreite; x++) {
      final p = abbilden(h, x.toDouble(), y.toDouble());
      if (p.dx < 0 || p.dy < 0 || p.dx > maxX || p.dy > maxY) continue;

      final x0 = p.dx.floor(), y0 = p.dy.floor();
      final x1 = math.min(x0 + 1, maxX), y1 = math.min(y0 + 1, maxY);
      final fx = p.dx - x0, fy = p.dy - y0;

      final a = quelle.getPixel(x0, y0);
      final b = quelle.getPixel(x1, y0);
      final c = quelle.getPixel(x0, y1);
      final d = quelle.getPixel(x1, y1);

      double misch(num pa, num pb, num pc, num pd) =>
          (pa * (1 - fx) + pb * fx) * (1 - fy) + (pc * (1 - fx) + pd * fx) * fy;

      ziel.setPixelRgb(
        x, y,
        misch(a.r, b.r, c.r, d.r).round(),
        misch(a.g, b.g, c.g, d.g).round(),
        misch(a.b, b.b, c.b, d.b).round(),
      );
    }
  }
  return ziel;
}
