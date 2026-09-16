/// Die Spalten der Listenansicht: welche es gibt, wie breit sie sind und
/// wie sich beides merken lässt.
///
/// **Warum die Liste vorher keine Spalten hatte, sondern Abschnitte.** Sie
/// zeigte fünf feste Angaben, deren Sichtbarkeit allein an der
/// Fensterbreite hing (620 Punkte für die Kamera, 860 für die Belichtung,
/// 1040 für die Bewertung). Wer nach dem Objektiv suchte, fand es
/// nirgends; wer die Kamera nicht brauchte, wurde sie nicht los; und über
/// den Spalten stand nichts, was sie benennt.
///
/// Ohne Oberfläche, aus demselben Grund wie bei den Kachelstufen: Die
/// Einstellung liegt in der Datenbank, und die darf keinen Baustein der
/// Oberfläche einlesen. Die Beschriftungen entstehen dort, wo alle
/// anderen auch entstehen – die Aufzählung hier bleibt sprachfrei.
library;

import 'dart:convert';

/// Was in einer Spalte steht.
///
/// Die Reihenfolge ist die Reihenfolge im Auswahlmenü und die Vorgabe
/// für die Anordnung in der Liste.
enum Listenspalte {
  dateiname,
  datum,
  kamera,
  objektiv,
  belichtung,
  bewertung,
  farbe,
  masse,
  groesse,
  art,
  ort,
}

/// Welche Spalten stehen, wenn niemand etwas eingestellt hat.
///
/// Genau die fünf, die es vorher gab – wer nichts anfasst, sieht das
/// Bisherige. Nur stehen sie jetzt unabhängig von der Fensterbreite da
/// und tragen eine Überschrift.
const List<Listenspalte> listenspaltenVorgabe = [
  Listenspalte.dateiname,
  Listenspalte.datum,
  Listenspalte.kamera,
  Listenspalte.belichtung,
  Listenspalte.bewertung,
];

/// Die Vorgabebreite je Spalte, in Punkten.
const Map<Listenspalte, double> listenspalteBreiteVorgabe = {
  Listenspalte.dateiname: 260,
  Listenspalte.datum: 150,
  Listenspalte.kamera: 180,
  Listenspalte.objektiv: 200,
  Listenspalte.belichtung: 190,
  Listenspalte.bewertung: 116,
  Listenspalte.farbe: 70,
  Listenspalte.masse: 120,
  Listenspalte.groesse: 100,
  Listenspalte.art: 90,
  Listenspalte.ort: 180,
};

/// Schmaler als das wird keine Spalte.
///
/// Unter etwa sechzig Punkten steht in jeder Spalte nur noch „…", und
/// eine Spalte, die nichts zeigt, ist keine Spalte mehr – sie abzuschalten
/// ist dann der ehrlichere Weg.
const double listenspalteMindestbreite = 60;

/// Und breiter auch nicht: Sonst schiebt ein einziges Ziehen alle
/// folgenden Spalten aus dem Bild.
const double listenspalteHoechstbreite = 600;

/// Der Zustand der Liste: welche Spalten in welcher Breite.
class Listenspaltenwahl {
  const Listenspaltenwahl({required this.spalten, required this.breiten});

  /// Die sichtbaren Spalten, in ihrer Reihenfolge.
  final List<Listenspalte> spalten;

  /// Die Breite je Spalte – auch für abgeschaltete, damit eine wieder
  /// eingeschaltete ihre alte Breite zurückbekommt.
  final Map<Listenspalte, double> breiten;

  static const vorgabe = Listenspaltenwahl(
    spalten: listenspaltenVorgabe,
    breiten: listenspalteBreiteVorgabe,
  );

  double breiteVon(Listenspalte s) =>
      breiten[s] ?? listenspalteBreiteVorgabe[s] ?? 140;

  /// Die Summe der sichtbaren Spalten – die Breite der Liste.
  double get gesamtbreite {
    var summe = 0.0;
    for (final s in spalten) {
      summe += breiteVon(s);
    }
    return summe;
  }

  bool zeigt(Listenspalte s) => spalten.contains(s);

  /// Schaltet eine Spalte an oder aus.
  ///
  /// Beim Einschalten kommt sie an ihren Platz in der Aufzählung, nicht
  /// ans Ende: Sonst hinge die Anordnung der Liste davon ab, in welcher
  /// Reihenfolge man die Häkchen gesetzt hat.
  Listenspaltenwahl umgeschaltet(Listenspalte s) {
    if (spalten.contains(s)) {
      // Die letzte Spalte bleibt: Eine Liste ohne jede Spalte waere eine
      // leere Flaeche ohne Weg zurueck.
      if (spalten.length <= 1) return this;
      return Listenspaltenwahl(
        spalten: [for (final x in spalten) if (x != s) x],
        breiten: breiten,
      );
    }
    final neu = [
      for (final x in Listenspalte.values)
        if (x == s || spalten.contains(x)) x
    ];
    return Listenspaltenwahl(spalten: neu, breiten: breiten);
  }

  Listenspaltenwahl mitBreite(Listenspalte s, double breite) =>
      Listenspaltenwahl(
        spalten: spalten,
        breiten: {
          ...breiten,
          s: breite.clamp(listenspalteMindestbreite, listenspalteHoechstbreite),
        },
      );

  /// Als Text für die Einstellungsspalte.
  ///
  /// Als Namen und nicht als Zahlen: Eine Aufzählung, in der später eine
  /// Spalte dazwischenrutscht, würde sonst alle gemerkten Wahlen
  /// verschieben.
  String alsText() => jsonEncode({
        'spalten': [for (final s in spalten) s.name],
        'breiten': {
          for (final e in breiten.entries) e.key.name: e.value,
        },
      });

  /// Liest zurück, was [alsText] geschrieben hat.
  ///
  /// Jeder Fehler endet in der Vorgabe: eine unlesbare Einstellung darf
  /// den Bildschirm nicht verhindern. Namen, die es nicht mehr gibt,
  /// fallen still weg – dieselbe Regel wie bei der Kartenansicht.
  static Listenspaltenwahl ausText(String? text) {
    if (text == null || text.isEmpty) return vorgabe;
    try {
      final roh = jsonDecode(text);
      if (roh is! Map) return vorgabe;
      final spalten = <Listenspalte>[];
      for (final name in (roh['spalten'] as List? ?? const [])) {
        final s = _nachName('$name');
        if (s != null && !spalten.contains(s)) spalten.add(s);
      }
      if (spalten.isEmpty) return vorgabe;
      final breiten = <Listenspalte, double>{...listenspalteBreiteVorgabe};
      final rohBreiten = roh['breiten'];
      if (rohBreiten is Map) {
        for (final e in rohBreiten.entries) {
          final s = _nachName('${e.key}');
          final b = e.value;
          if (s != null && b is num) {
            breiten[s] = b.toDouble().clamp(
                listenspalteMindestbreite, listenspalteHoechstbreite);
          }
        }
      }
      return Listenspaltenwahl(spalten: spalten, breiten: breiten);
    } catch (_) {
      return vorgabe;
    }
  }

  static Listenspalte? _nachName(String name) {
    for (final s in Listenspalte.values) {
      if (s.name == name) return s;
    }
    return null;
  }
}
