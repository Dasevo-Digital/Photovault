/// GPX einlesen – und Aufnahmen nachträglich verorten.
///
/// Der eigentliche Gewinn liegt nicht bei den Wanderungen, sondern hier:
/// Eine GPX-Spur trägt Zeitstempel. Damit lassen sich Fotos aus Kameras
/// **ohne** GPS nachträglich verorten, indem man Aufnahmezeit gegen Spur
/// legt. An der echten Bibliothek gemessen tragen nur 1092 von 7988
/// Aufnahmen eine Koordinate – 86 % sind für Karte, Globus und
/// Reiseerkennung unsichtbar.
///
/// Reine Funktionen, ohne Datenbank und ohne Dateizugriff: Ob ein Foto
/// an der richtigen Stelle landet, ist eine Rechnung und keine
/// Ansichtssache.
library;

import 'package:xml/xml.dart';

import 'reverse_geocoder.dart';

/// Ein Punkt einer aufgezeichneten Spur – mit Zeit, wie ihn das
/// Verorten braucht.
typedef Spurpunkt = ({
  DateTime zeit,
  double breite,
  double laenge,

  /// Meter über dem Meer, falls die Datei sie führt. Nicht jede tut das,
  /// und eine erfundene Null wäre schlimmer als nichts: Sie sähe aus wie
  /// eine Messung.
  double? hoehe,
});

/// Ein Punkt, wie er in der Datei steht – **ohne** die Bedingung, eine
/// Zeit zu tragen.
///
/// Für die Linie und für das Höhenprofil taugt auch ein Punkt ohne Zeit;
/// nur zum Zuordnen von Fotos taugt er nicht. Zwei Typen und nicht einer
/// mit einem Merker, weil [ortZurZeit] und alles darunter sich sonst
/// jedes Mal fragen müssten, ob die Zeit diesmal da ist.
typedef Rohpunkt = ({
  DateTime? zeit,
  double breite,
  double laenge,
  double? hoehe,
});

/// Warum eine Datei unbrauchbar war.
enum GpxAbbruch {
  /// Kein `<gpx>`-Wurzelelement – das ist keine GPX-Datei.
  keinGpx,

  /// Punkte ja, aber keiner mit Zeitstempel. Ohne Zeit lässt sich nichts
  /// zuordnen; die Spur wäre nur eine Linie.
  ohneZeit,

  /// Gar keine Punkte.
  leer,
}

class GpxFehler implements Exception {
  final GpxAbbruch grund;
  const GpxFehler(this.grund);

  @override
  String toString() => 'GpxFehler($grund)';
}

/// Die Punkte, die für eine Zuordnung taugen.
///
/// Gelesen werden `trkpt` (Spur), `rtept` (geplante Route) und `wpt`
/// (einzelne Marken) – alle drei tragen dieselben Angaben, und welches
/// Programm welches schreibt, ist nicht vorherzusehen.
///
/// **Punkte ohne `<time>` fallen weg.** Sie sind für die Linie brauchbar,
/// für das Zuordnen nicht, und eine Liste, in der die Hälfte keine Zeit
/// hat, brächte jede Suche durcheinander.
List<Spurpunkt> liesGpx(String inhalt) {
  final alle = liesGpxPunkte(inhalt);
  final spur = <Spurpunkt>[
    for (final p in alle)
      if (p.zeit case final z?)
        (zeit: z, breite: p.breite, laenge: p.laenge, hoehe: p.hoehe),
  ];
  if (spur.isEmpty) throw const GpxFehler(GpxAbbruch.ohneZeit);
  spur.sort((a, b) => a.zeit.compareTo(b.zeit));
  return spur;
}

