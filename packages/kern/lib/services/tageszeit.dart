/// Die Tageszeit über der Geländeansicht als reiner Wert – ohne die
/// Farben dazu (siehe `lichtstimmung.dart`), damit die Datenbank sie
/// merken kann, ohne Flutter zu kennen.
library;

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

/// Die Tageszeit zu einer gemerkten Nummer.
///
/// Eine Nummer ausserhalb der Reihe fällt auf die Vorgabe zurück, statt
/// den Bildschirm zu verhindern – dieselbe Regel wie beim Kartenstil.
Tageszeit tageszeit(int nr) => nr >= 0 && nr < Tageszeit.values.length
    ? Tageszeit.values[nr]
    : lichtstimmungVorgabe;
