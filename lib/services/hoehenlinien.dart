/// **Höhenlinien, selbst gerechnet.**
///
/// Es gäbe sie auch als Kacheln – OpenTopoMap zeichnet welche, und die
/// Geländeansicht hat sie bisher genau so bekommen. Drei Gründe, warum
/// sie hier trotzdem selbst entstehen:
///
/// 1. **Sie sitzen auf der Geometrie.** Geladene Höhenlinien kommen aus
///    einer anderen Quelle als das Höhengitter darunter; sie liegen dann
///    ein paar Meter neben dem Hang, den sie beschreiben. Diese hier
///    kommen aus **demselben** Gitter, aus dem auch die Landschaft
///    gebaut ist – sie können gar nicht danebenliegen.
/// 2. **Sie sind auf jeder Stufe scharf.** Eine Linie, die als Bild
///    ankommt, wird beim Näherkommen unscharf wie jedes Bild. Eine
///    gerechnete wird beim Näherkommen genauer.
/// 3. **Sie kosten keinen einzigen Abruf.** Das Gitter liegt ohnehin vor.
///
/// **Marching Squares**, das Standardverfahren: Jede Gitterzelle wird
/// daraufhin angesehen, welche ihrer vier Ecken über der gesuchten Höhe
/// liegen. Aus den sechzehn möglichen Fällen ergeben sich die
/// Streckenstücke, und wo eine Linie eine Kante schneidet, wird zwischen
/// den beiden Eckhöhen linear interpoliert – sonst hätte die Linie
/// Treppenstufen in der Grösse einer Gitterzelle.
///
/// Die Rechnung kommt ohne Flutter, ohne Netz und ohne Bilder aus; das
/// Ergebnis sind Strecken in **Blockkoordinaten von 0 bis 1**, so wie
/// eine Blocktextur sie braucht. Ganz unten steht dann doch ein
/// Zeichenbefehl – [zeichneHoehenlinien]. Er gehört hierher, weil zwei
/// Aufrufer ihn brauchen (die Blocktextur und die Übersicht) und weil
/// Strichstärke und Farbe zur Rechnung gehören, nicht zum Aufrufer.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'gelaendekacheln.dart';

/// Ein Streckenstück einer Höhenlinie, in Blockkoordinaten 0..1.
typedef Linienstueck = ({double x1, double y1, double x2, double y2});

/// Alle Höhenlinien eines Blocks.
typedef Hoehenlinien = ({
  /// Der Abstand zwischen zwei Linien in Metern.
  double abstand,

  /// Die gewöhnlichen Linien.
  List<Linienstueck> linien,

  /// Jede fünfte, kräftiger gezeichnet – ohne sie ist eine Schar von
  /// Linien nicht zu zählen.
  List<Linienstueck> zaehllinien,
});

/// Der Abstand zwischen zwei Höhenlinien, passend zum Gelände.
///
/// **Nicht fest, weil Gelände nicht gleich Gelände ist.** Zehn Meter sind
/// im Harz (195 bis 1139 m auf dem geladenen Ausschnitt) richtig und in
/// Grindelwald (547 bis 4035 m) ein schwarzer Filz: Dort lägen bei
/// dreieinhalbtausend Metern Unterschied dreihundertfünfzig Linien
/// übereinander. Gesucht ist der Abstand, bei dem rund zwanzig bis
/// vierzig Linien herauskommen.
///
/// Die Stufen sind die einer Wanderkarte – 5, 10, 20, 25, 50, 100, 200,
/// 500 – und keine gerechnete Zahl: „alle 37 Meter" liest niemand.
double hoehenlinienAbstand(double spanne) {
  const stufen = [5.0, 10.0, 20.0, 25.0, 50.0, 100.0, 200.0, 500.0, 1000.0];
  for (final s in stufen) {
    if (spanne / s <= 30) return s;
  }
  return stufen.last;
}