/// Alle Punkte der Datei, in der Reihenfolge, in der sie dastehen.
///
/// Die Reihenfolge der Datei und **nicht** nach Zeit sortiert: Für eine
/// Linie ist die aufgezeichnete Folge die Aussage. Punkte ohne Zeit
/// bleiben drin – sie sind es, die eine geplante Route ausmachen.
List<Rohpunkt> liesGpxPunkte(String inhalt) {
  final XmlDocument urkunde;
  try {
    urkunde = XmlDocument.parse(inhalt);
  } on XmlException {
    throw const GpxFehler(GpxAbbruch.keinGpx);
  }
  final wurzel = urkunde.rootElement;
  if (wurzel.localName.toLowerCase() != 'gpx') {
    throw const GpxFehler(GpxAbbruch.keinGpx);
  }

  final punkte = <Rohpunkt>[];
  for (final art in ['trkpt', 'rtept', 'wpt']) {
    for (final e in wurzel.findAllElements(art)) {
      final breite = double.tryParse(e.getAttribute('lat') ?? '');
      final laenge = double.tryParse(e.getAttribute('lon') ?? '');
      if (breite == null || laenge == null) continue;
      final zeitText = e.getElement('time')?.innerText.trim();
      final zeit = (zeitText == null || zeitText.isEmpty)
          ? null
          : DateTime.tryParse(zeitText)?.toUtc();
      // `<ele>` ist der Grund für diese Stufe. Bis hierher wurde es
      // gelesen und weggeworfen – ohne Höhe gibt es kein Profil.
      final hoeheText = e.getElement('ele')?.innerText.trim();
      final hoehe =
          (hoeheText == null || hoeheText.isEmpty) ? null : double.tryParse(hoeheText);
      punkte.add((zeit: zeit, breite: breite, laenge: laenge, hoehe: hoehe));
    }
  }

  if (punkte.isEmpty) throw const GpxFehler(GpxAbbruch.leer);
  return punkte;
}

/// Die Länge einer Spur in Kilometern – Summe der Luftlinien.
///
/// Ohne Glättung, anders als bei den Aktivitäten: Eine Aufzeichnung ist
/// bereits eine Folge gemessener Punkte und keine Sammlung von Fotos,
/// die zufällig nebeneinanderliegen. Wer sie glättete, verkürzte jede
/// Serpentine.
double spurlaengeKm(List<({double breite, double laenge})> punkte) {
  var summe = 0.0;
  for (var i = 1; i < punkte.length; i++) {
    summe += ReverseGeocoder.haversineKm(punkte[i - 1].breite,
        punkte[i - 1].laenge, punkte[i].breite, punkte[i].laenge);
  }
  return summe;
}

/// Ab welchem Unterschied ein Höhenwechsel als Höhenwechsel zählt.
///
/// **Die angreifbarste Zahl dieser Stufe, deshalb steht sie hier und
/// nicht versteckt im Code.** Fünf Meter. Die Höhe aus GPS ist um ein
/// Vielfaches ungenauer als die Position – ein stehendes Gerät wandert
/// über Minuten um mehrere Meter auf und ab. Ohne Schwelle summiert eine
/// flache Runde um den See hundert Höhenmeter, die es nie gab; mit einer
/// zu grossen fällt jede Treppe weg.
const double hoehenSchwelle = 5;

/// Über so viele Punkte wird die Höhe gemittelt, bevor gezählt wird.
///
/// **Die Schwelle allein reicht nicht.** Sie wirkt gegen den Abstand
/// zweier Messungen, und der ist beim Rauschen doppelt so gross wie
/// dessen Ausschlag: Ein Gerät, das um ±3 m schwankt, springt zwischen
/// zwei Punkten um 6 m – über der Schwelle von 5, also gezählt. Erst das
/// Mitteln nimmt dem Rauschen die Spitzen; die Schwelle fängt danach,
/// was übrig ist. Beides zusammen, nicht eins von beidem.
const int hoehenGlaettung = 5;

