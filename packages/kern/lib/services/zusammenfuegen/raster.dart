/// Bilder als Zahlenfelder für das Zusammenfügen (#498): Farbbilder mit
/// 8 Bit je Kanal, Ebenen mit Gleitkommawerten und die Pyramiden, auf
/// denen Belichtungsfusion und Ausrichtung arbeiten.
///
/// **Warum eigene Felder und nicht `img.Image`.** Die Pixel eines
/// `img.Image` laufen über Objekte je Bildpunkt (`getPixel`, `Color`); für
/// ein Foto mit 24 Millionen Punkten, das je Schritt ein Dutzend Mal
/// durchlaufen wird, ist das um ein Vielfaches zu langsam. Hier liegen die
/// Werte in `Uint8List`/`Float32List`, und jede Schleife greift direkt
/// darauf zu. Gemessen am Rechner (übersetzt, nicht im Testlauf): ein
/// Durchgang über 24 MP knapp 30 ms, das Dekodieren eines JPEG dieser
/// Grösse mit `package:image` 1,2 s.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'fehler.dart';

/// Ein Farbbild mit 8 Bit je Kanal, die Kanäle R, G, B verschachtelt.
///
/// Hält das `img.Image`, dessen Speicher [rgb] ist: So lässt es sich ohne
/// Kopie als JPEG schreiben. `Image.fromBytes` kopierte jedes Mal – bei
/// einem Panorama mit 50 MP wären das 150 MB nur für den Übergang.
class Farbbild {
  Farbbild._(this.bild) : rgb = bild.toUint8List();

  /// Ein schwarzes Bild in [breite] × [hoehe].
  factory Farbbild.leer(int breite, int hoehe) =>
      Farbbild._(img.Image(width: breite, height: hoehe));

  /// Übernimmt [bild], gewandelt auf 8 Bit und drei Kanäle, falls nötig.
  factory Farbbild.aus(img.Image bild) {
    final passend =
        bild.format == img.Format.uint8 &&
            bild.numChannels == 3 &&
            !bild.hasPalette
        ? bild
        : bild.convert(format: img.Format.uint8, numChannels: 3);
    return Farbbild._(passend);
  }

  final img.Image bild;
  final Uint8List rgb;

  int get breite => bild.width;
  int get hoehe => bild.height;
  int get pixel => breite * hoehe;

  /// Als JPEG in [qualitaet] (1–100).
  Uint8List alsJpeg({int qualitaet = 92}) =>
      img.encodeJpg(bild, quality: qualitaet.clamp(1, 100));
}

/// Liest ein JPEG oder PNG, dreht es nach seiner EXIF-Ausrichtung aufrecht
/// und verkleinert es auf höchstens [hoechstensPixel] Bildpunkte.
///
/// Wirft [Zusammenfuegefehler] mit [Fuegegrund.unlesbar], wenn die Bytes
/// kein lesbares Bild sind.
///
/// `bakeOrientation` nur bei einer echten Drehung: Es legt sonst trotzdem
/// eine Kopie an – bei 24 MP noch einmal 72 MB, die niemand braucht.
Farbbild dekodiereBild(Uint8List bytes, {int? hoechstensPixel, int? quelle}) {
  img.Image? roh;
  try {
    roh = img.decodeImage(bytes);
  } on Object {
    roh = null;
  }
  if (roh == null) {
    throw Zusammenfuegefehler(Fuegegrund.unlesbar, quelle: quelle);
  }
  var bild = roh;
  final ifd = bild.exif.imageIfd;
  if (ifd.hasOrientation && ifd.orientation != 1) {
    bild = img.bakeOrientation(bild);
  }
  final grenze = hoechstensPixel;
  if (grenze != null && bild.width * bild.height > grenze) {
    final f = math.sqrt(grenze / (bild.width * bild.height));
    bild = img.copyResize(
      bild,
      width: math.max(1, (bild.width * f).floor()),
      height: math.max(1, (bild.height * f).floor()),
      interpolation: img.Interpolation.average,
    );
  }
  return Farbbild.aus(bild);
}

