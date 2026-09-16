/// **Die Tageszeit über der Landschaft.**
///
/// Eine Stimmung setzt alles gemeinsam, was sich mit dem Stand der Sonne
/// ändert: woher das Licht kommt und wie hoch es steht, wie es sich auf
/// Grund- und Richtungslicht verteilt, welche Farbe es hat, welche zwei
/// Farben den Himmel aufspannen und wie der Dunst in der Ferne aussieht.
///
/// **Als ein Wert und nicht als Verzweigung im Maler.** Dieselbe Regel
/// wie bei den zwei Farbsätzen des Zierbaums: Läge die Wahl im Maler,
/// malte der Prüfstand die eine Fassung und der Bildschirm die andere.
/// So bekommen beide denselben Wert hereingereicht.
///
/// **Die Sonne bleibt im Nordwesten – bei jeder Tageszeit.** Das ist
/// physikalisch falsch und trotzdem richtig: Das Auge liest eine von
/// links oben beleuchtete Fläche als erhaben und eine von rechts unten
/// beleuchtete als vertieft. Wer morgens von Osten beleuchtet, dreht
/// jedes Tal zum Berg (siehe `schattierung`). Was die Tageszeit deshalb
/// wirklich ändert, ist die **Höhe** der Sonne – flach am Morgen und am
/// Abend, also längere Schatten und schärferes Relief – und die
/// **Farbe**.
library;

import 'dart:ui' show Color;

/// Die vier Stimmungen. Als Aufzählung und nicht als freier Winkel: Vier
/// Bilder, zwischen denen man wählt, sind eine Entscheidung; ein Regler
/// von 0 bis 24 Uhr wäre eine Aufgabe.
enum Tageszeit { morgen, mittag, abend, blaueStunde }

/// Was die Vorgabe ist, wenn niemand etwas eingestellt hat.
///
/// Mittag, und zwar **mit genau den Schattierungswerten von vorher**:
/// Wer nichts umstellt, sieht dasselbe Relief wie bisher. Neu sind für
/// ihn nur Himmel, Dunst und die Spur – die gelten für jede Stimmung.
const Tageszeit lichtstimmungVorgabe = Tageszeit.mittag;

/// Alles, was eine Tageszeit am Bild ändert.
class Lichtstimmung {
  const Lichtstimmung({
    required this.zeit,
    required this.sonne,
    required this.grundlicht,
    required this.richtungslicht,
    required this.untergrenze,
    required this.lichtfarbe,
    required this.himmelOben,
    required this.himmelUnten,
    required this.dunst,
  });

  final Tageszeit zeit;

  /// Die Richtung **zum** Licht, auf Länge 1. x nach Osten, y nach
  /// Norden, z nach oben – dieselben Achsen wie beim Gelände.
  final ({double x, double y, double z}) sonne;

  /// Wie viel Helligkeit eine Fläche auch dann hat, wenn sie von der
  /// Sonne wegzeigt. Zusammen mit [richtungslicht] ergibt es 1.
  ///
  /// **Viel Grundlicht heisst lesbare Karte, wenig heisst starkes
  /// Relief.** Das ist der Zielkonflikt dieser Ansicht, und er wird hier
  /// entschieden und nirgends sonst.
  final double grundlicht;
  final double richtungslicht;

  /// Wie dunkel eine abgewandte Fläche höchstens wird.
  ///
  /// Nicht bis auf null: Eine schwarze Nordflanke sieht aus wie ein Loch
  /// im Gitter, nicht wie ein Hang.
  final double untergrenze;

  /// Die Tönung des Lichts. Wird auf die Karte multipliziert, färbt sie
  /// also mit – deshalb zurückhaltend gewählt.
  final Color lichtfarbe;

  /// Der Himmel als senkrechter Verlauf: oben und unten.
  final Color himmelOben;
  final Color himmelUnten;

  /// Wohin die Ferne verblasst. Nahe an [himmelUnten], damit die
  /// Landschaft am Rand in den Himmel übergeht, statt gegen ihn zu
  /// schneiden.
  final Color dunst;
}