/// Mittelt eine Höhenreihe über ein **symmetrisch schrumpfendes**
/// Fenster.
///
/// Symmetrisch, damit die Enden stehen bleiben: Ein einseitiges Fenster
/// zöge den ersten Punkt in Richtung des zweiten und den letzten in
/// Richtung des vorletzten – ein Anstieg verlöre an beiden Enden Meter,
/// die er hatte. Auf einer gleichmässigen Steigung ändert dieses Mitteln
/// gar nichts, und genau das soll es.
List<double> geglaetteteHoehen(List<double> hoehen, {int fenster = hoehenGlaettung}) {
  if (fenster <= 1 || hoehen.length < 3) return hoehen;
  final halb = fenster ~/ 2;
  return [
    for (var i = 0; i < hoehen.length; i++)
      () {
        final h = [halb, i, hoehen.length - 1 - i].reduce((a, b) => a < b ? a : b);
        if (h == 0) return hoehen[i];
        var summe = 0.0;
        for (var k = i - h; k <= i + h; k++) {
          summe += hoehen[k];
        }
        return summe / (2 * h + 1);
      }(),
  ];
}

/// Auf- und Abstieg in Metern.
///
/// Zwei Stufen: erst [geglaetteteHoehen], dann eine Hysterese. Gemerkt
/// wird eine Bezugshöhe; erst wenn die aktuelle sie um mehr als
/// [schwelle] über- oder unterschreitet, wird der Unterschied gezählt
/// und die Bezugshöhe nachgezogen. Punkt für Punkt gezählt wäre jedes
/// Rauschen ein Anstieg.
///
/// Punkte ohne Höhe werden übersprungen, nicht durch Null ersetzt: Eine
/// fehlende Höhe als Null zu lesen ergäbe einen Absturz auf Meereshöhe
/// und einen Wiederaufstieg.
({double aufstieg, double abstieg}) hoehenbilanz(
  Iterable<double?> hoehen, {
  double schwelle = hoehenSchwelle,
  int glaettung = hoehenGlaettung,
}) {
  final vorhanden = [
    for (final h in hoehen)
      if (h != null) h,
  ];
  final reihe = geglaetteteHoehen(vorhanden, fenster: glaettung);
  if (reihe.isEmpty) return (aufstieg: 0, abstieg: 0);

  var bezug = reihe.first;
  var auf = 0.0;
  var ab = 0.0;
  for (final h in reihe.skip(1)) {
    final d = h - bezug;
    if (d > schwelle) {
      auf += d;
      bezug = h;
    } else if (d < -schwelle) {
      ab += -d;
      bezug = h;
    }
  }
  return (aufstieg: auf, abstieg: ab);
}

/// Ein Punkt des Höhenprofils: wie weit gelaufen, wie hoch – und
/// welcher Punkt der Spur es war.
///
/// Die [index]-Angabe ist der Grund, warum ein Zeigen auf das Profil
/// eine Marke auf der Karte setzen kann: Ohne sie müsste man die Strecke
/// rückwärts suchen und dabei Kommazahlen vergleichen.
typedef Profilpunkt = ({double km, double hoehe, int index});

/// Rechnet die Punkte einer Spur auf Streckenmarken um.
///
/// **Die Waagerechte ist die Strecke, nicht die Zeit.** Über der Zeit
/// aufgetragen wird jede Rast eine Ebene und jeder Abstieg eine Wand –
/// man sähe, wie lange man wo war, aber nicht, wie der Weg aussah.
///
/// Punkte ohne Höhe fallen heraus, **nachdem** ihre Strecke gezählt
/// wurde: Ein Loch in den Höhenangaben ist kein Loch im Weg.
List<Profilpunkt> profilpunkte(
    List<({double breite, double laenge, double? hoehe})> punkte) {
  final ergebnis = <Profilpunkt>[];
  var strecke = 0.0;
  for (var i = 0; i < punkte.length; i++) {
    if (i > 0) {
      strecke += ReverseGeocoder.haversineKm(punkte[i - 1].breite,
          punkte[i - 1].laenge, punkte[i].breite, punkte[i].laenge);
    }
    final h = punkte[i].hoehe;
    if (h != null) ergebnis.add((km: strecke, hoehe: h, index: i));
  }
  return ergebnis;
}

