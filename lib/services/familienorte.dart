/// Die Einfärbung der Familienkarte.
///
/// Ein Foto kann mehrere Verwandte zeigen – Urgroßmutter und Enkel auf
/// demselben Bild. Welche Farbe der Marker bekommt, ist deshalb eine
/// Entscheidung und keine Ablesung, und sie gehört in eine prüfbare
/// Funktion statt in den Maler.
library;

import 'verwandtschaftsgrad.dart';

/// Die vier Gruppen, nach denen die Karte einfärbt.
///
/// Nicht nach einzelnen Personen: Bei dreißig Verwandten bräuchte es
/// dreißig unterscheidbare Farben, und die gibt es nicht. Nach Richtung zu
/// gruppieren beantwortet ausserdem die Frage, um die es geht – wohin sich
/// eine Familie über die Generationen bewegt hat.
enum Ortsgruppe {
  /// Die Person selbst.
  ich,

  /// Eltern, Großeltern, Urgroßeltern …
  vorfahren,

  /// Geschwister, Cousins – die eigene Generation und ihre Seitenlinien.
  seitenlinie,

  /// Kinder, Enkel …
  nachkommen,

  /// Über Heirat verbunden.
  angeheiratet,
}

/// Ordnet einen Verwandtschaftsgrad einer Gruppe zu.
Ortsgruppe gruppeFuer(Grad grad) => switch (grad.art) {
      Gradart.selbst => Ortsgruppe.ich,
      Gradart.vorfahre || Gradart.vorfahrengeschwister => Ortsgruppe.vorfahren,
      Gradart.nachkomme || Gradart.geschwisterkind => Ortsgruppe.nachkommen,
      Gradart.geschwister || Gradart.cousin => Ortsgruppe.seitenlinie,
      _ => Ortsgruppe.angeheiratet,
    };

/// Wie eng eine Gruppe an der gewählten Person hängt – kleiner heißt
/// näher. Bestimmt, welche Farbe gewinnt, wenn mehrere Verwandte auf
/// einem Foto stehen.
int _rang(Ortsgruppe g) => switch (g) {
      Ortsgruppe.ich => 0,
      Ortsgruppe.nachkommen => 1,
      Ortsgruppe.vorfahren => 2,
      Ortsgruppe.seitenlinie => 3,
      Ortsgruppe.angeheiratet => 4,
    };

/// Die Gruppe eines Fotos, auf dem [personen] erkannt wurden.
///
/// Bei mehreren gewinnt die nächste – ein Foto mit der Urgroßmutter *und*
/// dem eigenen Kind ist in erster Linie eines vom eigenen Kind. Die
/// Alternative wäre gewesen, es zweimal zu zeichnen; dann stünden zwei
/// Marker exakt übereinander und der obere verdeckte den unteren.
///
/// `null`, wenn niemand aus der Familie darauf erkannt wurde.
Ortsgruppe? gruppeFuerFoto(Iterable<String> personen, Map<String, Grad> grade,
    {required String fokus}) {
  Ortsgruppe? beste;
  for (final id in personen) {
    Ortsgruppe? gruppe;
    if (id == fokus) {
      gruppe = Ortsgruppe.ich;
    } else {
      final grad = grade[id];
      if (grad != null) gruppe = gruppeFuer(grad);
    }
    if (gruppe == null) continue;
    if (beste == null || _rang(gruppe) < _rang(beste)) beste = gruppe;
  }
  return beste;
}
