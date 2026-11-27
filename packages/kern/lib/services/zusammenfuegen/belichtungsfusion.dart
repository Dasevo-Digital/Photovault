/// HDR aus einer Belichtungsreihe (#498): Belichtungsfusion nach Mertens,
/// Kautz und Van Reeth (2007), vorher das Ausrichten nach Ward.
///
/// **Was das Verfahren tut.** Es baut kein Bild mit hohem Dynamikumfang,
/// das danach wieder auf 8 Bit gepresst werden müsste (Tonemapping),
/// sondern nimmt aus jeder Aufnahme die Stellen, an denen sie gut ist:
/// Jeder Punkt jeder Aufnahme bekommt ein Gewicht aus Kontrast (Betrag des
/// Laplacefilters), Sättigung (Streuung von R, G, B) und guter Belichtung
/// (Nähe zu 0,5, Gaussglocke mit σ = 0,2 je Kanal). Verschmolzen wird über
/// Laplacepyramiden – Gewichte und Bilder je Frequenzband –, sonst
/// entstünden an jeder Gewichtskante Säume. Belichtungszeit oder
/// Kamerakurve braucht es dafür nicht, und es kommt mit JPEGs aus.
///
/// **Grösse und Speicher.** Das Ergebnis hat höchstens [hdrHoechstensPixel]
/// Bildpunkte (24 MP); grössere Quellen werden vorher verkleinert. Die
/// Quellen werden zweimal gelesen (einmal für das Ausrichten, wofür eine
/// kleine Fassung genügt, einmal zum Verschmelzen) und nie alle zugleich
/// gehalten. Bleibend im Speicher sind
/// die Summen der Pyramiden: Helligkeit in voller Auflösung, die beiden
/// Farbdifferenzen in halber (wie in jedem JPEG mit 4:2:0 – sichtbar wird
/// davon nichts, und es spart ein Drittel), dazu die Summe der Gewichte.
/// Zusammen mit den Pyramiden der gerade verarbeiteten Aufnahme sind das
/// knapp 30 Byte je Bildpunkt, bei 24 MP also um 0,7 GB.
///
/// **Grenze: Geisterbilder.** Bewegt sich etwas zwischen den Aufnahmen,
/// nimmt die Fusion es dort, wo es gut belichtet ist, und das kann in
/// zwei Aufnahmen verschieden sein – ein Ast erscheint halb durchsichtig
/// doppelt. Eine Erkennung solcher Stellen gibt es nicht.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'ausrichtung.dart';
import 'fehler.dart';
import 'raster.dart';

/// So viele Aufnahmen nimmt eine Belichtungsreihe.
const hdrMindestens = 2;
const hdrHoechstens = 9;

/// So gross wird das Ergebnis höchstens – siehe die Beschreibung oben.
const hdrHoechstensPixel = 24 * 1000 * 1000;

/// Was beim Verschmelzen gewählt werden kann.
class HdrOptionen {
  const HdrOptionen({
    this.ausrichten = true,
    this.drehung = true,
    this.hoechstensPixel = hdrHoechstensPixel,
  });

  /// Aus der Hand aufgenommen: vorher verschieben (und mit [drehung]
  /// drehen), bis die Aufnahmen übereinander liegen.
  final bool ausrichten;
  final bool drehung;
  final int hoechstensPixel;
}

/// Das verschmolzene Bild, dazu die Lage jeder Quelle auf dem Bezugsbild,
/// welche Quelle das war (die mittlere Helligkeit) und welchen Ausschnitt
/// des Bezugsbilds das Ergebnis zeigt (links, oben, Breite, Höhe – in der
/// Grösse, auf die die Quellen gebracht wurden).
class HdrErgebnis {
  const HdrErgebnis(this.bild, this.lagen, this.bezug, this.ausschnitt);

  final Farbbild bild;
  final List<Lage> lagen;
  final int bezug;
  final (int, int, int, int) ausschnitt;
}

/// So lang ist die lange Seite der Grauwerte, auf denen ausgerichtet wird,
/// höchstens. [richteAus] schiebt ohnehin nur bis zu einer Stufe mit
/// höchstens 3200 Punkten nach und rechnet den Rest als Massstab hoch;
/// was darüber liegt, kostete nur Speicher und Zeit.
const _ausrichtenHoechstensKante = 3200;

/// Darunter (kürzere Seite) lassen sich die Aufnahmen nicht verlässlich
/// ausrichten: Die Pyramide hätte nur eine Stufe, und die Güte sagte
/// nichts.
const _ausrichtenMindestensKante = 48;

