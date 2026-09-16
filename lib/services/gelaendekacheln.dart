/// Geländehöhen aus Kacheln – die Grundlage der 3D-Landschaft.
///
/// **Ohne neue Abhängigkeit.** Kacheln im `terrarium`-Format sind frei,
/// brauchen keinen Schlüssel und liegen unter derselben XYZ-Adresse wie
/// Kartenkacheln. Die Höhe steckt in den Farbwerten:
///
/// ```
/// Meter = r · 256 + g + b/256 − 32768
/// ```
///
/// **Nachgemessen und nicht abgeschrieben:** Kachel 11/1080/689
/// (Vogelsberg, 50,6° N / 9,8° O) ergibt 336,6 bis 814,0 m. Der
/// Taufstein dort ist 773 m hoch, die Talsohlen liegen um 340 – die
/// Zahlen passen.
///
/// Reine Rechnung, ohne Flutter und ohne Netz: Der Abruf wird
/// hereingereicht, damit sich jede Umrechnung ohne Server prüfen lässt.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Woher die Höhen kommen.
///
/// Von AWS Open Data, ohne Schlüssel und ohne Anmeldung. Steht hier als
/// Konstante, damit ein Wechsel der Quelle eine Zeile ist.
const String gelaendeKachelUrl =
    'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png';

/// Höchste Stufe, für die es Geländekacheln gibt.
///
/// Darüber liefert die Quelle nichts mehr; ein Gitter mit feineren
/// Angaben als 15 wäre erfunden.
const int gelaendeHoechsteStufe = 15;

/// Kantenlänge einer Kachel in Bildpunkten.
const int kachelKante = 256;

/// Meter über dem Meer aus einem Bildpunkt.
double hoeheAusFarbe(int r, int g, int b) => r * 256 + g + b / 256 - 32768;

/// Die Kachelspalte zu einer Länge.
int kachelX(double laenge, int zoom) {
  final n = 1 << zoom;
  return ((laenge + 180) / 360 * n).floor().clamp(0, n - 1);
}

/// Die Kachelzeile zu einer Breite (Web-Mercator).
int kachelY(double breite, int zoom) {
  final n = 1 << zoom;
  final rad = breite * math.pi / 180;
  final y = (1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) / 2 * n;
  return y.floor().clamp(0, n - 1);
}

/// Die Kachelspalte zu einer Länge – **mit Nachkommastellen**.
///
/// Dasselbe wie [kachelX], nur ungerundet: Der Nachkommaanteil ist die
/// Stelle innerhalb der Kachel, von 0 am Westrand bis 1 am Ostrand. Genau
/// das braucht eine Textur, die auf einem Block sitzt.
double kachelXGenau(double laenge, int zoom) =>
    (laenge + 180) / 360 * (1 << zoom);

/// Die Kachelzeile zu einer Breite – **mit Nachkommastellen**.
///
/// Das Gegenstück zu [kachelXGenau], und der einzige Weg, eine Breite
/// mercatorgerecht auf eine Textur zu legen: Die Kacheln sind in
/// Mercator gleich hoch, in Grad nicht. Über einen Block von 380 Metern
/// ist der Unterschied winzig – über einen Ausschnitt von vier
/// Kilometern ist er es nicht mehr.
double kachelYGenau(double breite, int zoom) {
  final rad = breite * math.pi / 180;
  return (1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) /
      2 *
      (1 << zoom);
}

/// Die westliche Kante einer Kachelspalte, in Grad.
double kachelWesten(int x, int zoom) => x / (1 << zoom) * 360 - 180;

/// Die nördliche Kante einer Kachelzeile, in Grad.
double kachelNorden(int y, int zoom) {
  final n = 1 << zoom;
  final t = math.pi * (1 - 2 * y / n);
  return 180 / math.pi * math.atan(0.5 * (math.exp(t) - math.exp(-t)));
}

