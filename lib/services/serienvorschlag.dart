/// Die Serienvorschläge – gemeinsam für den Bildschirm, der sie zeigt, und
/// die Werkzeugliste, die ihre Zahl nennt.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;

import '../db/database.dart';
import 'embedding_similarity.dart';

/// Der Schlüssel eines Vorschlags: die Kennung seiner ersten Aufnahme.
///
/// Dieselbe Bildung wie bei Reise- und Aktivitätsvorschlägen. Sortiert,
/// damit derselbe Vorschlag bei jedem Lauf denselben Schlüssel bekommt –
/// die Reihenfolge, in der die Gruppenbildung ihre Mitglieder zurückgibt,
/// ist nicht zugesichert.
String serienschluessel(List<AssetData> gruppe) =>
    ([for (final a in gruppe) a.id]..sort()).first;

/// Sucht Serien, die noch keine sind.
///
/// **Was hier alles nicht mehr vorkommt.** Bereits gestapelte Aufnahmen
/// (sonst fände der nächste Lauf dieselben Gruppen wieder – aus der
/// Einbettungstabelle verschwinden sie ja nicht) und abgelehnte Vorschläge.
///
/// An der echten Bibliothek gemessen (6930 Einbettungen): 286 brauchbare
/// Gruppen mit 778 Aufnahmen in 240 ms, bei der eingestellten Ähnlichkeit
/// von 0,92 und höchstens 30 Sekunden Abstand. Die Erkennung war nie das
/// Problem – es gab bis Fassung 62 nur keine Stelle, die die Zahl nannte.
Future<List<List<AssetData>>> serienvorschlaege(
  AppDatabase db,
  Map<String, Float32List> alleEinbettungen,
) async {
  final gestapelt = await db.bereitsGestapelt();
  final verworfen = await db.verworfeneSerienvorschlaege();

  final einbettungen = <String, Float32List>{
    for (final e in alleEinbettungen.entries)
      if (!gestapelt.contains(e.key)) e.key: e.value,
  };
  if (einbettungen.isEmpty) return const [];

  final bekannt = await db.assetsByIds(einbettungen.keys.toList());

  // **Geschätzte Daten fliegen hier raus.** Eine Serie ist über ihren
  // zeitlichen Abstand definiert – höchstens 30 Sekunden. Aufnahmen, deren
  // Zeitstempel aus dem Dateisystem stammt, tragen alle denselben, und
  // damit ist der Abstand null: Sie erfüllen die Bedingung nicht, weil sie
  // zusammengehören, sondern weil niemand ihre Zeit kennt.
  //
  // Genau so ist es passiert. In der 6. Vergleichsauflage stand eine
  // „Gruppe" mit 943 Mitgliedern in der Zählung – alle 943 lagen auf
  // demselben erfundenen Zeitpunkt. Damals wurde sie über eine
  // Plausibilitätsgrenze aussortiert; jetzt kommt sie gar nicht mehr
  // zustande.
  final zeiten = {
    for (final a in bekannt)
      if (!a.datumGeschaetzt) a.id: a.fileCreatedAt,
  };

  final kennungen = await compute(
    findBurstGroups,
    BurstSearchParams(einbettungen, zeiten),
  );

  // **Eine Abfrage fuer alle Gruppen, nicht eine je Gruppe.** Die
  // Datenbank laeuft auf einem eigenen Isolate; jede Abfrage ist ein
  // Hin- und Rueckweg ueber die Isolate-Grenze, und davon gab es hier so
  // viele wie Gruppen. An der gewachsenen Bibliothek gemessen, 324
  // Gruppen mit 1050 Aufnahmen:
  //
  //   eine assetsByIds je Gruppe        52,2 ms
  //   eine Abfrage, dann verteilen      12,6 ms
  final alleKennungen = <String>{for (final liste in kennungen) ...liste};
  final geladen = await db.assetsByIds(alleKennungen.toList());
  final nachKennung = {for (final a in geladen) a.id: a};

  final gruppen = <List<AssetData>>[];
  for (final liste in kennungen) {
    final aufnahmen = [
      for (final id in liste)
        if (nachKennung[id] != null) nachKennung[id]!
    ];
    if (aufnahmen.length < 2) continue;
    if (verworfen.contains(serienschluessel(aufnahmen))) continue;
    gruppen.add(aufnahmen);
  }
  return gruppen;
}
