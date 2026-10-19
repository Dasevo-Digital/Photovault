/// **Die Landschaft in Blöcken – damit sie scharf werden kann.**
///
/// Bis hierher trug der Geländeflug **eine** Textur über der ganzen
/// Landschaft, und ihre Stufe war an die des Höhengitters gekettet
/// (`gelaendeHoechsteStufe` = 15) und teilte sich mit ihm ein Budget von
/// sechzehn Kacheln. Gemessen an der Wanderung durch das Ilsetal
/// (2,82 × 3,27 km) fiel die Wahl damit auf Stufe 14:
///
/// ```
/// Stufe   Kacheln        Textur        m/Bildpunkt   Speicher
/// z14     2x3 =    6      512x768          5,90        2 MB   <- vorher
/// z16     8x10 =  80     2048x2560         1,48       20 MB
/// z17    15x19 = 285     3840x4864         0,74       71 MB
/// z18    30x36 =1080     7680x9216         0,37      270 MB
/// ```
///
/// Fünf Meter neunzig je Bildpunkt – daher der Brei. Die **Höhen** müssen
/// bei 15 aufhören, weil die Quelle darüber nichts liefert; die
/// **Textur** muss das nicht. Sie kann aber auch nicht einfach auf 18
/// gehen: 270 MB in einer einzigen Bildfläche sind weder zu halten noch
/// überhaupt anzulegen, und eine zwölf Kilometer lange Tour wäre das
/// Sechzehnfache davon.
///
/// Deshalb Blöcke. Die Landschaft zerfällt in Rechtecke entlang der
/// Kachelgrenzen einer Grundstufe; **jeder Block trägt seine eigene
/// Textur und wählt seine eigene Stufe nach der Entfernung zur Kamera.**
/// Nahe der Kamera fein, in der Ferne grob – und geladen wird nur, was
/// wirklich zu sehen ist.
///
/// Reine Rechnung: kein Flutter, kein Netz, keine Bilder. Damit lässt
/// sich jede Stufenwahl prüfen, ohne einen Server zu fragen.
library;

import 'dart:math' as math;

import 'gelaendekacheln.dart';

/// Auf welcher Kachelstufe ein Block sein Rechteck absteckt.
///
/// **Sechzehn, und das ist eine Abwägung.** Ein Block der Stufe 16 misst
/// auf der Breite des Harzes rund 380 Meter. Gröber (z15, 760 m) hiesse,
/// dass ein einzelner Block bei Stufe 18 schon 16 × 16 Kacheln bräuchte –
/// 16 MB für ein Stück Landschaft, das zur Hälfte hinter einem Berg
/// liegt. Feiner (z17, 190 m) vervierfachte die Zahl der Blöcke und damit
/// die Verwaltung, ohne dass ein Block dadurch billiger würde.
const int texturGrundstufe = 16;

/// Die feinste Stufe, die ein Block laden darf.
///
/// Esri liefert das Weltbild bis 19; die Wanderwege von Waymarked Trails
/// hören bei 18 auf (bei 19 kommt 404). 18 ist ausserdem die Stufe, ab
/// der ein Block 4 MB belegt – bei 19 wären es 16 MB, und der Vorrat
/// fasste dann nur noch fünf Blöcke.
const int texturHoechsteStufe = 18;

/// Ein Rechteck der Landschaft, an den Kachelgrenzen von
/// [texturGrundstufe] ausgerichtet.
///
/// Die Grenzen sind **Kachelgrenzen und keine gerundeten Gradzahlen**:
/// Nur so deckt sich ein Block auf jeder feineren Stufe genau mit einer
/// ganzen Zahl von Kacheln, und nur so stossen zwei Nachbarblöcke ohne
/// Lücke und ohne Überlappung aneinander.
class Texturblock {
  /// Kachelkoordinaten auf [grundstufe].
  final int spalte;
  final int zeile;
  final int grundstufe;

  const Texturblock({
    required this.spalte,
    required this.zeile,
    required this.grundstufe,
  });

  double get west => kachelWesten(spalte, grundstufe);
  double get ost => kachelWesten(spalte + 1, grundstufe);
  double get nord => kachelNorden(zeile, grundstufe);
  double get sued => kachelNorden(zeile + 1, grundstufe);

  double get mitteBreite => (nord + sued) / 2;
  double get mitteLaenge => (west + ost) / 2;

  /// Wie viele Kacheln je Kante dieser Block auf [stufe] braucht.
  ///
  /// Eine Stufe feiner heisst doppelt so viele Kacheln je Kante. Unter
  /// der Grundstufe gibt es nichts zu teilen – dann ist es eine.
  int kachelnJeKante(int stufe) =>
      stufe <= grundstufe ? 1 : 1 << (stufe - grundstufe);

  /// Die Kantenlänge der fertigen Textur in Bildpunkten.
  int texturkante(int stufe) => kachelnJeKante(stufe) * kachelKante;

