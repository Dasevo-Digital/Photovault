/// Wie gross die Kacheln der Zeitleiste sein können.
///
/// **Warum das hier steht und nicht beim Raster.** Die Wahl wird in den
/// Einstellungen abgelegt, und die Datenbank darf keinen Baustein der
/// Oberfläche einlesen. Beide – die Spalte und das Raster – brauchen
/// dieselben Zahlen; zwei Sätze wären zwei Rechnungen, die auseinander
/// laufen, sobald jemand nur eine anfasst.
library;

/// Die wählbaren Kachelbreiten, von klein nach gross.
///
/// **Warum Stufen und keine stufenlose Rechnung.** Eine Kachelbreite, die
/// sich mit jedem Punkt ändert, ist genau der Fall, für den es
/// `dekodierbreite` gibt: Jeder Zwischenschritt wäre ein eigener
/// Schlüssel im Bildspeicher, und jede sichtbare Kachel würde dabei neu
/// dekodiert. Fünf Stufen sind fünf Schlüssel.
///
/// Die mittlere ist 160 – die Grösse, die es vorher als einzige gab. Wer
/// nichts einstellt, sieht also genau das Bisherige.
const List<double> zeitleisteKachelstufen = [96, 128, 160, 220, 300];

/// Welche Stufe gilt, wenn niemand etwas eingestellt hat.
const int zeitleisteKachelstufeVorgabe = 2;

/// Die Kachelbreite zu einer Stufe.
///
/// Eine Zahl ausserhalb der Reihe fällt auf die Vorgabe zurück, statt den
/// Bildschirm zu verhindern – dieselbe Regel wie beim Kartenstil.
double zeitleisteKachelbreite(int stufe) =>
    stufe >= 0 && stufe < zeitleisteKachelstufen.length
        ? zeitleisteKachelstufen[stufe]
        : zeitleisteKachelstufen[zeitleisteKachelstufeVorgabe];

/// Die Stufe, die auf [stufe] folgt – geklemmt an den Enden.
int naechsteKachelstufe(int stufe, {required bool groesser}) =>
    (stufe + (groesser ? 1 : -1)).clamp(0, zeitleisteKachelstufen.length - 1);

/// Wie viele Kacheln nebeneinander in einen waagerechten Streifen passen.
///
/// **Wozu.** Die Übersicht zeigte feste Zahlen – zehn Personen, acht
/// Alben, zwölf Fotos –, gleich ob das Fenster 900 oder 2000 Punkte breit
/// war. Auf einem breiten Schirm blieb die halbe Zeile leer, und wer mehr
/// sehen wollte, musste den Streifen schieben, obwohl der Platz da war.
///
/// [hoechstens] deckelt das nach oben: Ein Streifen ist eine Vorschau,
/// keine vollständige Liste – dafür gibt es „Alle anzeigen".
/// [mindestens] hält ihn auf schmalen Fenstern am Leben; lieber eine
/// Kachel, die halb hineinragt, als ein leerer Abschnitt.
int streifenAnzahl(
  double breite, {
  required double kachelbreite,
  required double abstand,
  required int hoechstens,
  int mindestens = 3,
}) {
  if (!breite.isFinite || breite <= 0) return mindestens;
  // Die letzte Kachel braucht keinen Abstand hinter sich.
  final passt = ((breite + abstand) / (kachelbreite + abstand)).floor();
  return passt.clamp(mindestens, hoechstens);
}

/// Wie die Zeitleiste ihre Fotos anordnet.
///
/// **Zwei Formen und nicht eine.** Die Quadrate zeigen von jedem Foto
/// denselben Ausschnitt und lassen die Augen in Spalten laufen – gut, um
/// etwas Bestimmtes zu suchen. Die Reihen zeigen jedes Foto so, wie es
/// aufgenommen wurde, und ein Hochformat sieht auch aus wie eines – gut,
/// um zu schauen. Welche gerade richtig ist, hängt daran, was man vorhat,
/// und das weiss nur der Betrachter.
enum Zeitleistenform {
  /// Festes Raster, alle Kacheln quadratisch und beschnitten.
  quadrate,

  /// Bündige Reihen, jedes Foto in seinem eigenen Seitenverhältnis.
  reihen,
}

/// Welche Form gilt, wenn niemand etwas eingestellt hat.
///
/// Die Quadrate – wer nichts umstellt, sieht genau das Bisherige.
const Zeitleistenform zeitleisteFormVorgabe = Zeitleistenform.quadrate;

/// Die Form zu einer gespeicherten Zahl.
///
/// Eine Zahl ausserhalb der Reihe fällt auf die Vorgabe zurück, statt den
/// Bildschirm zu verhindern – dieselbe Regel wie bei der Kachelstufe.
Zeitleistenform zeitleisteForm(int wert) =>
    wert >= 0 && wert < Zeitleistenform.values.length
        ? Zeitleistenform.values[wert]
        : zeitleisteFormVorgabe;
