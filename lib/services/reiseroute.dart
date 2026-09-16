/// Die Darstellung einer Reise: Route und Tageskapitel.
///
/// Ist eine Reise erst benannt, ist die Ansicht fast geschenkt — die
/// Aufnahmen liegen chronologisch vor, die Orte stehen aus der
/// Umkehr-Geokodierung an jedem Bild. Fast: Zwei Rechnungen braucht es
/// doch, und beide sind am fertigen Bild nicht zu beurteilen.
library;

import 'reverse_geocoder.dart';

/// Ein Punkt der Route.
typedef Routenpunkt = ({double breite, double laenge, DateTime zeit});

/// Wie weit zwei Routenpunkte auseinanderliegen müssen, damit beide
/// gezeichnet werden.
///
/// Ein Kilometer. Darunter liegt eine Stadtbesichtigung, und die ist als
/// Linie nichts als ein Knäuel.
const double routeMindestabstandKm = 1;

/// Darunter ist es dieselbe Stelle – zehn Meter, also weniger als die
/// Ungenauigkeit jedes GPS-Empfängers.
const double derselbeOrtKm = 0.01;

/// Fasst die Aufnahmeorte zu einer Linie zusammen.
///
/// **Nicht einfach jede Aufnahme ein Punkt.** An der echten Bibliothek
/// gemessen: 356 Aufnahmen einer Reise, davon über dreihundert an
/// derselben Stelle. Als Linie gezeichnet wären das dreihundert
/// deckungsgleiche Ecken — teuer zu zeichnen und ohne jede Aussage.
///
/// Der erste und der **letzte** Punkt bleiben stehen: Wo eine Reise
/// endet, ist eine Angabe, auch wenn der Rückweg kurz war. „Stehen
/// bleiben" heißt dabei *an einer anderen Stelle* — wer dort aufhört, wo
/// er zuletzt war, hat keinen weiteren Punkt, sondern denselben.
List<Routenpunkt> reiseroute(
  Iterable<Routenpunkt> punkte, {
  double mindestabstandKm = routeMindestabstandKm,
}) {
  final sortiert = punkte.toList()..sort((a, b) => a.zeit.compareTo(b.zeit));
  if (sortiert.length < 2) return sortiert;

  final route = <Routenpunkt>[sortiert.first];
  for (final p in sortiert.skip(1)) {
    final letzter = route.last;
    if (ReverseGeocoder.haversineKm(
            letzter.breite, letzter.laenge, p.breite, p.laenge) >=
        mindestabstandKm) {
      route.add(p);
    }
  }
  final letzter = sortiert.last;
  if (ReverseGeocoder.haversineKm(
          route.last.breite, route.last.laenge, letzter.breite, letzter.laenge) >
      derselbeOrtKm) {
    route.add(letzter);
  }
  return route;
}

/// Ein Tag der Reise – ein Kapitel im Raster.
typedef Reisetag = ({DateTime tag, List<String> aufnahmeIds, String? ort});

/// Teilt die Aufnahmen in Kalendertage.
///
/// Kalendertage und keine 24-Stunden-Abschnitte: Ein Kapitel heißt
/// „4. Juni", und was um 23:50 aufgenommen wurde, gehört zum 4. Juni und
/// nicht zum halben fünften.
///
/// Der Ort eines Tages ist der häufigste seiner Aufnahmen. Er kann
/// fehlen — an einem Tag ohne eine einzige verortete Aufnahme steht dann
/// nichts, und das ist richtiger als der Ort vom Vortag.
List<Reisetag> reisetage(
    Iterable<({String id, DateTime zeit, String? stadt})> aufnahmen) {
  final sortiert = aufnahmen.toList()..sort((a, b) => a.zeit.compareTo(b.zeit));
  final tage = <DateTime, List<({String id, DateTime zeit, String? stadt})>>{};
  for (final a in sortiert) {
    final tag = DateTime(a.zeit.year, a.zeit.month, a.zeit.day);
    tage.putIfAbsent(tag, () => []).add(a);
  }

  final schluessel = tage.keys.toList()..sort();
  return [
    for (final tag in schluessel)
      (
        tag: tag,
        aufnahmeIds: [for (final a in tage[tag]!) a.id],
        ort: _haeufigsterOrt(tage[tag]!.map((a) => a.stadt)),
      ),
  ];
}

String? _haeufigsterOrt(Iterable<String?> orte) {
  final gezaehlt = <String, int>{};
  for (final o in orte) {
    if (o == null || o.isEmpty) continue;
    gezaehlt[o] = (gezaehlt[o] ?? 0) + 1;
  }
  if (gezaehlt.isEmpty) return null;
  final beste = gezaehlt.keys.toList()
    ..sort((a, b) {
      final z = gezaehlt[b]!.compareTo(gezaehlt[a]!);
      return z != 0 ? z : a.compareTo(b);
    });
  return beste.first;
}