  /// Was die Textur dieses Blocks auf [stufe] im Speicher belegt.
  int speicherBytes(int stufe) {
    final k = texturkante(stufe);
    return k * k * 4;
  }

  /// Die Kacheladressen dieses Blocks auf [stufe], zeilenweise von
  /// Nordwesten nach Südosten – in derselben Reihenfolge, in der sie
  /// zusammengesetzt werden.
  List<({int z, int x, int y})> kacheln(int stufe) {
    final n = kachelnJeKante(stufe);
    final x0 = spalte * n;
    final y0 = zeile * n;
    return [
      for (var dy = 0; dy < n; dy++)
        for (var dx = 0; dx < n; dx++) (z: stufe, x: x0 + dx, y: y0 + dy),
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is Texturblock &&
      other.spalte == spalte &&
      other.zeile == zeile &&
      other.grundstufe == grundstufe;

  @override
  int get hashCode => Object.hash(spalte, zeile, grundstufe);

  @override
  String toString() => 'Block($grundstufe/$spalte/$zeile)';
}

/// Alle Blöcke, die einen Ausschnitt abdecken – zeilenweise von
/// Nordwesten nach Südosten.
///
/// Der äusserste Block ragt in der Regel über den Ausschnitt hinaus; das
/// ist gewollt. Ein Block, der an der Ausschnittkante beschnitten würde,
/// deckte sich nicht mehr mit ganzen Kacheln, und genau darauf beruht
/// die ganze Rechnung.
List<Texturblock> texturbloecke({
  required double sued,
  required double west,
  required double nord,
  required double ost,
  int grundstufe = texturGrundstufe,
}) {
  final x0 = kachelX(west, grundstufe);
  final x1 = kachelX(ost, grundstufe);
  // Zeile 0 liegt im Norden – Nord und Süd sind bei den Kachelzeilen
  // deshalb vertauscht.
  final y0 = kachelY(nord, grundstufe);
  final y1 = kachelY(sued, grundstufe);
  return [
    for (var y = y0; y <= y1; y++)
      for (var x = x0; x <= x1; x++)
        Texturblock(spalte: x, zeile: y, grundstufe: grundstufe),
  ];
}

/// Wie viele Meter ein Bildpunkt einer Kachel auf [stufe] abdeckt.
///
/// Web-Mercator: Am Äquator sind es 156.543 Meter je Bildpunkt auf Stufe
/// 0, und auf jeder weiteren Stufe die Hälfte. Zu den Polen hin schrumpft
/// der Massstab mit dem Kosinus der Breite.
double kachelAufloesung(double breite, int stufe) =>
    156543.03392 * math.cos(breite * math.pi / 180) / (1 << stufe);

/// Die Stufe, auf der ein Block in [entfernungMeter] Entfernung geladen
/// werden soll.
///
/// **Die Regel ist nicht geraten, sondern gerechnet.** Ein Bildpunkt auf
/// dem Schirm deckt in der Entfernung *d* genau `d / brennweite` Meter ab
/// (das ist die Umkehrung der Projektion in `Gelaendekamera`). Gesucht ist
/// die gröbste Stufe, deren Kachelauflösung noch feiner ist als das –
/// jede feinere lieferte Bildpunkte, die niemand sieht, und jede gröbere
/// wäre sichtbar unscharf.
///
/// [schaerfe] verschiebt das Ganze: 1 heisst „ein Texturpunkt je
/// Bildpunkt". Auf einem Bildschirm mit doppelter Punktdichte gehört das
/// Pixelverhältnis hinein, sonst ist die Karte auf dem halben Weg zur
/// Unschärfe.
///
/// **Nach unten wird nicht auf die Grundstufe geklemmt**, und das ist
/// eine Entscheidung, die eine Messung erzwungen hat: Mit der Grundstufe
/// als Untergrenze bekäme auch der fernste Block noch eine eigene Textur
/// der Stufe 16. Bei einer Tour über zwölf Kilometer sind das über
/// tausend Blöcke und 256 MB, bevor überhaupt etwas scharf ist. Was
/// gröber als die Übersichtskarte wäre, braucht deshalb gar keine eigene
/// Textur – das entscheidet der Aufrufer, der weiss, wie fein seine
/// Übersicht ist.
int blockstufe({
  required double entfernungMeter,
  required double brennweite,
  required double breite,
  double schaerfe = 1.0,
  int hoechsteStufe = texturHoechsteStufe,
}) {
  if (!entfernungMeter.isFinite || entfernungMeter <= 0) return hoechsteStufe;
  if (brennweite <= 0) return 0;
  // Was ein Bildpunkt in dieser Entfernung abdeckt.
  final gebraucht = entfernungMeter / (brennweite * schaerfe);
  if (gebraucht <= 0) return hoechsteStufe;
  // kachelAufloesung(stufe) <= gebraucht  <=>  2^stufe >= aufloesung0/gebraucht
  final null0 = kachelAufloesung(breite, 0);
  final stufe = (math.log(null0 / gebraucht) / math.ln2).ceil();
  return stufe.clamp(0, hoechsteStufe);
}