/// Welche Kacheln ein Ausschnitt braucht – und auf welcher Stufe.
///
/// Gewählt wird die **feinste** Stufe, die mit [hoechstensKacheln]
/// auskommt. Eine feste Stufe wäre bei einer Zwölf-Kilometer-Wanderung
/// entweder grob wie ein Bundesland oder eine Flut von Kacheln.
({int zoom, int x0, int y0, int x1, int y1}) kachelbereich({
  required double sued,
  required double west,
  required double nord,
  required double ost,
  int hoechstensKacheln = 16,
  int hoechsteStufe = gelaendeHoechsteStufe,
}) {
  for (var z = hoechsteStufe; z >= 0; z--) {
    final x0 = kachelX(west, z);
    final x1 = kachelX(ost, z);
    // Nord und Süd sind bei den Kachelzeilen vertauscht: Zeile 0 liegt
    // oben.
    final y0 = kachelY(nord, z);
    final y1 = kachelY(sued, z);
    if ((x1 - x0 + 1) * (y1 - y0 + 1) <= hoechstensKacheln) {
      return (zoom: z, x0: x0, y0: y0, x1: x1, y1: y1);
    }
  }
  return (zoom: 0, x0: 0, y0: 0, x1: 0, y1: 0);
}

/// Ein Höhengitter über einem rechteckigen Ausschnitt.
///
/// Die Werte liegen zeilenweise von **Nord nach Süd** und von West nach
/// Ost – so, wie die Kacheln aufgebaut sind. Wer sie anders herum
/// erwartet, dreht die Landschaft um.
class Hoehengitter {
  final int spalten;
  final int zeilen;

  /// Meter über dem Meer. `nan` steht für „nicht bekannt" – eine
  /// fehlende Kachel wird nicht mit Meereshöhe gefüllt, das gäbe ein
  /// Loch, das wie ein See aussähe.
  final Float32List hoehen;

  final double nord;
  final double sued;
  final double west;
  final double ost;

  Hoehengitter({
    required this.spalten,
    required this.zeilen,
    required this.hoehen,
    required this.nord,
    required this.sued,
    required this.west,
    required this.ost,
  });

  double bei(int spalte, int zeile) => hoehen[zeile * spalten + spalte];

  /// Die Höhe an einer Koordinate, bilinear zwischen den Gitterpunkten.
  ///
  /// Bilinear und nicht der nächste Punkt: Eine Spur, die über das
  /// Gelände gelegt wird, sprünge sonst an jeder Gitterlinie.
  double? anOrt(double breite, double laenge) {
    if (breite > nord || breite < sued || laenge < west || laenge > ost) {
      return null;
    }
    final fx = (laenge - west) / (ost - west) * (spalten - 1);
    final fy = (nord - breite) / (nord - sued) * (zeilen - 1);
    final x0 = fx.floor().clamp(0, spalten - 1);
    final y0 = fy.floor().clamp(0, zeilen - 1);
    final x1 = (x0 + 1).clamp(0, spalten - 1);
    final y1 = (y0 + 1).clamp(0, zeilen - 1);
    final tx = fx - x0;
    final ty = fy - y0;
    final a = bei(x0, y0);
    final b = bei(x1, y0);
    final c = bei(x0, y1);
    final d = bei(x1, y1);
    if (a.isNaN || b.isNaN || c.isNaN || d.isNaN) return null;
    return a * (1 - tx) * (1 - ty) +
        b * tx * (1 - ty) +
        c * (1 - tx) * ty +
        d * tx * ty;
  }

  /// Tiefster und höchster bekannter Punkt.
  ({double tief, double hoch}) get spanne {
    var tief = double.infinity;
    var hoch = double.negativeInfinity;
    for (final h in hoehen) {
      if (h.isNaN) continue;
      if (h < tief) tief = h;
      if (h > hoch) hoch = h;
    }
    if (tief > hoch) return (tief: 0, hoch: 0);
    return (tief: tief, hoch: hoch);
  }

