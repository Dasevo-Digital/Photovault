/// **Wer könnte das sein?**
///
/// Die Rechnung stand bisher nur in der Sammelzuordnung des Personen-Tabs,
/// fest im Bildschirm. Von den neun Stellen, die den Zuordnungs-Dialog
/// öffnen, schlugen deshalb genau zwei etwas vor – und ausgerechnet die
/// häufigen nicht: ein Gesicht im Vollbild antippen, Gesichter durchsehen,
/// das Info-Blatt. Dabei liegt die Einbettung des Gesichts dort genauso
/// daneben.
///
/// Rein und ohne Datenbankklassen, wie [Reisefortschritt] und
/// [Ortsuebersicht]: An einem Vorschlag sieht man nicht mehr, aus welcher
/// Tabelle er kam.
library;

import 'dart:typed_data';

import 'face_clustering_service.dart' show meanNormalizedEmbedding;
import 'face_engine_service.dart' show FaceEngineService;

/// Die Einbettung eines zugeordneten Gesichts, so wie sie aus der
/// Datenbank kommt.
typedef Gesichtseinbettung = ({String personId, Float32List vektor});

/// Der Mittelpunkt aller Gesichter einer Person.
typedef Personenkern = ({String personId, Float32List kern});

/// Wer vorgeschlagen wird und wie sicher.
typedef Personentreffer = ({String personId, double aehnlichkeit});


/// Fasst die Einbettungen je Person zu einem Kern zusammen.
///
/// Personen ohne eine einzige Einbettung fallen heraus – für sie lässt sich
/// nichts vergleichen, und ein Kern aus dem Nichts wäre eine erfundene
/// Behauptung.
List<Personenkern> personenkerne(Iterable<Gesichtseinbettung> einbettungen) {
  final jePerson = <String, List<Float32List>>{};
  for (final e in einbettungen) {
    jePerson.putIfAbsent(e.personId, () => []).add(e.vektor);
  }
  return [
    for (final e in jePerson.entries)
      (personId: e.key, kern: meanNormalizedEmbedding(e.value)),
  ];
}

/// Der ähnlichste Kern zu [gesicht] – aber nur, wenn er die Schwelle
/// **seiner** Person erreicht.
///
/// [schwelleFuer] liefert die persönliche Schwelle; darin steckt das
/// Gelernte. Wer bisher zu oft fälschlich vorgeschlagen wurde, braucht
/// jetzt mehr Ähnlichkeit – eine gemeinsame Schwelle für alle würde genau
/// diese Korrektur wieder einebnen.
///
/// Gibt `null` zurück, wenn nichts nahe genug ist. **Das ist der
/// Regelfall bei einem fremden Gesicht**, und es ist wichtiger, dort nichts
/// zu sagen als etwas zu raten: Ein falscher Vorschlag, den jemand
/// wegklickt, kostet mehr Zeit als gar keiner – und einer, den jemand
/// übersieht und bestätigt, kostet eine falsche Zuordnung.
Personentreffer? besterTreffer(
  Float32List gesicht,
  Iterable<Personenkern> kerne, {
  required double Function(String personId) schwelleFuer,
}) {
  String? bester;
  var beste = 0.0;
  for (final k in kerne) {
    final aehnlich = FaceEngineService.cosineSimilarity(gesicht, k.kern);
    if (aehnlich > beste) {
      beste = aehnlich;
      bester = k.personId;
    }
  }
  if (bester == null || beste < schwelleFuer(bester)) return null;
  return (personId: bester, aehnlichkeit: beste);
}
