/// Wischen oder Kneifen – für Karte und Landschaft gleich.
library;

/// Ab welcher Abweichung von 1 eine Geste als Kneifen gilt.
///
/// Ein echtes Trackpad schickt beim Zweifinger-Kneifen dieselbe Art
/// Ereignis wie beim Wischen, nur mit einem Skalenwert. Das kann
/// flutter_map bereits – dort darf nicht dazwischengefunkt werden.
const double wischKneifSchwelle = 0.01;

/// Ob diese Geste ein Wischen ist und kein Kneifen.
bool istWischen(double skala) => (skala - 1).abs() <= wischKneifSchwelle;