/// Bis zu dieser mittleren Sättigung (Streuung von R, G, B, 0..1) gilt eine
/// Aufnahme als farblos – gut zwei Stufen, so viel trägt das Rauschen eines
/// Schwarzweiss-JPEG. Gemessen an Farbaufnahmen: um 0,05 bis 0,15.
const _farblosBis = 0.01;

/// Verschmilzt [anzahl] Aufnahmen, die [lade] der Reihe nach liefert.
///
/// [lade] wird je Quelle zweimal gerufen und darf jedes Mal neu dekodieren
/// – so liegt nie mehr als eine Quelle im Speicher. [fortschritt] meldet
/// erledigte Schritte von 3 × [anzahl].
///
/// **Der erste Durchgang braucht nur eine kleine Fassung.** Er bestimmt
/// Helligkeit, Bezug und Lage jeder Aufnahme, und ausgerichtet wird auf
/// höchstens 3200 Punkten an der langen Seite. Liefert [ladeKlein] eine
/// verkleinerte, aufrechte Fassung (die App lässt sie von ihren
/// Bildwerkzeugen erzeugen, was um ein Vielfaches schneller geht als das
/// Dekodieren in Dart), wird sie dafür genommen und jede Lage danach auf
/// die volle Grösse umgerechnet. Ohne [ladeKlein] liest der erste
/// Durchgang [lade] wie der zweite.
///
/// **Geprüft.** Wo ausgerichtet wird, muss jede Aufnahme danach auf ihren
/// Bezug passen ([ausrichtgueteMindestens]); sonst scheitert es mit
/// [Fuegegrund.nichtAusrichtbar] statt mit einem Bild voller Doppelkanten.
/// Passt sie unverschoben besser, bleibt sie unverschoben. Zu kleine
/// Aufnahmen scheitern mit [Fuegegrund.zuKlein].
HdrErgebnis fuegeBelichtungen(
  int anzahl,
  Farbbild Function(int i) lade, {
  Kleinfassung Function(int i)? ladeKlein,
  HdrOptionen optionen = const HdrOptionen(),
  void Function(int erledigt, int gesamt)? fortschritt,
}) {
  if (anzahl < hdrMindestens || anzahl > hdrHoechstens) {
    throw const Zusammenfuegefehler(Fuegegrund.anzahl);
  }
  final gesamt = 3 * anzahl;
  var erledigt = 0;
  void schritt() => fortschritt?.call(++erledigt, gesamt);

  (int, int) begrenzt(Farbbild b) {
    final f = b.pixel > optionen.hoechstensPixel
        ? math.sqrt(optionen.hoechstensPixel / b.pixel)
        : 1.0;
    return (
      math.max(1, (b.breite * f).floor()),
      math.max(1, (b.hoehe * f).floor()),
    );
  }

  // Erster Durchgang: Grösse festlegen, Grauwerte, Helligkeit und Farbe je
  // Aufnahme. Die Grauwerte (1 Byte je Punkt, höchstens 3200 an der langen
  // Seite) bleiben bis zum Ausrichten.
  var b1 = 0, h1 = 0;
  final grau = <Graubild>[];
  final hell = <double>[];
  var farbig = false;
  // Um so viel sind die Grauwerte kleiner als der erste Durchgang.
  var teiler = 1;
  for (var i = 0; i < anzahl; i++) {
    var b = ladeKlein?.call(i).bild ?? lade(i);
    if (i == 0) (b1, h1) = begrenzt(b);
    b = _angleichen(b, b1, h1, i);
    farbig = farbig || _mittlereSaettigung(b) > _farblosBis;
    var g = Graubild.aus(b);
    var summe = 0;
    for (final v in g.werte) {
      summe += v;
    }
    hell.add(summe / g.werte.length);
    if (optionen.ausrichten) {
      if (math.min(g.breite, g.hoehe) < _ausrichtenMindestensKante) {
        throw const Zusammenfuegefehler(Fuegegrund.zuKlein);
      }
      // Genau die Stufen, die [richteAus] selbst bilden würde: Das Ergebnis
      // bleibt dasselbe, nur ohne die oberen Stufen.
      var t = 1;
      while (math.max(g.breite, g.hoehe) > _ausrichtenHoechstensKante) {
        g = g.halb();
        t *= 2;
      }
      teiler = t;
    }
    grau.add(optionen.ausrichten ? g : Graubild(1, 1));
    schritt();
  }

  // Bezug ist die mittlere Helligkeit: Mit ihr teilen die hellste und die
  // dunkelste Aufnahme am meisten Zeichnung. Seine Stufen entstehen einmal
  // für alle.
  final reihe = List<int>.generate(anzahl, (i) => i)
    ..sort((a, b) => hell[a].compareTo(hell[b]));
  final bezug = reihe[(anzahl - 1) ~/ 2];
  final grob = List<Lage>.filled(anzahl, Lage.ruhe);
  final vorbereitet = optionen.ausrichten ? Ausrichtbezug(grau[bezug]) : null;
  for (var i = 0; i < anzahl; i++) {
    if (i == bezug) continue;
    if (vorbereitet != null) {
      final r = richteAusAn(vorbereitet, grau[i], drehung: optionen.drehung);
      if (math.max(r.guete, r.gueteRuhe) < ausrichtgueteMindestens) {
        throw Zusammenfuegefehler(Fuegegrund.nichtAusrichtbar, quelle: i);
      }
      grob[i] = r.gueteRuhe >= r.guete ? Lage.ruhe : r.lage;
    }
    schritt();
  }
  grau.clear();

  // Zweiter Durchgang: verschmelzen. Mit kleiner Fassung steht die volle
  // Grösse erst fest, wenn die erste Aufnahme gelesen ist.
  Farbbild? vorab;
  var breite = b1, hoehe = h1;
  if (ladeKlein != null) {
    vorab = lade(0);
    (breite, hoehe) = begrenzt(vorab);
  }
  final kx = teiler * breite / b1, ky = teiler * hoehe / h1;
  final lagen = [
    for (final l in grob) glaetteLage(Lage(l.dx * kx, l.dy * ky, l.winkel)),
  ];
  final (x0, y0, w, h) = gemeinsamerAusschnitt(lagen, breite, hoehe);
  if (w < 16 || h < 16) {
    throw const Zusammenfuegefehler(Fuegegrund.nichtAusrichtbar);
  }
  final stufen = pyramidenstufen(w, h);
  List<Ebene>? summeGewichte;
  List<Ebene>? summeY, summeCb, summeCr;
  for (var i = 0; i < anzahl; i++) {
    // In einer eigenen Funktion, damit das Farbbild schon wieder frei ist,
    // wenn die Pyramiden entstehen – bei 24 MP 144 MB weniger zugleich.
    final (gp, y, cb, cr) = _bereite(
      () {
        final q = vorab ?? lade(i);
        vorab = null;
        return _angleichen(q, breite, hoehe, i);
      },
      lagen[i],
      (x0, y0, w, h),
      stufen,
      saettigung: farbig,
    );
    // Helligkeit in voller, Farbe in halber Auflösung – Farbe ab Stufe 1
    // der Gewichte.
    summeY = _gewichtetDazu(summeY, y, gp, 0, stufen);
    summeCb = _gewichtetDazu(summeCb, cb, gp, 1, stufen - 1);
    summeCr = _gewichtetDazu(summeCr, cr, gp, 1, stufen - 1);
    if (summeGewichte == null) {
      summeGewichte = gp;
    } else {
      for (var l = 0; l < stufen; l++) {
        final s = summeGewichte[l].werte;
        final g = gp[l].werte;
        for (var k = 0; k < s.length; k++) {
          s[k] += g[k];
        }
      }
    }
    schritt();
  }

  // Je Stufe durch die Summe der Gewichte teilen (wie beim Mehrband-
  // Überblenden): Dann ergeben die Gewichte auf jeder Stufe eins, ohne
  // dass alle Gewichtskarten zugleich im Speicher liegen müssten.
  void teile(List<Ebene> p, int ab) {
    for (var l = 0; l < p.length; l++) {
      final z = p[l].werte;
      final s = summeGewichte![l + ab].werte;
      for (var k = 0; k < z.length; k++) {
        z[k] /= s[k] + 1e-12;
      }
    }
  }

  teile(summeY!, 0);
  teile(summeCb!, 1);
  teile(summeCr!, 1);
  summeGewichte = null;
  final yEbene = falteZusammen(summeY);
  final cbHalb = falteZusammen(summeCb);
  final crHalb = falteZusammen(summeCr);
  final bild = _setzeZusammen(yEbene, cbHalb, crHalb);
  schritt();
  return HdrErgebnis(bild, lagen, bezug, (x0, y0, w, h));
}