/// Die Höhenlinien über einem rechteckigen Ausschnitt.
///
/// [west], [ost], [sued], [nord] stecken den Block ab; die Koordinaten
/// des Ergebnisses sind darauf bezogen, 0 im Nordwesten und 1 im
/// Südosten. Die Breite läuft **mercatorgerecht**, damit die Linien zu
/// den Kacheln passen, auf denen sie liegen.
///
/// [maschen] ist die Zahl der Abtastzellen je Kante. Mehr heisst glatter
/// und teurer; für eine Blocktextur von 512 Bildpunkten sind 64 Zellen
/// eine Zelle je acht Bildpunkte, und feiner sieht man nicht.
Hoehenlinien hoehenlinien(
  Hoehengitter gitter, {
  required double west,
  required double ost,
  required double sued,
  required double nord,
  required double abstand,
  int maschen = 64,
  int grundstufe = 16,
}) {
  final linien = <Linienstueck>[];
  final zaehllinien = <Linienstueck>[];
  if (!(ost > west) || !(nord > sued) || abstand <= 0) {
    return (abstand: abstand, linien: linien, zaehllinien: zaehllinien);
  }

  // Die Höhen an den Gitterpunkten dieses Blocks, einmal geholt.
  final h = List<double?>.filled((maschen + 1) * (maschen + 1), null);
  // Mercator, damit x und y so laufen wie auf der Kachel darunter.
  final xW = kachelXGenau(west, grundstufe);
  final xO = kachelXGenau(ost, grundstufe);
  final yN = kachelYGenau(nord, grundstufe);
  final yS = kachelYGenau(sued, grundstufe);
  double laengeBei(double t) =>
      (xW + (xO - xW) * t) / (1 << grundstufe) * 360 - 180;
  double breiteBei(double t) {
    final y = yN + (yS - yN) * t;
    final r = math.pi * (1 - 2 * y / (1 << grundstufe));
    return 180 / math.pi * math.atan(0.5 * (math.exp(r) - math.exp(-r)));
  }

  var tief = double.infinity;
  var hoch = double.negativeInfinity;
  for (var j = 0; j <= maschen; j++) {
    final breite = breiteBei(j / maschen);
    for (var i = 0; i <= maschen; i++) {
      final w = gitter.anOrt(breite, laengeBei(i / maschen));
      h[j * (maschen + 1) + i] = w;
      if (w != null) {
        if (w < tief) tief = w;
        if (w > hoch) hoch = w;
      }
    }
  }
  if (!tief.isFinite || !hoch.isFinite) {
    return (abstand: abstand, linien: linien, zaehllinien: zaehllinien);
  }

  /// Wo auf der Strecke von [a] nach [b] die Höhe [ziel] liegt.
  double anteil(double a, double b, double ziel) =>
      (b - a).abs() < 1e-9 ? 0.5 : ((ziel - a) / (b - a)).clamp(0.0, 1.0);

  final erste = (tief / abstand).ceil();
  final letzte = (hoch / abstand).floor();
  // Eine Obergrenze, damit ein kaputtes Gitter nicht Millionen Linien
  // erzeugt: Bei mehr als zweihundert Linien ist der Abstand falsch
  // gewählt, nicht das Gelände ungewöhnlich.
  for (var k = erste; k <= letzte && k - erste < 200; k++) {
    final ziel = k * abstand;
    final ziel5 = k % 5 == 0;
    final wohin = ziel5 ? zaehllinien : linien;
    for (var j = 0; j < maschen; j++) {
      for (var i = 0; i < maschen; i++) {
        final a = h[j * (maschen + 1) + i];
        final b = h[j * (maschen + 1) + i + 1];
        final c = h[(j + 1) * (maschen + 1) + i + 1];
        final d = h[(j + 1) * (maschen + 1) + i];
        // Eine Zelle mit einer unbekannten Ecke wird übersprungen: Eine
        // Linie durch ein Loch im Gitter wäre erfunden.
        if (a == null || b == null || c == null || d == null) continue;

        // **Und eine Zelle ohne Höhenunterschied auch.**
        //
        // Das ist keine Vorsichtsmassnahme, sondern ein Fehler, den der
        // Test an einer ebenen Fläche von genau 500 Metern gefunden hat:
        // Dort standen Höhenlinien. `anOrt` interpoliert bilinear, und
        // die vier Gewichte summieren sich in Fliesskomma nicht exakt
        // auf eins – aus 500,0 wird mal 499,99999999999994 und mal
        // 500,00000000000006. Die Linie bei genau 500 lief dann quer
        // durch das Rauschen.
        //
        // In der Landschaft heisst „ebene Fläche" See, Stausee oder
        // Talsohle. Genau dort wäre eine Linie am auffälligsten falsch.
        final tiefsteEcke = math.min(math.min(a, b), math.min(c, d));
        final hoechsteEcke = math.max(math.max(a, b), math.max(c, d));
        if (hoechsteEcke - tiefsteEcke < 1e-6) continue;

        final x0 = i / maschen;
        final x1 = (i + 1) / maschen;
        final y0 = j / maschen;
        final y1 = (j + 1) / maschen;

        // Die Schnittpunkte auf den vier Kanten, im Uhrzeigersinn ab
        // oben. `null` heisst: Diese Kante wird nicht geschnitten.
        final oben = (a > ziel) != (b > ziel)
            ? (x: x0 + (x1 - x0) * anteil(a, b, ziel), y: y0)
            : null;
        final rechts = (b > ziel) != (c > ziel)
            ? (x: x1, y: y0 + (y1 - y0) * anteil(b, c, ziel))
            : null;
        final unten = (d > ziel) != (c > ziel)
            ? (x: x0 + (x1 - x0) * anteil(d, c, ziel), y: y1)
            : null;
        final links = (a > ziel) != (d > ziel)
            ? (x: x0, y: y0 + (y1 - y0) * anteil(a, d, ziel))
            : null;

        final punkte = [
          if (oben != null) oben,
          if (rechts != null) rechts,
          if (unten != null) unten,
          if (links != null) links,
        ];
        // Zwei Schnittpunkte sind der Regelfall. Vier bedeuten einen
        // Sattel – dann werden sie paarweise verbunden, wie sie in der
        // Aufzählung stehen; welches der beiden Paare richtig ist,
        // entscheidet erst der Mittelwert, und der Unterschied ist eine
        // halbe Zelle. Bei einer Zelle von acht Bildpunkten fällt das
        // nicht auf.
        for (var p = 0; p + 1 < punkte.length; p += 2) {
          wohin.add((
            x1: punkte[p].x,
            y1: punkte[p].y,
            x2: punkte[p + 1].x,
            y2: punkte[p + 1].y
          ));
        }
      }
    }
  }

  return (abstand: abstand, linien: linien, zaehllinien: zaehllinien);
}