/// Was über eine Spur im Ganzen gesagt werden kann.
typedef Spurkennzahlen = ({
  DateTime? von,
  DateTime? bis,
  int punktzahl,
  double laengeKm,

  /// `null`, wenn **kein** Punkt eine Höhe trug. Null Meter Aufstieg und
  /// „keine Höhenangabe" sind zweierlei – das eine ist eine flache
  /// Runde, das andere ein Gerät ohne Barometer.
  double? aufstieg,
  double? abstieg,
});

/// Rechnet die Kennzahlen einer Spur – einmal beim Einlesen, nicht bei
/// jeder Anzeige.
Spurkennzahlen spurkennzahlen(List<Rohpunkt> punkte) {
  final zeiten = [
    for (final p in punkte)
      if (p.zeit case final z?) z,
  ]..sort();
  final mitHoehe = punkte.any((p) => p.hoehe != null);
  final bilanz =
      mitHoehe ? hoehenbilanz([for (final p in punkte) p.hoehe]) : null;
  return (
    von: zeiten.isEmpty ? null : zeiten.first,
    bis: zeiten.isEmpty ? null : zeiten.last,
    punktzahl: punkte.length,
    laengeKm: spurlaengeKm(
        [for (final p in punkte) (breite: p.breite, laenge: p.laenge)]),
    aufstieg: bilanz?.aufstieg,
    abstieg: bilanz?.abstieg,
  );
}

/// Wie weit zwei aufeinanderfolgende Punkte auseinanderliegen dürfen,
/// damit dazwischen noch gerechnet wird.
///
/// Eine halbe Stunde. Bei einer längeren Lücke stand das Gerät entweder
/// still oder hatte keinen Empfang – dazwischen zu rechnen hiesse, eine
/// Bewegung zu erfinden, die niemand aufgezeichnet hat.
const Duration gpxHoechsteLuecke = Duration(minutes: 30);

/// Wie weit vor dem ersten und nach dem letzten Punkt noch zugeordnet
/// wird.
///
/// Fünf Minuten: Das Foto vom Start, bevor die Uhr des Empfängers lief.
const Duration gpxRandtoleranz = Duration(minutes: 5);

/// Wo jemand zur Zeit [zeit] war – `null`, wenn die Spur es nicht hergibt.
///
/// Zwischen zwei Punkten wird linear gerechnet. Das ist eine Annahme,
/// aber die einzige, die eine Aufzeichnung überhaupt zulässt – und über
/// eine halbe Stunde hinaus wird sie nicht gemacht.
({double breite, double laenge})? ortZurZeit(
  List<Spurpunkt> spur,
  DateTime zeit, {
  Duration hoechsteLuecke = gpxHoechsteLuecke,
  Duration randtoleranz = gpxRandtoleranz,
}) {
  if (spur.isEmpty) return null;
  final z = zeit.toUtc();

  if (z.isBefore(spur.first.zeit)) {
    return spur.first.zeit.difference(z) <= randtoleranz
        ? (breite: spur.first.breite, laenge: spur.first.laenge)
        : null;
  }
  if (z.isAfter(spur.last.zeit)) {
    return z.difference(spur.last.zeit) <= randtoleranz
        ? (breite: spur.last.breite, laenge: spur.last.laenge)
        : null;
  }

  // Binäre Suche nach dem letzten Punkt, der nicht nach [z] liegt.
  var links = 0;
  var rechts = spur.length - 1;
  while (links < rechts) {
    final mitte = (links + rechts + 1) ~/ 2;
    if (spur[mitte].zeit.isAfter(z)) {
      rechts = mitte - 1;
    } else {
      links = mitte;
    }
  }
  final vor = spur[links];
  if (vor.zeit == z || links == spur.length - 1) {
    return (breite: vor.breite, laenge: vor.laenge);
  }
  final nach = spur[links + 1];
  final luecke = nach.zeit.difference(vor.zeit);
  if (luecke > hoechsteLuecke) return null;
  if (luecke.inMilliseconds == 0) {
    return (breite: vor.breite, laenge: vor.laenge);
  }
  final anteil =
      z.difference(vor.zeit).inMilliseconds / luecke.inMilliseconds;
  return (
    breite: vor.breite + (nach.breite - vor.breite) * anteil,
    laenge: vor.laenge + (nach.laenge - vor.laenge) * anteil,
  );
}