/// Liest eine Quelle, legt sie auf den gemeinsamen [ausschnitt] und gibt
/// ihre Gewichtspyramide, die Helligkeit und die beiden halben
/// Farbdifferenzen. [saettigung] wie bei [gewichteNachMertens].
(List<Ebene>, Ebene, Ebene, Ebene) _bereite(
  Farbbild Function() lade,
  Lage lage,
  (int, int, int, int) ausschnitt,
  int stufen, {
  required bool saettigung,
}) {
  final quelle = lade();
  final (x0, y0, w, h) = ausschnitt;
  final a =
      lage.winkel == 0 &&
          lage.dx == 0 &&
          lage.dy == 0 &&
          x0 == 0 &&
          y0 == 0 &&
          w == quelle.breite &&
          h == quelle.hoehe
      ? quelle
      : lege(quelle, lage, x0, y0, w, h);
  final gp = gausspyramide(
    gewichteNachMertens(a, saettigung: saettigung),
    stufen,
  );
  final (y, cb, cr) = _zerlege(a);
  return (gp, y, cb, cr);
}

/// Bringt [b] auf [breite] × [hoehe] – gleiches Seitenverhältnis
/// vorausgesetzt (auf 1,5 % genau), sonst [Fuegegrund.groessenUngleich].
Farbbild _angleichen(Farbbild b, int breite, int hoehe, int i) {
  if (b.breite == breite && b.hoehe == hoehe) return b;
  final soll = breite / hoehe;
  final ist = b.breite / b.hoehe;
  if ((ist - soll).abs() / soll > 0.015) {
    throw Zusammenfuegefehler(Fuegegrund.groessenUngleich, quelle: i);
  }
  if (b.breite >= breite && b.hoehe >= hoehe) {
    return verkleinere(b, breite, hoehe);
  }
  return Farbbild.aus(
    img.copyResize(
      b.bild,
      width: breite,
      height: hoehe,
      interpolation: img.Interpolation.linear,
    ),
  );
}

