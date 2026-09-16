/// Gruppiert Fotos für die Listenansicht.
///
/// Als eigene, reine Funktion und nicht im Widget: Die Reihenfolge der
/// Gruppen ist die eigentliche Entscheidung – und die lässt sich nur so
/// prüfen, ohne einen Bildschirm aufzubauen.
library;

import '../db/database.dart';

/// Wonach die Liste gegliedert wird.
enum ListenGruppierung {
  /// Wie das Raster: ein Abschnitt je Monat, neueste zuerst.
  monat,

  /// Ein Abschnitt je Kameramodell – die Arbeitsweise, wenn man eine
  /// Reihe mit zwei Gehäusen fotografiert hat und beide getrennt
  /// durchsehen will.
  kamera,

  /// Keine Gliederung, eine durchgehende Liste.
  keine,
}

/// Ein Abschnitt der Liste.
class Assetgruppe {
  /// Bei [ListenGruppierung.monat] `jahr*100+monat`, bei
  /// [ListenGruppierung.kamera] die Modellbezeichnung, sonst leer.
  ///
  /// Unformatiert: Wie daraus „März 2026" wird, weiss nur die Oberfläche –
  /// sie kennt die Sprache.
  final String schluessel;
  final List<AssetData> assets;

  const Assetgruppe(this.schluessel, this.assets);
}

/// Die Kamerabezeichnung eines Fotos, oder `null`, wenn keine bekannt ist.
///
/// Hersteller und Modell werden nicht doppelt geschrieben – Canon steht in
/// beiden EXIF-Feldern („Canon" und „Canon EOS R10"). Dieselbe Regel wie
/// beim Namensmuster im Export.
String? kamerabezeichnung(AssetData asset) {
  final hersteller = asset.cameraMake?.trim() ?? '';
  final modell = asset.cameraModel?.trim() ?? '';
  if (modell.isEmpty && hersteller.isEmpty) return null;
  if (modell.isEmpty) return hersteller;
  if (hersteller.isEmpty) return modell;
  if (modell.toLowerCase().startsWith(hersteller.toLowerCase())) return modell;
  return '$hersteller $modell';
}

/// Gliedert [assets] nach [art].
///
/// [assets] kommt bereits nach Datum sortiert (neueste zuerst) – innerhalb
/// jeder Gruppe bleibt diese Reihenfolge erhalten, gleich wonach gruppiert
/// wird.
///
/// Bei [ListenGruppierung.kamera] stehen die Gruppen alphabetisch und die
/// Fotos ohne Kameraangabe am Ende. Nach Häufigkeit zu sortieren wäre
/// verlockend, ist aber unbrauchbar: Die Reihenfolge änderte sich dann bei
/// jedem Import, und man müsste die gesuchte Kamera jedes Mal neu suchen.
List<Assetgruppe> gruppiereAssets(List<AssetData> assets, ListenGruppierung art,
    {bool absteigend = true}) {
  if (art == ListenGruppierung.keine) {
    return assets.isEmpty ? const [] : [Assetgruppe('', assets)];
  }

  final nachSchluessel = <String, List<AssetData>>{};
  for (final asset in assets) {
    final schluessel = switch (art) {
      ListenGruppierung.monat =>
        '${asset.fileCreatedAt.year * 100 + asset.fileCreatedAt.month}',
      ListenGruppierung.kamera => kamerabezeichnung(asset) ?? '',
      ListenGruppierung.keine => '',
    };
    nachSchluessel.putIfAbsent(schluessel, () => []).add(asset);
  }

  final schluessel = nachSchluessel.keys.toList();
  switch (art) {
    case ListenGruppierung.monat:
      // In dieselbe Richtung wie die Aufnahmen darin – wie im Raster.
      schluessel.sort((a, b) => absteigend
          ? int.parse(b).compareTo(int.parse(a))
          : int.parse(a).compareTo(int.parse(b)));
    case ListenGruppierung.kamera:
      schluessel.sort((a, b) {
        // Ohne Kameraangabe immer ans Ende, unabhängig vom Alphabet.
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    case ListenGruppierung.keine:
      break;
  }

  return [for (final s in schluessel) Assetgruppe(s, nachSchluessel[s]!)];
}