/// Wie nah zwei Aufnahmen sein müssen, um zum selben Aufenthaltsort zu
/// gehören.
///
/// Fünfzehn Kilometer. Das ist die Grösse einer Stadt samt ihres Umlands:
/// Wer in Rom wohnt und den Vatikan fotografiert, war nicht woanders.
/// Kleiner gewählt zerfiele jede Stadtbesichtigung in ein Dutzend Pins,
/// und die Karte wäre wieder das Knäuel, das [reiseroute] gerade
/// vermeidet.
const double aufenthaltRadiusKm = 15;

/// Ein Ort, an dem man sich aufgehalten hat, samt seiner Bilder.
typedef Aufenthaltsort = ({
  double breite,
  double laenge,
  String? name,
  List<String> aufnahmeIds,
  DateTime von,
  DateTime bis,
});

/// Eine Aufnahme, wie die Zusammenfassung sie braucht.
typedef Aufenthaltsaufnahme = ({
  String id,
  double breite,
  double laenge,
  DateTime zeit,
  String? stadt,
});

/// Fasst die Aufnahmen einer Reise zu Aufenthaltsorten zusammen.
///
/// **Nach Nähe und nicht nach Ortsnamen.** Der Name wäre der bequemere
/// Schlüssel, ist aber der schlechtere: Er fehlt bei jeder Aufnahme ohne
/// geladenen Datensatz, und die Umkehr-Geokodierung wechselt an
/// Stadtgrenzen den Namen, ohne dass jemand die Straße gewechselt hätte.
/// Der Name wird deshalb erst am Ende vergeben – der häufigste der
/// Gruppe.
///
/// Die Reihenfolge ist chronologisch nach der **ersten** Aufnahme der
/// Gruppe. Eine Karte, deren Pins in wechselnder Reihenfolge erscheinen,
/// lässt sich nicht mit der Tagesliste darunter zusammenlesen.
List<Aufenthaltsort> aufenthaltsorte(
  Iterable<Aufenthaltsaufnahme> aufnahmen, {
  double radiusKm = aufenthaltRadiusKm,
}) {
  final sortiert = aufnahmen.toList()..sort((a, b) => a.zeit.compareTo(b.zeit));
  final gruppen = <List<Aufenthaltsaufnahme>>[];
  // Der Mittelpunkt jeder Gruppe, laufend nachgeführt.
  //
  // Nicht der Abstand zum zuletzt aufgenommenen Bild: Danach hinge eine
  // Kette knapp benachbarter Bilder beliebig weit fort – drei Aufnahmen
  // im Abstand von je zwölf Kilometern wären ein einziger
  // „Aufenthaltsort" über vierundzwanzig Kilometer, und der Pin läge auf
  // keinem davon. Gegen die Mitte gemessen bleibt eine Gruppe kompakt,
  // und wer wirklich weitergezogen ist, bekommt einen eigenen Pin.
  final mitten = <({double breite, double laenge})>[];

  for (final a in sortiert) {
    var gefunden = -1;
    var besteEntfernung = double.infinity;
    for (var i = 0; i < gruppen.length; i++) {
      final e = ReverseGeocoder.haversineKm(
          mitten[i].breite, mitten[i].laenge, a.breite, a.laenge);
      if (e <= radiusKm && e < besteEntfernung) {
        besteEntfernung = e;
        gefunden = i;
      }
    }
    if (gefunden < 0) {
      gruppen.add([a]);
      mitten.add((breite: a.breite, laenge: a.laenge));
      continue;
    }
    gruppen[gefunden].add(a);
    final n = gruppen[gefunden].length;
    mitten[gefunden] = (
      breite: mitten[gefunden].breite + (a.breite - mitten[gefunden].breite) / n,
      laenge: mitten[gefunden].laenge + (a.laenge - mitten[gefunden].laenge) / n,
    );
  }

  final ergebnis = <Aufenthaltsort>[
    for (var i = 0; i < gruppen.length; i++)
      (
        breite: mitten[i].breite,
        laenge: mitten[i].laenge,
        name: _haeufigsterOrt(gruppen[i].map((a) => a.stadt)),
        aufnahmeIds: [for (final a in gruppen[i]) a.id],
        von: gruppen[i].first.zeit,
        bis: gruppen[i].last.zeit,
      ),
  ];
  ergebnis.sort((a, b) => a.von.compareTo(b.von));
  return ergebnis;
}
