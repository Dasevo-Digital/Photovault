/// Bündige Reihen: Fotos in ihrem eigenen Seitenverhältnis, jede Reihe
/// auf die volle Breite gefüllt.
///
/// **Warum das hier steht und nicht beim Raster.** Es ist reine Rechnung,
/// dieselbe Trennung wie bei `zierbaum.dart` und `faechertafel.dart`: Der
/// Zeitstrahl muss die Höhe einer Monatsgruppe kennen, ohne dass ein Pixel
/// entsteht. Läge die Anordnung im Widget, gäbe es sie zweimal – einmal
/// gezeichnet und einmal geschätzt –, und genau das war beim festen Raster
/// schon einmal der Grund, warum der Zeitstrahl an eine andere Stelle sprang
/// als das Raster.
///
/// **Reihen und nicht Spalten.** Eine Spaltenwand (Masonry) sieht in einer
/// Portfolio-Galerie gut aus, schickt aber das zweite Foto in die zweite
/// Spalte. In einer nach Datum sortierten Zeitleiste ist das die falsche
/// Reihenfolge: Hier wird links nach rechts und oben nach unten gelesen.
library;

/// Das Seitenverhältnis (Breite ÷ Höhe), das gilt, wenn die Datenbank
/// keines kennt.
///
/// An der echten Bibliothek gemessen betrifft das 2 von 8098 Aufnahmen.
/// Ein Kleinbildformat ist die harmloseste Annahme: Es ist weder besonders
/// schmal noch besonders breit, fällt also in keiner Richtung auf.
const double seitenverhaeltnisVorgabe = 3 / 2;

/// Ein Platz in einer Reihe: welches Element, und wie breit es dort ist.
typedef Bildplatz = ({int index, double breite});

/// Eine fertige Reihe – alle Plätze darin sind [hoehe] hoch.
class Bildreihe {
  const Bildreihe({required this.hoehe, required this.plaetze});

  final double hoehe;
  final List<Bildplatz> plaetze;

  /// Der erste Index in dieser Reihe. Reihen sind nie leer.
  int get ersterIndex => plaetze.first.index;

  /// Der letzte Index in dieser Reihe.
  int get letzterIndex => plaetze.last.index;
}

/// Ordnet [seitenverhaeltnisse] in bündige Reihen.
///
/// [breite] ist die verfügbare Breite, [abstand] der Zwischenraum zwischen
/// zwei Bildern derselben Reihe, [zielhoehe] die angestrebte Reihenhöhe –
/// bei uns die eingestellte Kachelstufe.
///
/// Das Verfahren: Elemente sammeln, solange die Reihe bei voller Breite
/// noch höher als [zielhoehe] wäre. Sobald sie es nicht mehr ist, wird sie
/// geschlossen und **exakt** auf [breite] skaliert.
///
/// **Die letzte Reihe wird nicht gestreckt.** Sie bleibt auf [zielhoehe]
/// stehen. Sonst zöge ein einzelnes übriges Foto sich über den halben
/// Bildschirm – und ausgerechnet das letzte Foto eines Monats bekäme so
/// eine Bedeutung, die es nicht hat.
List<Bildreihe> bildreihen({
  required List<double> seitenverhaeltnisse,
  required double breite,
  required double zielhoehe,
  required double abstand,
}) {
  if (seitenverhaeltnisse.isEmpty) return const [];
  // Ohne Breite gibt es nichts anzuordnen. Kein Wurf: Ein Widget wird beim
  // ersten Aufbau durchaus mit 0 vermessen, und dabei soll nichts krachen.
  if (!breite.isFinite || breite <= 0) return const [];
  if (!zielhoehe.isFinite || zielhoehe <= 0) return const [];

  final reihen = <Bildreihe>[];
  var beginn = 0;
  var summeVerhaeltnisse = 0.0;

  for (var i = 0; i < seitenverhaeltnisse.length; i++) {
    summeVerhaeltnisse += _gesundesVerhaeltnis(seitenverhaeltnisse[i]);
    final anzahl = i - beginn + 1;
    final nutzbar = breite - abstand * (anzahl - 1);
    // Die Höhe, bei der diese Elemente die Zeile genau füllen würden.
    final hoehe = nutzbar / summeVerhaeltnisse;

    if (hoehe <= zielhoehe) {
      // Voll genug. Ein einzelnes sehr breites Panorama landet hier schon
      // beim ersten Durchgang und bekommt damit seine eigene Reihe – was
      // richtig ist: Neben ihm wäre für nichts anderes Platz.
      reihen.add(_reihe(seitenverhaeltnisse, beginn, i, hoehe, breite, abstand));
      beginn = i + 1;
      summeVerhaeltnisse = 0;
    }
  }

  // Was übrig bleibt, behält die Zielhöhe.
  if (beginn < seitenverhaeltnisse.length) {
    reihen.add(_letzteReihe(
        seitenverhaeltnisse, beginn, seitenverhaeltnisse.length - 1, zielhoehe));
  }
  return reihen;
}

/// Die Gesamthöhe von [reihen] samt der Abstände dazwischen.
double reihenGesamthoehe(List<Bildreihe> reihen, double abstand) {
  if (reihen.isEmpty) return 0;
  var summe = 0.0;
  for (final r in reihen) {
    summe += r.hoehe;
  }
  return summe + abstand * (reihen.length - 1);
}

/// Ein Seitenverhältnis, mit dem sich rechnen lässt.
///
/// Null, negativ, unendlich oder `NaN` kämen aus einer kaputten oder
/// fehlenden Angabe. Sie durchzulassen hiesse, eine Reihe unendlich hoch
/// oder null breit zu machen – ein Bildschirm, der gar nichts mehr zeigt,
/// wegen eines einzigen falschen Eintrags.
double _gesundesVerhaeltnis(double v) =>
    v.isFinite && v > 0 ? v : seitenverhaeltnisVorgabe;

Bildreihe _reihe(List<double> verhaeltnisse, int von, int bis, double hoehe,
    double breite, double abstand) {
  final plaetze = <Bildplatz>[];
  var belegt = 0.0;
  for (var i = von; i <= bis; i++) {
    // Der letzte Platz bekommt, was übrig ist. Sonst summierten sich die
    // Rundungsreste, und der rechte Rand wäre mal einen halben Punkt zu
    // kurz, mal zu lang – bei einer bündigen Reihe genau das, was auffällt.
    final letzter = i == bis;
    final b = letzter
        ? breite - belegt - abstand * (bis - von)
        : hoehe * _gesundesVerhaeltnis(verhaeltnisse[i]);
    plaetze.add((index: i, breite: b));
    belegt += b;
  }
  return Bildreihe(hoehe: hoehe, plaetze: plaetze);
}

Bildreihe _letzteReihe(
    List<double> verhaeltnisse, int von, int bis, double hoehe) {
  return Bildreihe(
    hoehe: hoehe,
    plaetze: [
      for (var i = von; i <= bis; i++)
        (index: i, breite: hoehe * _gesundesVerhaeltnis(verhaeltnisse[i])),
    ],
  );
}