/// Verkleinert [b] durch Mitteln über Flächen auf [breite] × [hoehe] – für
/// die Registrierung und für Quellen, die grösser sind als ihr Platz im
/// Ergebnis. Vergrössert nie: Ein Ziel über der Quelle bleibt die Quelle.
Farbbild verkleinere(Farbbild b, int breite, int hoehe) {
  if (breite >= b.breite && hoehe >= b.hoehe) return b;
  final aus = Farbbild.leer(breite, hoehe);
  final q = b.rgb;
  final z = aus.rgb;
  final sx = b.breite / breite;
  final sy = b.hoehe / hoehe;
  final summe = Float64List(breite * 3);
  for (var y = 0; y < hoehe; y++) {
    final y0 = (y * sy).floor();
    final y1 = math.max(y0 + 1, math.min(b.hoehe, ((y + 1) * sy).ceil()));
    summe.fillRange(0, summe.length, 0);
    for (var yy = y0; yy < y1; yy++) {
      final zeile = yy * b.breite * 3;
      for (var x = 0; x < breite; x++) {
        final x0 = (x * sx).floor();
        final x1 = math.max(x0 + 1, math.min(b.breite, ((x + 1) * sx).ceil()));
        var r = 0, g = 0, bl = 0;
        for (var xx = x0, i = zeile + x0 * 3; xx < x1; xx++, i += 3) {
          r += q[i];
          g += q[i + 1];
          bl += q[i + 2];
        }
        summe[x * 3] += r;
        summe[x * 3 + 1] += g;
        summe[x * 3 + 2] += bl;
      }
    }
    for (var x = 0; x < breite; x++) {
      final x0 = (x * sx).floor();
      final x1 = math.max(x0 + 1, math.min(b.breite, ((x + 1) * sx).ceil()));
      final n = (x1 - x0) * (y1 - y0);
      final o = (y * breite + x) * 3;
      z[o] = (summe[x * 3] / n).round();
      z[o + 1] = (summe[x * 3 + 1] / n).round();
      z[o + 2] = (summe[x * 3 + 2] / n).round();
    }
  }
  return aus;
}

/// Verkleinert [b] so, dass es höchstens [pixel] Bildpunkte hat.
Farbbild verkleinereAuf(Farbbild b, int pixel) {
  if (b.pixel <= pixel) return b;
  final f = math.sqrt(pixel / b.pixel);
  return verkleinere(
    b,
    math.max(1, (b.breite * f).round()),
    math.max(1, (b.hoehe * f).round()),
  );
}

/// Ein Kanal mit Gleitkommawerten, zeilenweise.
class Ebene {
  Ebene(this.breite, this.hoehe, [Float32List? werte])
    : werte = werte ?? Float32List(breite * hoehe);

  final int breite;
  final int hoehe;
  final Float32List werte;

  int get pixel => breite * hoehe;
}

/// Die Helligkeit von [b] in 0..1 (Gewichte nach Rec. 601, wie JPEG).
Ebene helligkeit(Farbbild b) {
  final e = Ebene(b.breite, b.hoehe);
  final q = b.rgb;
  final w = e.werte;
  for (var i = 0, j = 0; i < w.length; i++, j += 3) {
    w[i] = (0.299 * q[j] + 0.587 * q[j + 1] + 0.114 * q[j + 2]) / 255;
  }
  return e;
}

/// Ein Kanal (0 = R, 1 = G, 2 = B) von [b] in 0..1.
Ebene kanal(Farbbild b, int k) {
  final e = Ebene(b.breite, b.hoehe);
  final q = b.rgb;
  final w = e.werte;
  for (var i = 0, j = k; i < w.length; i++, j += 3) {
    w[i] = q[j] / 255;
  }
  return e;
}

/// Die halbe Fassung von [e] nach Burt und Adelson: geglättet mit dem
/// Kern 1-4-6-4-1, dann jeder zweite Punkt. Am Rand wird der letzte Punkt
/// wiederholt.
Ebene reduziere(Ebene e) {
  final w = e.breite;
  final h = e.hoehe;
  final w2 = (w + 1) >> 1;
  final h2 = (h + 1) >> 1;
  final q = e.werte;
  // Erst die Zeilen, dann die Spalten – getrennt ist der Kern 5 statt 25
  // Zugriffe je Punkt.
  final quer = Float32List(w2 * h);
  final wl = w - 1;
  for (var y = 0; y < h; y++) {
    final z = y * w;
    final o = y * w2;
    for (var x = 0; x < w2; x++) {
      final c = 2 * x;
      final a = c - 2 < 0 ? 0 : c - 2;
      final b = c - 1 < 0 ? 0 : c - 1;
      final d = c + 1 > wl ? wl : c + 1;
      final f = c + 2 > wl ? wl : c + 2;
      quer[o + x] =
          (q[z + a] + 4 * q[z + b] + 6 * q[z + c] + 4 * q[z + d] + q[z + f]) /
          16;
    }
  }
  final aus = Ebene(w2, h2);
  final z = aus.werte;
  final hl = h - 1;
  for (var y = 0; y < h2; y++) {
    final c = 2 * y;
    final a = (c - 2 < 0 ? 0 : c - 2) * w2;
    final b = (c - 1 < 0 ? 0 : c - 1) * w2;
    final m = c * w2;
    final d = (c + 1 > hl ? hl : c + 1) * w2;
    final f = (c + 2 > hl ? hl : c + 2) * w2;
    final o = y * w2;
    for (var x = 0; x < w2; x++) {
      z[o + x] =
          (quer[a + x] +
              4 * quer[b + x] +
              6 * quer[m + x] +
              4 * quer[d + x] +
              quer[f + x]) /
          16;
    }
  }
  return aus;
}