/// Die Schritte, in denen nach dem Zeitversatz gesucht wird.
///
/// Halbe Stunden von −14 bis +14: Alle Zeitzonen der Welt sind ganze oder
/// halbe Stunden von UTC entfernt (die drei Viertelstunden-Zonen –
/// Nepal, Chatham – fallen durch und lassen sich von Hand einstellen).
List<Duration> gpxVersatzkandidaten() => [
      for (var m = -14 * 60; m <= 14 * 60; m += 30) Duration(minutes: m),
    ];

/// Sucht den Zeitversatz, bei dem die meisten Aufnahmen auf die Spur
/// passen.
///
/// **Der Grund, warum es diese Funktion gibt:** EXIF schreibt die
/// Aufnahmezeit ohne Zeitzone, GPX schreibt UTC. Zwischen beiden liegt
/// ein Versatz, den niemand kennt – und er ist nicht einmal immer die
/// Zeitzone: Eine Kamera, deren Uhr seit zwei Jahren falsch geht,
/// verschiebt alles um denselben Betrag. Statt den Nutzer raten zu
/// lassen, wird ausprobiert und gezählt.
///
/// Bei Gleichstand gewinnt der kleinere Versatz – wenn zwei Erklärungen
/// gleich viele Fotos treffen, ist die harmlosere die wahrscheinlichere.
Duration besterVersatz(
  List<Spurpunkt> spur,
  Iterable<DateTime> zeiten, {
  List<Duration>? kandidaten,
  Duration hoechsteLuecke = gpxHoechsteLuecke,
  Duration randtoleranz = gpxRandtoleranz,
}) {
  final liste = zeiten.toList();
  var bester = Duration.zero;
  var meiste = -1;
  for (final versatz in kandidaten ?? gpxVersatzkandidaten()) {
    var treffer = 0;
    for (final z in liste) {
      if (ortZurZeit(spur, z.add(versatz),
              hoechsteLuecke: hoechsteLuecke, randtoleranz: randtoleranz) !=
          null) {
        treffer++;
      }
    }
    if (treffer > meiste ||
        (treffer == meiste && versatz.abs() < bester.abs())) {
      meiste = treffer;
      bester = versatz;
    }
  }
  return bester;
}

/// Eine geplante Zuordnung – Aufnahme zu Koordinate.
typedef Verortung = ({String assetId, double breite, double laenge});

/// Ordnet allen [aufnahmen] eine Koordinate zu, soweit die Spur es
/// hergibt.
List<Verortung> verorteAusSpur(
  List<Spurpunkt> spur,
  Iterable<({String id, DateTime zeit})> aufnahmen, {
  Duration versatz = Duration.zero,
  Duration hoechsteLuecke = gpxHoechsteLuecke,
  Duration randtoleranz = gpxRandtoleranz,
}) =>
    [
      for (final a in aufnahmen)
        if (ortZurZeit(spur, a.zeit.add(versatz),
                hoechsteLuecke: hoechsteLuecke,
                randtoleranz: randtoleranz)
            case final ort?)
          (assetId: a.id, breite: ort.breite, laenge: ort.laenge),
    ];
