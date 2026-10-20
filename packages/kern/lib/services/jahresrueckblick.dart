/// **Ein Jahr in Zahlen und Bildern.**
///
/// Google zeigt am Jahresende einen „Recap", Apple einen Jahresrückblick.
/// Die Bausteine liegen hier alle schon vor – Aufnahmen mit Datum, Ort,
/// Bewertung und Schärfe, erkannte Personen, bestätigte Reisen. Es fehlte
/// die Seite, die sie für ein Jahr zusammenstellt.
///
/// Rein und ohne Datenbankklassen: Welche Fotos die „besten" sind, ist
/// eine Regel, und die soll sich prüfen lassen.
library;

import 'dart:math' as math;

/// Eine Aufnahme, so weit sie hier gebraucht wird.
typedef Jahresaufnahme = ({
  String id,
  DateTime wann,
  bool video,
  bool favorit,
  int bewertung,
  double? schaerfe,
  String? land,
  String? ort,

  /// Das Datum ist aus dem Dateizeitstempel geraten. Solche Aufnahmen
  /// zählen mit, zeigen aber keinen Tag an und kommen nicht in die
  /// Auswahl – ein falsch datiertes Foto wäre im Rückblick auf das
  /// falsche Jahr eine Behauptung.
  bool datumGeraten,
});

/// Was über ein Jahr zu sagen ist.
class Jahreszahlen {
  final int fotos;
  final int videos;

  /// An wie vielen verschiedenen Tagen fotografiert wurde.
  final int tage;

  final Set<String> laender;
  final Set<String> orte;

  /// Aufnahmen je Monat, Januar zuerst.
  final List<int> jeMonat;

  const Jahreszahlen({
    required this.fotos,
    required this.videos,
    required this.tage,
    required this.laender,
    required this.orte,
    required this.jeMonat,
  });

  /// Der Monat mit den meisten Aufnahmen (1 bis 12), oder `null`.
  int? get staerksterMonat {
    var bester = -1, anzahl = 0;
    for (var m = 0; m < 12; m++) {
      if (jeMonat[m] > anzahl) {
        anzahl = jeMonat[m];
        bester = m;
      }
    }
    return bester < 0 ? null : bester + 1;
  }
}

/// Zählt [aufnahmen] eines Jahres.
Jahreszahlen jahreszahlen(Iterable<Jahresaufnahme> aufnahmen) {
  var fotos = 0, videos = 0;
  final tage = <int>{};
  final laender = <String>{}, orte = <String>{};
  final jeMonat = List<int>.filled(12, 0);
  for (final a in aufnahmen) {
    a.video ? videos++ : fotos++;
    jeMonat[a.wann.month - 1]++;
    if (!a.datumGeraten) {
      tage.add(a.wann.year * 1000 + _tagImJahr(a.wann));
    }
    if (a.land case final l? when l.isNotEmpty) laender.add(l);
    if (a.ort case final o? when o.isNotEmpty) orte.add(o);
  }
  return Jahreszahlen(
    fotos: fotos,
    videos: videos,
    tage: tage.length,
    laender: laender,
    orte: orte,
    jeMonat: jeMonat,
  );
}

/// Wie viele Fotos die Auswahl höchstens hat.
const jahresauswahlGroesse = 24;

/// Die besten Fotos eines Jahres, nach Datum geordnet.
///
/// **Erst über das Jahr verteilt, dann nach Güte.** Nach Güte allein käme
/// der eine Urlaub mit den vielen Favoriten zwölfmal vor und der Rest des
/// Jahres gar nicht. Deshalb bekommt zuerst jeder Monat, in dem
/// fotografiert wurde, sein bestes Foto; der restliche Platz geht nach
/// Güte. Güte heisst: Favorit, dann Sterne, dann Schärfe.
///
/// Videos und Fotos mit geratenem Datum kommen nicht hinein.
List<String> jahresauswahl(
  Iterable<Jahresaufnahme> aufnahmen, {
  int groesse = jahresauswahlGroesse,
}) {
  final kandidaten = [
    for (final a in aufnahmen)
      if (!a.video && !a.datumGeraten) a,
  ];
  if (kandidaten.isEmpty) return const [];
  // Die Schärfe nur als Abstufung innerhalb gleicher Sterne: auf 0..1
  // gebracht über den grössten Wert des Jahres.
  final hoechsteSchaerfe = kandidaten.fold<double>(
    0,
    (m, a) => math.max(m, a.schaerfe ?? 0),
  );
  double guete(Jahresaufnahme a) =>
      (a.favorit ? 10 : 0) +
      a.bewertung +
      (hoechsteSchaerfe > 0 ? (a.schaerfe ?? 0) / hoechsteSchaerfe : 0);
  int nachGuete(Jahresaufnahme a, Jahresaufnahme b) {
    final g = guete(b).compareTo(guete(a));
    return g != 0 ? g : a.wann.compareTo(b.wann);
  }

  final gewaehlt = <String>{};
  final jeMonat = <int, List<Jahresaufnahme>>{};
  for (final a in kandidaten) {
    jeMonat.putIfAbsent(a.wann.month, () => []).add(a);
  }
  for (final monat in jeMonat.keys.toList()..sort()) {
    if (gewaehlt.length >= groesse) break;
    final liste = jeMonat[monat]!..sort(nachGuete);
    gewaehlt.add(liste.first.id);
  }
  for (final a in [...kandidaten]..sort(nachGuete)) {
    if (gewaehlt.length >= groesse) break;
    gewaehlt.add(a.id);
  }
  final nachId = {for (final a in kandidaten) a.id: a};
  return gewaehlt.toList()
    ..sort((a, b) => nachId[a]!.wann.compareTo(nachId[b]!.wann));
}

int _tagImJahr(DateTime d) =>
    DateTime(d.year, d.month, d.day).difference(DateTime(d.year)).inDays;