/// Mittag – **die Zahlen, die vorher fest im Code standen**.
///
/// Sonne aus Nordwesten, 45° hoch; 0,72 Grundlicht, 0,28 Richtungslicht,
/// nicht unter 0,5. Ein Test hält das fest, damit die Vorgabe nicht
/// nebenbei verrutscht.
const Lichtstimmung stimmungMittag = Lichtstimmung(
  zeit: Tageszeit.mittag,
  sonne: (x: -0.5, y: 0.5, z: 0.707),
  grundlicht: 0.72,
  richtungslicht: 0.28,
  untergrenze: 0.5,
  lichtfarbe: Color(0xFFFFFFFF),
  himmelOben: Color(0xFF5B93CE),
  himmelUnten: Color(0xFFCFE4F5),
  dunst: Color(0xFFC6DCEF),
);

/// Morgen – die Sonne steht bei 22°, das Licht ist warm, der Dunst
/// milchig. Flachere Sonne heisst längere Schatten: Das Relief tritt
/// deutlich stärker hervor als am Mittag.
const Lichtstimmung stimmungMorgen = Lichtstimmung(
  zeit: Tageszeit.morgen,
  sonne: (x: -0.614, y: 0.692, z: 0.375),
  grundlicht: 0.62,
  richtungslicht: 0.38,
  untergrenze: 0.42,
  lichtfarbe: Color(0xFFFFF4E6),
  himmelOben: Color(0xFF9CC0E6),
  himmelUnten: Color(0xFFFFE8CC),
  dunst: Color(0xFFF2E2CE),
);

/// Abend – 14° und deutlich wärmer. Die stärkste Reliefwirkung der vier.
///
/// Der Himmel oben ist **kein Nachtblau**, obwohl das zum tiefen Stand
/// passte: In dieser Ansicht sieht man vom Himmel nur einen schmalen
/// Streifen ganz oben, und ein dunkelblauer Streifen über einer golden
/// beleuchteten Landschaft las sich wie zwei verschiedene Bilder. Am
/// gerenderten Bild entschieden.
const Lichtstimmung stimmungAbend = Lichtstimmung(
  zeit: Tageszeit.abend,
  sonne: (x: -0.684, y: 0.664, z: 0.302),
  grundlicht: 0.58,
  richtungslicht: 0.42,
  untergrenze: 0.38,
  lichtfarbe: Color(0xFFFFD09C),
  himmelOben: Color(0xFF7C7FA8),
  himmelUnten: Color(0xFFF09A4E),
  dunst: Color(0xFFE0A070),
);

/// Blaue Stunde – die Sonne ist weg, das Licht kommt vom Himmel.
///
/// Deshalb **weniger** Richtungslicht und nicht mehr: Ohne direkte Sonne
/// gibt es keine harten Schatten. Wer hier das Relief hochzöge, malte
/// eine Mittagsszene in Blau.
const Lichtstimmung stimmungBlaueStunde = Lichtstimmung(
  zeit: Tageszeit.blaueStunde,
  sonne: (x: -0.573, y: 0.573, z: 0.586),
  grundlicht: 0.70,
  richtungslicht: 0.30,
  untergrenze: 0.46,
  lichtfarbe: Color(0xFFA8B6DC),
  himmelOben: Color(0xFF16233F),
  himmelUnten: Color(0xFF64789E),
  dunst: Color(0xFF5B6E94),
);

/// In der Reihenfolge des Tages – so steht sie auch im Menü.
const List<Lichtstimmung> lichtstimmungen = [
  stimmungMorgen,
  stimmungMittag,
  stimmungAbend,
  stimmungBlaueStunde,
];

/// Die Stimmung zu einer Tageszeit.
Lichtstimmung stimmungFuer(Tageszeit zeit) =>
    lichtstimmungen.firstWhere((s) => s.zeit == zeit,
        orElse: () => stimmungMittag);

/// Die Tageszeit zu einer gemerkten Nummer.
///
/// Eine Nummer ausserhalb der Reihe fällt auf die Vorgabe zurück, statt
/// den Bildschirm zu verhindern – dieselbe Regel wie beim Kartenstil.
Tageszeit tageszeit(int nr) => nr >= 0 && nr < Tageszeit.values.length
    ? Tageszeit.values[nr]
    : lichtstimmungVorgabe;
