/// Was an einem Ort war – für die Ortsansicht.
///
/// **Zwei Wünsche, eine Rechnung.** „Ein Klick auf ein Land soll seine
/// Regionen zeigen" und „ein Klick auf einen Pin soll die Fotos zeigen"
/// enden bei derselben Frage: *Was war hier?* Beantwortet wird sie für
/// Land, Region und Ort auf dieselbe Weise, nur mit anderer Ebene.
///
/// Rein und ohne Datenbankklassen. An der fertigen Liste sieht man nicht
/// mehr, ob „Bayern" einmal oder zweimal gezählt wurde.
library;

import 'reisefortschritt.dart'
    show Besuchsangabe, Markenart, Markeneintrag, ortsmarkeZerlegen;

/// Welche Ebene eine Ortsansicht zeigt.
enum Ortsebene { land, region, ort }

/// Ein Eintrag der nächsten Ebene – eine Region unter einem Land, ein Ort
/// unter einer Region.
typedef Unterort = ({
  /// Der Schlüssel, unter dem eine Marke dazu steht: der GeoNames-Code
  /// („DE.02") für eine Region, „Land|Region|Ort" für einen Ort. Beides
  /// so, wie die Tabelle `Ortsmarken` es führt – ein zweiter Schlüssel
  /// für dieselbe Sache wäre eine zweite Wahrheit.
  String schluessel,
  String name,
  int aufnahmen,
  Markenart? marke,

  /// Belegt durch etwas, das eine Ebene TIEFER liegt: eine von Hand
  /// markierte Stadt färbt ihr Bundesland.
  ///
  /// Getrennt von [marke] und nicht in sie hineingerechnet, denn beides
  /// bedeutet Verschiedenes: [marke] ist der Haken, den jemand an
  /// **dieser** Zeile gesetzt hat, und nur er lässt sich hier wieder
  /// wegnehmen. Wer die Ableitung als eigene Marke ausgäbe, böte einen
  /// Haken zum Entfernen an, den es gar nicht gibt.
  bool abgeleitet,
});

extension UnterortStand on Unterort {
  /// Belegt heisst: Es gibt Fotos, es steht ein Haken von Hand, oder eine
  /// Ebene tiefer steht einer. „Geplant" zählt nicht – wie überall in
  /// dieser App.
  bool get besucht =>
      aufnahmen > 0 || marke == Markenart.besucht || abgeleitet;
}

/// Was über einen Ort bekannt ist.
class Ortsuebersicht {
  final Ortsebene ebene;
  final String schluessel;
  final String name;

  /// Verortete Aufnahmen von hier – bei einem Land alle des Landes.
  final int aufnahmen;

  /// Die eigene Marke, falls eine gesetzt ist.
  final Markenart? marke;

  /// Die nächste Ebene, besuchte zuerst.
  ///
  /// **Auch das Unbesuchte steht drin.** Eine Liste, die nur zeigt, wo man
  /// war, ist ein Spiegel der eigenen Fotos; erst mit den übrigen wird sie
  /// eine Landkarte. Bei einem Ort ist sie leer – darunter kommt nichts
  /// mehr.
  final List<Unterort> unterorte;

  const Ortsuebersicht({
    required this.ebene,
    required this.schluessel,
    required this.name,
    required this.aufnahmen,
    required this.marke,
    required this.unterorte,
  });

  int get unterorteGesamt => unterorte.length;
  int get unterorteBesucht => unterorte.where((u) => u.besucht).length;

  /// Ob für einen Besuch überhaupt etwas spricht.
  bool get besucht =>
      aufnahmen > 0 || unterorteBesucht > 0 || marke == Markenart.besucht;
}