  /// Verkleinert das Gitter auf höchstens [kante] Punkte je Seite.
  ///
  /// **Der Grund, warum es diese Funktion gibt:** Ein Gitter von
  /// 256 × 256 sind rund 130.000 Dreiecke je Kachel. Vier Kacheln wären
  /// eine halbe Million – so viel zeichnet keine Bildrate. Genommen wird
  /// jeder n-te Punkt und nicht der Mittelwert: Ein Mittel über acht
  /// Bildpunkte trägt jeden Gipfel ab.
  Hoehengitter verkleinert(int kante) {
    if (spalten <= kante && zeilen <= kante) return this;
    final neueSpalten = math.min(spalten, kante);
    final neueZeilen = math.min(zeilen, kante);
    final neu = Float32List(neueSpalten * neueZeilen);
    // **Der letzte Punkt muss der letzte bleiben.** Naheliegend wäre,
    // jeden n-ten zu nehmen; dann fiele der Ostrand weg, während [ost]
    // weiter die volle Breite behauptet – die Landschaft wäre gedehnt.
    // Deshalb wird die Stelle anteilig gerechnet, so dass 0 auf 0 und
    // der letzte auf den letzten fällt.
    int stelle(int i, int neu, int alt) =>
        neu <= 1 ? 0 : (i * (alt - 1) / (neu - 1)).round().clamp(0, alt - 1);
    for (var y = 0; y < neueZeilen; y++) {
      final ay = stelle(y, neueZeilen, zeilen);
      for (var x = 0; x < neueSpalten; x++) {
        neu[y * neueSpalten + x] = bei(stelle(x, neueSpalten, spalten), ay);
      }
    }
    return Hoehengitter(
      spalten: neueSpalten,
      zeilen: neueZeilen,
      hoehen: neu,
      nord: nord,
      sued: sued,
      west: west,
      ost: ost,
    );
  }
}

/// Eine geladene Kachel: ihre Bildpunkte als RGBA.
typedef Kachelbild = ({int x, int y, Uint8List rgba});

/// Setzt die Kacheln zu einem Gitter zusammen.
///
/// Fehlende Kacheln bleiben als `nan` stehen – siehe [Hoehengitter.hoehen].
Hoehengitter gitterAusKacheln({
  required int zoom,
  required int x0,
  required int y0,
  required int x1,
  required int y1,
  required Iterable<Kachelbild> kacheln,
  int kante = kachelKante,
}) {
  final breiteKacheln = x1 - x0 + 1;
  final hoeheKacheln = y1 - y0 + 1;
  final spalten = breiteKacheln * kante;
  final zeilen = hoeheKacheln * kante;
  final hoehen = Float32List(spalten * zeilen)
    ..fillRange(0, spalten * zeilen, double.nan);

  for (final k in kacheln) {
    final sx = (k.x - x0) * kante;
    final sy = (k.y - y0) * kante;
    if (sx < 0 || sy < 0 || sx >= spalten || sy >= zeilen) continue;
    for (var y = 0; y < kante; y++) {
      for (var x = 0; x < kante; x++) {
        final i = (y * kante + x) * 4;
        if (i + 2 >= k.rgba.length) continue;
        hoehen[(sy + y) * spalten + sx + x] =
            hoeheAusFarbe(k.rgba[i], k.rgba[i + 1], k.rgba[i + 2]);
      }
    }
  }

  return Hoehengitter(
    spalten: spalten,
    zeilen: zeilen,
    hoehen: hoehen,
    nord: kachelNorden(y0, zoom),
    sued: kachelNorden(y1 + 1, zoom),
    west: kachelWesten(x0, zoom),
    ost: kachelWesten(x1 + 1, zoom),
  );
}

/// Die Adressen der Kacheln eines Bereichs.
List<({int z, int x, int y})> kacheladressen(
        ({int zoom, int x0, int y0, int x1, int y1}) bereich) =>
    [
      for (var y = bereich.y0; y <= bereich.y1; y++)
        for (var x = bereich.x0; x <= bereich.x1; x++)
          (z: bereich.zoom, x: x, y: y),
    ];

/// Setzt die Adresse in die Vorlage ein.
String kacheladresse(int z, int x, int y,
        {String vorlage = gelaendeKachelUrl}) =>
    vorlage
        .replaceAll('{z}', '$z')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$y');