/// Die Umkehrung von [reduziere] auf [breite] × [hoehe]: Nullen
/// dazwischen, mit dem doppelten Kern geglättet. Ausgeschrieben heisst das
/// für eine gerade Stelle (g[k-1] + 6 g[k] + g[k+1]) / 8 und für eine
/// ungerade (g[k] + g[k+1]) / 2.
Ebene erweitere(Ebene e, int breite, int hoehe) {
  final gw = e.breite;
  final gh = e.hoehe;
  final q = e.werte;
  final gwl = gw - 1;
  final quer = Float32List(breite * gh);
  for (var y = 0; y < gh; y++) {
    final z = y * gw;
    final o = y * breite;
    for (var x = 0; x < breite; x++) {
      final k = x >> 1;
      final km = k > gwl ? gwl : k;
      if (x.isEven) {
        final a = km - 1 < 0 ? 0 : km - 1;
        final b = km + 1 > gwl ? gwl : km + 1;
        quer[o + x] = (q[z + a] + 6 * q[z + km] + q[z + b]) / 8;
      } else {
        final b = km + 1 > gwl ? gwl : km + 1;
        quer[o + x] = (q[z + km] + q[z + b]) / 2;
      }
    }
  }
  final aus = Ebene(breite, hoehe);
  final z = aus.werte;
  final ghl = gh - 1;
  for (var y = 0; y < hoehe; y++) {
    final k = y >> 1;
    final km = k > ghl ? ghl : k;
    final o = y * breite;
    if (y.isEven) {
      final a = (km - 1 < 0 ? 0 : km - 1) * breite;
      final m = km * breite;
      final b = (km + 1 > ghl ? ghl : km + 1) * breite;
      for (var x = 0; x < breite; x++) {
        z[o + x] = (quer[a + x] + 6 * quer[m + x] + quer[b + x]) / 8;
      }
    } else {
      final m = km * breite;
      final b = (km + 1 > ghl ? ghl : km + 1) * breite;
      for (var x = 0; x < breite; x++) {
        z[o + x] = (quer[m + x] + quer[b + x]) / 2;
      }
    }
  }
  return aus;
}

/// Rechnet [faktor] · [erweitere]([grob]) auf [fein] auf – ohne die
/// erweiterte Stufe ganz anzulegen. Bei 24 MP spart das je Aufruf 96 MB:
/// Es bleibt nur die waagerecht erweiterte Hälfte stehen.
void erweitereDazu(Ebene grob, Ebene fein, double faktor) {
  final gw = grob.breite;
  final gh = grob.hoehe;
  final breite = fein.breite;
  final q = grob.werte;
  final gwl = gw - 1;
  final quer = Float32List(breite * gh);
  for (var y = 0; y < gh; y++) {
    final z = y * gw;
    final o = y * breite;
    for (var x = 0; x < breite; x++) {
      final k = x >> 1;
      final km = k > gwl ? gwl : k;
      final b = km + 1 > gwl ? gwl : km + 1;
      if (x.isEven) {
        final a = km - 1 < 0 ? 0 : km - 1;
        quer[o + x] = (q[z + a] + 6 * q[z + km] + q[z + b]) / 8;
      } else {
        quer[o + x] = (q[z + km] + q[z + b]) / 2;
      }
    }
  }
  final f = fein.werte;
  final ghl = gh - 1;
  for (var y = 0; y < fein.hoehe; y++) {
    final k = y >> 1;
    final km = k > ghl ? ghl : k;
    final o = y * breite;
    final m = km * breite;
    final b = (km + 1 > ghl ? ghl : km + 1) * breite;
    if (y.isEven) {
      final a = (km - 1 < 0 ? 0 : km - 1) * breite;
      final g = faktor / 8;
      for (var x = 0; x < breite; x++) {
        f[o + x] += g * (quer[a + x] + 6 * quer[m + x] + quer[b + x]);
      }
    } else {
      final g = faktor / 2;
      for (var x = 0; x < breite; x++) {
        f[o + x] += g * (quer[m + x] + quer[b + x]);
      }
    }
  }
}