/// Stellt zusammen, was über einen Ort bekannt ist.
///
/// [angaben] sind **alle** Zeilen aus `besuchteOrte()`; eingegrenzt wird
/// hier. Der Aufrufer soll nicht zweimal filtern müssen und dabei eine
/// andere Regel anwenden als diese Funktion.
///
/// [nachIso] übersetzt den Ländernamen der Umkehr-Geokodierung in den
/// Code, [regionscodes] den Regionsnamen („DE|Hamburg" nach „DE.04").
///
/// [bekannteUnterorte] ist das, was der Datensatz kennt – alle Regionen
/// eines Landes bzw. alle Orte einer Region. Leer ist zulässig: 24 der
/// 252 Länder haben keine verzeichnete Region.
Ortsuebersicht ortsuebersicht({
  required Ortsebene ebene,
  required String schluessel,
  required String name,
  required Iterable<Besuchsangabe> angaben,
  required Map<String, String> nachIso,
  required Map<String, String> regionscodes,
  Iterable<({String schluessel, String name})> bekannteUnterorte = const [],
  Iterable<Markeneintrag> marken = const [],
}) {
  final markeJeSchluessel = <String, Markenart>{};
  for (final m in marken) {
    markeJeSchluessel['${m.art} ${m.schluessel}'] = m.wert;
  }
  Markenart? markeFuer(String art, String s) => markeJeSchluessel['$art $s'];

  var eigene = 0;
  final unteraufnahmen = <String, int>{};
  final unternamen = <String, String>{};

  for (final a in angaben) {
    final land = a.land;
    if (land == null || land.isEmpty) continue;
    final iso = nachIso[land];
    if (iso == null) continue;
    final region = a.region;
    final regionscode = (region == null || region.isEmpty)
        ? null
        : regionscodes['$iso|$region'];
    final ort = a.ort;
    final ortsschluessel =
        (ort == null || ort.isEmpty) ? null : '$land|${region ?? ''}|$ort';

    switch (ebene) {
      case Ortsebene.land:
        if (iso != schluessel) continue;
        eigene += a.anzahl;
        // Regionen ohne auflösbaren Code fallen weg – sie hätten keinen
        // Schlüssel, unter dem eine Marke stehen könnte, und wären damit
        // eine Zeile, die man ansieht und nicht anklicken kann.
        if (regionscode != null) {
          unteraufnahmen[regionscode] =
              (unteraufnahmen[regionscode] ?? 0) + a.anzahl;
          unternamen[regionscode] = region!;
        }
      case Ortsebene.region:
        if (regionscode != schluessel) continue;
        eigene += a.anzahl;
        if (ortsschluessel != null) {
          unteraufnahmen[ortsschluessel] =
              (unteraufnahmen[ortsschluessel] ?? 0) + a.anzahl;
          unternamen[ortsschluessel] = ort!;
        }
      case Ortsebene.ort:
        if (ortsschluessel != schluessel) continue;
        eigene += a.anzahl;
    }
  }

  // Was eine Ebene tiefer steht, färbt die Zeile darüber. Ohne das galt
  // eine von Hand markierte Stadt in der Regionenübersicht als nirgends,
  // während die Länderliste dieselbe Marke längst mitzählte – zwei
  // Bildschirme, dieselben Daten, gegenteilige Auskunft.
  //
  // Nur bei den Regionen: Unter einem Ort kommt nichts mehr.
  final abgeleitet = <String>{};
  if (ebene == Ortsebene.land) {
    for (final m in marken) {
      if (m.art != 'ort' || m.wert != Markenart.besucht) continue;
      final teile = ortsmarkeZerlegen(m.schluessel, nachIso);
      if (teile == null || teile.iso != schluessel || teile.region.isEmpty) {
        continue;
      }
      // Ohne auflösbaren Code gibt es keine Zeile, die sich färben liesse
      // – die Liste führt Regionen unter ihrem Code.
      final code = regionscodes['${teile.iso}|${teile.region}'];
      if (code != null) abgeleitet.add(code);
    }
  }

  final art = switch (ebene) {
    Ortsebene.land => 'land',
    Ortsebene.region => 'region',
    Ortsebene.ort => 'ort',
  };
  final unterart = ebene == Ortsebene.land ? 'region' : 'ort';

  // Ein von Hand markierter Ort gehört ebenso in die Liste. `orteIn`
  // deckelt bei den sechzig grössten – auf der Weltkarte lässt sich aber
  // jeder Fleck markieren, und die nächstgelegene Stadt ist oft ein Dorf.
  // Ohne diese Zeile gäbe es eine Marke in der Datenbank, zu der keine
  // Zeile existiert: unsichtbar, und deshalb auch nie wieder wegzunehmen.
  //
  // Auch geplante gehören dazu, gerade sie: Ein Vorhaben, das man nicht
  // mehr findet, kann man nicht abhaken.
  final markierte = <String, String>{};
  if (ebene == Ortsebene.region) {
    for (final m in marken) {
      if (m.art != 'ort') continue;
      final teile = ortsmarkeZerlegen(m.schluessel, nachIso);
      if (teile == null) continue;
      if (regionscodes['${teile.iso}|${teile.region}'] != schluessel) continue;
      markierte[m.schluessel] = teile.ort;
    }
  }

  // Was der Datensatz kennt, und dazu alles, was die Fotos nennen: Ein
  // Ort, den `cities1000` nicht führt, aber ein Foto belegt, muss
  // trotzdem in der Liste stehen.
  final alle = <String, String>{
    for (final u in bekannteUnterorte) u.schluessel: u.name,
    ...markierte,
    ...unternamen,
  };

  final unterorte = <Unterort>[
    for (final e in alle.entries)
      (
        schluessel: e.key,
        name: e.value,
        aufnahmen: unteraufnahmen[e.key] ?? 0,
        marke: markeFuer(unterart, e.key),
        abgeleitet: abgeleitet.contains(e.key),
      ),
  ];

  // Besuchtes zuerst, darin das mit den meisten Aufnahmen; alles Übrige
  // alphabetisch. Wer nachsehen will, wo er war, findet es oben; wer
  // sucht, was noch fehlt, findet es an einer Stelle statt verstreut.
  unterorte.sort((a, b) {
    if (a.besucht != b.besucht) return a.besucht ? -1 : 1;
    if (a.aufnahmen != b.aufnahmen) return b.aufnahmen.compareTo(a.aufnahmen);
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

  return Ortsuebersicht(
    ebene: ebene,
    schluessel: schluessel,
    name: name,
    aufnahmen: eigene,
    marke: markeFuer(art, schluessel),
    unterorte: unterorte,
  );
}
