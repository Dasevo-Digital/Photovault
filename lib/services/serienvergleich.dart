/// Die Daten für den Serienvergleich – eine Spalte je Aufnahme.
///
/// Reine Abfrage ohne Oberfläche, damit sich prüfen lässt, was
/// nebeneinandergestellt wird, ohne einen Pixel zu zeichnen.
library;

import '../db/database.dart';

/// Ein Gesicht in einer Spalte.
class Serienkopf {
  /// Der gespeicherte 160×160-Ausschnitt, relativ zur Bibliothek.
  final String? ausschnitt;

  /// Der Name, wenn die Person benannt ist.
  final String? name;

  /// Schärfe des Ausschnitts (siehe `gesichtsschaerfe`), oder `null`.
  final double? schaerfe;

  /// Wahrscheinlichkeit „Augen offen", oder `null`.
  ///
  /// Steht bewusst nur hier und nicht mehr in der Sichtungsleiste: Neben
  /// dem Gesicht lässt sich eine falsche Zahl sehen und übergehen, ohne
  /// Bild nicht.
  final double? augenOffen;

  /// Wie gross der Kopf im Bild ist (Anteil der Bildbreite) – die Spalten
  /// werden danach sortiert, damit dieselbe Person in allen Spalten
  /// ungefähr auf derselben Höhe steht.
  final double breite;

  const Serienkopf({
    required this.ausschnitt,
    required this.name,
    required this.schaerfe,
    required this.augenOffen,
    required this.breite,
  });
}

/// Eine Aufnahme der Serie samt ihren Gesichtern.
class Serienspalte {
  final AssetData asset;
  final List<Serienkopf> gesichter;

  const Serienspalte({required this.asset, required this.gesichter});

  /// Die Schärfe des besten Gesichts – oder `null`, wenn keines gemessen
  /// ist.
  ///
  /// Das schärfste zählt, nicht der Durchschnitt: Auf einem Gruppenbild ist
  /// hinten fast immer jemand weich, und das ist kein Grund, die Aufnahme
  /// aussortieren zu wollen. Dieselbe Regel wie in der Sichtung.
  double? get besteSchaerfe {
    double? beste;
    for (final g in gesichter) {
      final s = g.schaerfe;
      if (s == null) continue;
      if (beste == null || s > beste) beste = s;
    }
    return beste;
  }

  /// Kennung der Aufnahme – für den Vergleich „ist das die schärfste
  /// Spalte", ohne die Spalten selbst gleichsetzen zu müssen.
  String get schaerfsteId => asset.id;
}

/// Baut die Spalten zu einer Serie.
///
/// Die Gesichter jeder Spalte stehen **nach Grösse sortiert**, das grösste
/// oben. Über eine Serie hinweg ist das die stabilste Anordnung, die ohne
/// Wiedererkennung zu haben ist: Wer nah an der Kamera stand, steht in
/// jeder Spalte oben. Nach Kennung oder Erkennungsreihenfolge sortiert
/// sprängen dieselben Köpfe von Spalte zu Spalte.
Future<List<Serienspalte>> serienspalten(
    AppDatabase db, List<AssetData> serie) async {
  final namen = {for (final p in await db.allePersonen()) p.id: p.name};
  final spalten = <Serienspalte>[];
  for (final asset in serie) {
    final gesichter = await db.facesForAsset(asset.id);
    final koepfe = [
      for (final g in gesichter)
        if (!g.isIgnored)
          Serienkopf(
            ausschnitt: g.cropRelativePath,
            name: g.personId == null ? null : namen[g.personId],
            schaerfe: g.schaerfe,
            augenOffen: g.eyeOpenScore,
            breite: g.boxW,
          ),
    ]..sort((a, b) => b.breite.compareTo(a.breite));
    spalten.add(Serienspalte(asset: asset, gesichter: koepfe));
  }
  return spalten;
}