/// Das Gewicht jedes Punkts nach Mertens: Kontrast · Sättigung · gute
/// Belichtung, alle Exponenten 1, dazu 1e-12, damit eine Fläche, an der
/// keine Aufnahme etwas zeigt, gleichmässig gemischt wird.
///
/// **Ohne [saettigung] für farblose Reihen.** Bei einer Schwarzweissreihe
/// ist die Sättigung überall null, jedes Gewicht damit 1e-12 – und das
/// Verfahren mittelte die Aufnahmen bloss, mit flauen Lichtern und
/// Schatten. Bei Farbaufnahmen trägt die Sättigung dagegen mit, wie bei
/// Mertens; ob eine Reihe farblos ist, entscheidet [fuegeBelichtungen] für
/// alle Aufnahmen gemeinsam, damit die Gewichte vergleichbar bleiben.
Ebene gewichteNachMertens(Farbbild a, {bool saettigung = true}) {
  final w = a.breite, h = a.hoehe;
  final q = a.rgb;
  // Die gute Belichtung hängt je Kanal nur vom Wert ab: 256 Einträge statt
  // drei Exponentialfunktionen je Punkt.
  final glocke = Float64List(256);
  for (var v = 0; v < 256; v++) {
    final d = v / 255 - 0.5;
    glocke[v] = math.exp(-d * d / (2 * 0.2 * 0.2));
  }
  final g = helligkeit(a).werte;
  final aus = Ebene(w, h);
  final z = aus.werte;
  final wl = w - 1, hl = h - 1;
  for (var y = 0; y < h; y++) {
    final oben = (y == 0 ? 0 : y - 1) * w;
    final unten = (y == hl ? hl : y + 1) * w;
    final zeile = y * w;
    for (var x = 0; x < w; x++) {
      final i = zeile + x;
      final links = x == 0 ? i : i - 1;
      final rechts = x == wl ? i : i + 1;
      final kontrast =
          (4 * g[i] - g[links] - g[rechts] - g[oben + x] - g[unten + x]).abs();
      final r = q[i * 3], gr = q[i * 3 + 1], bl = q[i * 3 + 2];
      final double satt;
      if (saettigung) {
        final m = (r + gr + bl) / 3;
        final dr = r - m, dg = gr - m, db = bl - m;
        satt = math.sqrt((dr * dr + dg * dg + db * db) / 3) / 255;
      } else {
        satt = 1;
      }
      final belichtung = glocke[r] * glocke[gr] * glocke[bl];
      z[i] = kontrast * satt * belichtung + 1e-12;
    }
  }
  return aus;
}