/// Wie viele Stufen eine Pyramide über [breite] × [hoehe] bekommt: so
/// viele, bis die kürzere Seite unter acht Punkte fiele. Erst die gröbsten
/// Stufen gleichen grosse Flächen gegeneinander aus – mit zu wenigen
/// bekäme der Himmel einer Belichtungsreihe Flecken.
int pyramidenstufen(int breite, int hoehe) {
  var kurz = math.min(breite, hoehe);
  var n = 1;
  while (kurz >= 16) {
    kurz = (kurz + 1) >> 1;
    n++;
  }
  return n;
}

/// Die Gausspyramide von [e] mit [stufen] Stufen; die erste ist [e] selbst.
List<Ebene> gausspyramide(Ebene e, int stufen) {
  final p = <Ebene>[e];
  while (p.length < stufen) {
    p.add(reduziere(p.last));
  }
  return p;
}

/// Macht aus einer Gausspyramide an Ort und Stelle die Laplacepyramide:
/// jede Stufe weniger der erweiterten nächsten; die gröbste bleibt.
void zuLaplace(List<Ebene> p) {
  for (var l = 0; l < p.length - 1; l++) {
    erweitereDazu(p[l + 1], p[l], -1);
  }
}

/// Setzt eine Laplacepyramide wieder zu einem Bild zusammen – an Ort und
/// Stelle, das Ergebnis ist die erste Stufe.
Ebene falteZusammen(List<Ebene> p) {
  for (var l = p.length - 2; l >= 0; l--) {
    erweitereDazu(p[l + 1], p[l], 1);
    // Die gröbere Stufe ist aufgegangen; ihr Speicher kann gehen.
    p.removeLast();
  }
  return p.first;
}

/// Ein Grauwertbild mit 8 Bit, für die Ausrichtung nach Ward.
class Graubild {
  Graubild(this.breite, this.hoehe, [Uint8List? werte])
    : werte = werte ?? Uint8List(breite * hoehe);

  /// Die Helligkeit von [b] (Gewichte wie [helligkeit]).
  factory Graubild.aus(Farbbild b) {
    final g = Graubild(b.breite, b.hoehe);
    final q = b.rgb;
    final w = g.werte;
    for (var i = 0, j = 0; i < w.length; i++, j += 3) {
      w[i] = (77 * q[j] + 150 * q[j + 1] + 29 * q[j + 2]) >> 8;
    }
    return g;
  }

  final int breite;
  final int hoehe;
  final Uint8List werte;

  /// Die halbe Fassung, je vier Punkte gemittelt.
  Graubild halb() {
    final w2 = math.max(1, breite >> 1);
    final h2 = math.max(1, hoehe >> 1);
    final aus = Graubild(w2, h2);
    final q = werte;
    final z = aus.werte;
    final bl = breite - 1;
    final hl = hoehe - 1;
    for (var y = 0; y < h2; y++) {
      final a = math.min(2 * y, hl) * breite;
      final b = math.min(2 * y + 1, hl) * breite;
      for (var x = 0; x < w2; x++) {
        final x0 = math.min(2 * x, bl);
        final x1 = math.min(2 * x + 1, bl);
        z[y * w2 + x] =
            (q[a + x0] + q[a + x1] + q[b + x0] + q[b + x1] + 2) >> 2;
      }
    }
    return aus;
  }
}

/// Ein Farbwert aus [b] an der Stelle ([x], [y]) mit bilinearer
/// Interpolation, in [ziel] ab [o] geschrieben. Erwartet 0 ≤ x ≤ breite-1
/// und 0 ≤ y ≤ hoehe-1.
void tasteAb(Farbbild b, double x, double y, Float64List ziel, int o) {
  final w = b.breite;
  final x0 = x.floor();
  final y0 = y.floor();
  final x1 = x0 + 1 < w ? x0 + 1 : x0;
  final y1 = y0 + 1 < b.hoehe ? y0 + 1 : y0;
  final fx = x - x0;
  final fy = y - y0;
  final q = b.rgb;
  final i00 = (y0 * w + x0) * 3;
  final i10 = (y0 * w + x1) * 3;
  final i01 = (y1 * w + x0) * 3;
  final i11 = (y1 * w + x1) * 3;
  final w00 = (1 - fx) * (1 - fy);
  final w10 = fx * (1 - fy);
  final w01 = (1 - fx) * fy;
  final w11 = fx * fy;
  for (var k = 0; k < 3; k++) {
    ziel[o + k] =
        q[i00 + k] * w00 +
        q[i10 + k] * w10 +
        q[i01 + k] * w01 +
        q[i11 + k] * w11;
  }
}