/// Zeichnet die Linien in ein Bild von [breite] mal [hoehe] Bildpunkten.
///
/// **Zwei Striche je Linie, und der erste ist der Grund dafür.** Am
/// gerenderten Luftbild des Ilsetals war von den Höhenlinien nichts zu
/// sehen: Ein brauner Strich über dunklem Nadelwald hat kaum Kontrast.
/// Umgekehrt verschwände ein heller Strich über einer Kalkwand. Deshalb
/// liegt unter jeder Linie ein etwas breiterer dunkler Saum und darüber
/// der helle Kern – dieselbe Machart wie bei der Spur (siehe
/// `Gelaendemaler._spurZug`), und aus demselben Grund: Eine Linie muss
/// auf jedem Untergrund lesbar sein, den ein Luftbild hergibt.
///
/// Die Strichstärke wächst mit der Bildgrösse. Ein Strich von einem
/// Bildpunkt ist auf einer Textur von 1024 Punkten ein Faden, den auf dem
/// Schirm niemand sieht – die Textur wird ja auf ein Stück Landschaft
/// gelegt, das viel kleiner ist als sie selbst.
void zeichneHoehenlinien(
    ui.Canvas leinwand, Hoehenlinien linien, double breite, double hoehe) {
  final massstab = math.max(breite, hoehe) / 512;

  void zug(List<Linienstueck> stuecke, double stark) {
    if (stuecke.isEmpty) return;
    final pfad = ui.Path();
    for (final s in stuecke) {
      pfad.moveTo(s.x1 * breite, s.y1 * hoehe);
      pfad.lineTo(s.x2 * breite, s.y2 * hoehe);
    }
    leinwand.drawPath(
      pfad,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (stark + 1.4) * massstab
        ..color = const ui.Color(0xFF3A2A18).withValues(alpha: 0.40),
    );
    leinwand.drawPath(
      pfad,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = stark * massstab
        ..color = const ui.Color(0xFFFFE3B0).withValues(alpha: 0.80),
    );
  }

  zug(linien.linien, 1.0);
  // Jede fünfte kräftiger – ohne sie ist eine Schar von Linien nicht zu
  // zählen.
  zug(linien.zaehllinien, 2.0);
}
