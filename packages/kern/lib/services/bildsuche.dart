import 'dart:typed_data';

import 'clip_service.dart';
import 'videostandbilder.dart';

/// Die Rangfolge der Suche nach Bildinhalt – für den Desktop, der den
/// Suchtext selbst einbettet, und das Telefon, das ihn vom Server holt.

/// Die Kandidaten der Suche: je Aufnahme ihre Einbettung ([einzeln]), bei
/// Videos zusätzlich die ihrer weiteren Standbilder ([videos]).
///
/// **Die Schlüssel tragen die Stelle mit** (`kennung#2`), damit die
/// Rangfolge jedes Standbild einzeln bewerten kann. Es zählt das
/// **beste**, nicht das Mittel: Ein Mittelwert über verschiedene Szenen
/// wäre ein Vektor, der zu nichts mehr recht passt. Zurück auf die
/// Aufnahme kommt man über [aufnahmeAusSuchschluessel].
Map<String, Float32List> suchkandidatenAus(
  Map<String, Float32List> einzeln,
  Map<String, List<Float32List>> videos,
) {
  if (videos.isEmpty) return einzeln;
  return {
    ...einzeln,
    for (final e in videos.entries)
      for (var i = 0; i < e.value.length; i++) '${e.key}#$i': e.value[i],
  };
}

/// Die Aufnahmekennung zu einem Schlüssel aus [suchkandidatenAus].
String aufnahmeAusSuchschluessel(String schluessel) {
  final trenner = schluessel.lastIndexOf('#');
  return trenner < 0 ? schluessel : schluessel.substring(0, trenner);
}

/// Die [anzahl] Aufnahmen aus [erlaubt], die am besten zu [vektor] passen,
/// die beste zuerst.
///
/// Reihenfolge ist entscheidend: ERST auf [erlaubt] beschränken, DANN
/// ranken. Andersherum (Audit-Fund) entschied das bibliotheksweite
/// Top-200 darüber, was ein Filter überhaupt noch zu sehen bekam: Wer
/// „Sonnenuntergang“ sucht und auf ein Album mit fünf Fotos einschränkt,
/// verlor jeden Treffer, der es global nicht unter die besten 200
/// geschafft hatte.
List<String> rangfolgeDerBildsuche(
  Float32List vektor,
  Map<String, Float32List> kandidaten,
  Set<String> erlaubt, {
  int anzahl = 200,
}) {
  final zugelassen = <String, Float32List>{
    for (final e in kandidaten.entries)
      if (erlaubt.contains(aufnahmeAusSuchschluessel(e.key))) e.key: e.value,
  };
  // Etwas mehr als [anzahl]: Ein Video kann mit mehreren Standbildern in
  // der Rangfolge auftauchen, und die fallen gleich wieder zusammen.
  final rang = ClipService.rankBySimilarity(
    vektor,
    zugelassen,
    topK: anzahl * (1 + videoStandbilderHoechstens),
  );
  // Je Aufnahme zählt ihr bestes Standbild; die Rangfolge kommt
  // absteigend, das erste Auftreten ist also das beste.
  final gesehen = <String>{};
  return [
    for (final e in rang)
      if (gesehen.add(aufnahmeAusSuchschluessel(e.key)))
        aufnahmeAusSuchschluessel(e.key),
  ].take(anzahl).toList();
}