/// Die mittlere Sättigung von [b] (Streuung von R, G, B, 0..1), an jedem
/// vierten Punkt jeder vierten Zeile gemessen – für die Frage, ob eine
/// Reihe farblos ist.
double _mittlereSaettigung(Farbbild b) {
  final q = b.rgb;
  var summe = 0.0;
  var n = 0;
  for (var y = 0; y < b.hoehe; y += 4) {
    for (var x = 0, i = y * b.breite * 3; x < b.breite; x += 4, i += 12) {
      final r = q[i], g = q[i + 1], bl = q[i + 2];
      final m = (r + g + bl) / 3;
      final dr = r - m, dg = g - m, db = bl - m;
      summe += math.sqrt((dr * dr + dg * dg + db * db) / 3);
      n++;
    }
  }
  return n == 0 ? 0 : summe / n / 255;
}

/// Helligkeit (voll) und die Farbdifferenzen Cb, Cr (halb, je vier Punkte
/// gemittelt), alles in 0..1 bzw. −0,5..0,5.
(Ebene, Ebene, Ebene) _zerlege(Farbbild a) {
  final w = a.breite, h = a.hoehe;
  final q = a.rgb;
  final y = Ebene(w, h);
  final yw = y.werte;
  for (var i = 0, j = 0; i < yw.length; i++, j += 3) {
    yw[i] = (0.299 * q[j] + 0.587 * q[j + 1] + 0.114 * q[j + 2]) / 255;
  }
  final w2 = (w + 1) >> 1, h2 = (h + 1) >> 1;
  final cb = Ebene(w2, h2), cr = Ebene(w2, h2);
  final cbw = cb.werte, crw = cr.werte;
  for (var yy = 0; yy < h2; yy++) {
    for (var xx = 0; xx < w2; xx++) {
      var sb = 0.0, sr = 0.0;
      var n = 0;
      for (var dy = 0; dy < 2; dy++) {
        final py = 2 * yy + dy;
        if (py >= h) continue;
        for (var dx = 0; dx < 2; dx++) {
          final px = 2 * xx + dx;
          if (px >= w) continue;
          final i = py * w + px;
          final l = yw[i];
          sb += 0.564 * (q[i * 3 + 2] / 255 - l);
          sr += 0.713 * (q[i * 3] / 255 - l);
          n++;
        }
      }
      cbw[yy * w2 + xx] = sb / n;
      crw[yy * w2 + xx] = sr / n;
    }
  }
  return (y, cb, cr);
}

/// Baut die Laplacepyramide von [e] mit [stufen] Stufen, wiegt jede Stufe
/// mit den Gewichten [gp] ab Stufe [ab] und zählt sie auf [summe] auf.
List<Ebene> _gewichtetDazu(
  List<Ebene>? summe,
  Ebene e,
  List<Ebene> gp,
  int ab,
  int stufen,
) {
  final p = gausspyramide(e, math.max(1, stufen));
  zuLaplace(p);
  for (var l = 0; l < p.length; l++) {
    final z = p[l].werte;
    final g = gp[l + ab].werte;
    for (var k = 0; k < z.length; k++) {
      z[k] *= g[k];
    }
  }
  if (summe == null) return p;
  for (var l = 0; l < p.length; l++) {
    final s = summe[l].werte;
    final z = p[l].werte;
    for (var k = 0; k < s.length; k++) {
      s[k] += z[k];
    }
  }
  return summe;
}

/// Setzt Helligkeit und Farbdifferenzen wieder zu RGB zusammen, mit 0..255
/// begrenzt. Die halben Farbebenen werden dafür einzeln erweitert.
Farbbild _setzeZusammen(Ebene y, Ebene cbHalb, Ebene crHalb) {
  final w = y.breite, h = y.hoehe;
  final aus = Farbbild.leer(w, h);
  final z = aus.rgb;
  final yw = y.werte;
  // Rot braucht nur Cr, Blau nur Cb, Grün beide: erst Cr, dann Cb, damit
  // nie beide vollen Ebenen zugleich im Speicher liegen.
  final gruen = Float32List(w * h);
  int stelle(double v) {
    final x = (v * 255 + 0.5).floor();
    return x < 0 ? 0 : (x > 255 ? 255 : x);
  }

  {
    final cr = erweitere(crHalb, w, h).werte;
    for (var i = 0; i < yw.length; i++) {
      z[i * 3] = stelle(yw[i] + 1.402 * cr[i]);
      gruen[i] = yw[i] - 0.714136 * cr[i];
    }
  }
  {
    final cb = erweitere(cbHalb, w, h).werte;
    for (var i = 0; i < yw.length; i++) {
      z[i * 3 + 1] = stelle(gruen[i] - 0.344136 * cb[i]);
      z[i * 3 + 2] = stelle(yw[i] + 1.772 * cb[i]);
    }
  }
  return aus;
}
