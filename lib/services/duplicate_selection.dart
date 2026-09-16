/// Entscheidet, welches Foto einer Duplikatgruppe behalten wird.
///
/// Reine Funktionen ohne Datenbank- oder UI-Zugriff, damit sich die Regeln
/// ohne laufende App prüfen lassen – bei einer Funktion, die Fotos in den
/// Papierkorb verschiebt, ist das keine Kür.
library;

import '../db/database.dart';

/// Rangfolge beim Behalten, wichtigstes Kriterium zuerst:
///
/// 1. **Favorit** – eine bewusste Nutzerentscheidung wiegt schwerer als
///    jede gemessene Qualität.
/// 2. **Höhere Bewertung** – ebenfalls bewusst vergeben.
/// 3. **Schärfe** (siehe blur_detection.dart) – das eigentliche
///    Qualitätsmerkmal bei sonst gleichwertigen Aufnahmen.
/// 4. **Auflösung** – mehr Pixel bei gleicher Schärfe.
/// 5. **Früher aufgenommen** – als letzter, stabiler Tiebreaker, damit die
///    Auswahl bei identischen Werten reproduzierbar bleibt und nicht von
///    der Sortierreihenfolge abhängt.
AssetData besterDerGruppe(List<AssetData> gruppe) {
  final sortiert = [...gruppe]..sort(_vergleiche);
  return sortiert.first;
}

int _vergleiche(AssetData a, AssetData b) {
  if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
  if (a.rating != b.rating) return b.rating.compareTo(a.rating);

  final sa = a.sharpnessScore, sb = b.sharpnessScore;
  if (sa != sb) {
    // Fehlender Score zählt als schlechter, nicht als bester.
    if (sa == null) return 1;
    if (sb == null) return -1;
    return sb.compareTo(sa);
  }

  final pa = (a.widthPx ?? 0) * (a.heightPx ?? 0);
  final pb = (b.widthPx ?? 0) * (b.heightPx ?? 0);
  if (pa != pb) return pb.compareTo(pa);

  return a.fileCreatedAt.compareTo(b.fileCreatedAt);
}

/// Was in einer Gruppe in den Papierkorb wandern würde.
///
/// Gibt eine **leere** Liste zurück, sobald die Gruppe mehr als ein Foto
/// enthält, das der Nutzer ausdrücklich ausgezeichnet hat (Favorit oder
/// Bewertung): Dann ist nicht entscheidbar, welches davon überflüssig ist,
/// und automatisches Löschen wäre eine Anmaßung. Solche Gruppen bleiben
/// unangetastet und müssen von Hand durchgesehen werden.
List<AssetData> zuLoeschendeDerGruppe(List<AssetData> gruppe) {
  if (gruppe.length < 2) return const [];

  final ausgezeichnet = gruppe.where((a) => a.isFavorite || a.rating > 0).length;
  if (ausgezeichnet > 1) return const [];

  final behalten = besterDerGruppe(gruppe);
  return gruppe.where((a) => a.id != behalten.id).toList();
}

/// Ergebnis über alle Gruppen hinweg – für die Vorschau vor dem Löschen.
class LoeschVorschau {
  /// Fotos, die in den Papierkorb wandern würden.
  final List<AssetData> zuLoeschen;

  /// Gruppen, die bewusst übersprungen werden, weil mehrere Fotos darin
  /// ausgezeichnet sind (siehe [zuLoeschendeDerGruppe]).
  final int uebersprungeneGruppen;

  const LoeschVorschau({required this.zuLoeschen, required this.uebersprungeneGruppen});
}

LoeschVorschau berechneLoeschVorschau(List<List<AssetData>> gruppen) {
  final zuLoeschen = <AssetData>[];
  var uebersprungen = 0;
  for (final g in gruppen) {
    final weg = zuLoeschendeDerGruppe(g);
    if (weg.isEmpty && g.length >= 2) {
      uebersprungen++;
      continue;
    }
    zuLoeschen.addAll(weg);
  }
  return LoeschVorschau(zuLoeschen: zuLoeschen, uebersprungeneGruppen: uebersprungen);
}
