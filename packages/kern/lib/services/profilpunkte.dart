/// Das Höhenprofil einer Spur in Zahlen – für Rechner, Handy und Server
/// gleich.
library;

import 'reverse_geocoder.dart';

/// Ein Punkt des Höhenprofils: wie weit gelaufen, wie hoch – und
/// welcher Punkt der Spur es war.
///
/// Die [index]-Angabe ist der Grund, warum ein Zeigen auf das Profil
/// eine Marke auf der Karte setzen kann: Ohne sie müsste man die Strecke
/// rückwärts suchen und dabei Kommazahlen vergleichen.
typedef Profilpunkt = ({double km, double hoehe, int index});

/// Rechnet die Punkte einer Spur auf Streckenmarken um.
///
/// **Die Waagerechte ist die Strecke, nicht die Zeit.** Über der Zeit
/// aufgetragen wird jede Rast eine Ebene und jeder Abstieg eine Wand –
/// man sähe, wie lange man wo war, aber nicht, wie der Weg aussah.
///
/// Punkte ohne Höhe fallen heraus, **nachdem** ihre Strecke gezählt
/// wurde: Ein Loch in den Höhenangaben ist kein Loch im Weg.
List<Profilpunkt> profilpunkte(
  List<({double breite, double laenge, double? hoehe})> punkte,
) {
  final ergebnis = <Profilpunkt>[];
  var strecke = 0.0;
  for (var i = 0; i < punkte.length; i++) {
    if (i > 0) {
      strecke += ReverseGeocoder.haversineKm(
        punkte[i - 1].breite,
        punkte[i - 1].laenge,
        punkte[i].breite,
        punkte[i].laenge,
      );
    }
    final h = punkte[i].hoehe;
    if (h != null) ergebnis.add((km: strecke, hoehe: h, index: i));
  }
  return ergebnis;
}
