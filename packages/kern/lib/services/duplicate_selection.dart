/// Entscheidet, welches Foto einer Duplikatgruppe behalten wird.
///
/// Reine Funktionen ohne Datenbank- oder UI-Zugriff, damit sich die Regeln
/// ohne laufende App prüfen lassen – bei einer Funktion, die Fotos in den
/// Papierkorb verschiebt, ist das keine Kür.
library;

import 'package:kern/db/database.dart';
import 'package:path/path.dart' as p;

import 'raw_formats.dart';

/// Ab wie viel mehr Pixeln eine Aufnahme als die grössere Fassung gilt.
const deutlichMehrPixel = 1.2;

/// Rangfolge beim Behalten, wichtigstes Kriterium zuerst:
///
/// 1. **Favorit** – eine bewusste Nutzerentscheidung wiegt schwerer als
///    jede gemessene Qualität.
/// 2. **Höhere Bewertung** – ebenfalls bewusst vergeben.
/// 3. **Volle Auflösung** – wer weniger als 1/[deutlichMehrPixel] der
///    grössten Fassung der Gruppe hat, ist eine verkleinerte Kopie.
/// 4. **RAW** vor jedem abgeleiteten Format bei vergleichbarer Grösse.
/// 5. **Schärfe** (siehe blur_detection.dart) – das eigentliche
///    Qualitätsmerkmal bei sonst gleichwertigen Aufnahmen.
/// 6. **Auflösung** – mehr Pixel bei gleicher Schärfe.
/// 7. **Früher aufgenommen** – als letzter, stabiler Tiebreaker, damit die
///    Auswahl bei identischen Werten reproduzierbar bleibt und nicht von
///    der Sortierreihenfolge abhängt.
///
/// **Warum die Auflösung vor der Schärfe steht (#249).** Die Schärfe ist
/// eine Kommazahl; zwei Werte sind praktisch nie gleich, und so kam die
/// Auflösung als Nächstes nie zum Zug. Eine verkleinerte oder neu kodierte
/// Kopie hat dabei eher mehr Kantenenergie als ihr Original: In einer
/// echten Bibliothek blieben zwei 3-MP-JPEGs (Schärfe 133 und 101), und
/// die 48-MP-DNGs, aus denen sie entstanden waren (90 und 71), gingen in
/// den Papierkorb.
AssetData besterDerGruppe(List<AssetData> gruppe) {
  final groesste = gruppe.map(_pixel).fold(0, (a, b) => a > b ? a : b);
  bool voll(AssetData a) => _pixel(a) * deutlichMehrPixel >= groesste;
  final sortiert = [...gruppe]..sort((a, b) => _vergleiche(a, b, voll));
  return sortiert.first;
}

int _pixel(AssetData a) => (a.widthPx ?? 0) * (a.heightPx ?? 0);

bool _istRaw(AssetData a) =>
    rawImageExtensions.contains(p.extension(a.relativePath).toLowerCase());

int _vergleiche(AssetData a, AssetData b, bool Function(AssetData) voll) {
  if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
  if (a.rating != b.rating) return b.rating.compareTo(a.rating);

  // Ein Merkmal je Aufnahme, gemessen an der ganzen Gruppe – kein Vergleich
  // zweier Grössen mit Schwelle, der von der Reihenfolge abhinge.
  final va = voll(a), vb = voll(b);
  if (va != vb) return va ? -1 : 1;
  final ra = _istRaw(a), rb = _istRaw(b);
  if (ra != rb) return ra ? -1 : 1;

  final sa = a.sharpnessScore, sb = b.sharpnessScore;
  if (sa != sb) {
    // Fehlender Score zählt als schlechter, nicht als bester.
    if (sa == null) return 1;
    if (sb == null) return -1;
    return sb.compareTo(sa);
  }

  final pa = _pixel(a), pb = _pixel(b);
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

  final ausgezeichnet = gruppe
      .where((a) => a.isFavorite || a.rating > 0)
      .length;
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

  const LoeschVorschau({
    required this.zuLoeschen,
    required this.uebersprungeneGruppen,
  });
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
  return LoeschVorschau(
    zuLoeschen: zuLoeschen,
    uebersprungeneGruppen: uebersprungen,
  );
}
