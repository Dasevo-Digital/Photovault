/// **Wann ein altes Foto entstanden ist – geschätzt aus dem Bild.**
///
/// Ein eingescanntes Abzugsfoto trägt das Datum des Scans oder gar keins.
/// MyHeritage bietet dafür seit 2023 „PhotoDater“ an, ein eigens dafür
/// trainiertes Modell. Hier reicht, was schon da ist: Die Bildsuche
/// (CLIP) hat in jedem Foto einen Vektor hinterlegt, und CLIP hat beim
/// Training Millionen Bilder mit Unterschriften wie „a photo from the
/// 1950s“ gesehen. Vergleicht man den Bildvektor mit Sätzen je Jahrzehnt,
/// ergibt sich eine Verteilung über die Jahrzehnte – ohne neues Modell und
/// ohne das Foto noch einmal zu öffnen.
///
/// **Eine Spanne, keine Jahreszahl.** Selbst das eigens trainierte Modell
/// von MyHeritage liegt nach eigener Angabe nur bei 59 % der Fotos
/// innerhalb von fünf Jahren. Gezeigt wird deshalb die kürzeste Folge von
/// Jahrzehnten, in der der grösste Teil der Verteilung liegt. Ist sie
/// breit, weiss das Modell es nicht – und das soll man sehen.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Die Jahrzehnte, zwischen denen gewählt wird. Vor 1880 gibt es kaum
/// Abzüge in Familienalben, und was es gibt, sieht für CLIP gleich aus.
const datierungJahrzehnte = [
  1880, 1890, 1900, 1910, 1920, 1930, 1940, //
  1950, 1960, 1970, 1980, 1990, 2000, 2010, 2020,
];

/// Mehrere Sätze je Jahrzehnt, gemittelt – ein einzelner Satz trägt
/// seine eigenen Zufälle mit.
///
/// **Ausgewählt an einer Probe, nicht ausgedacht.** 24 Farbfotos von 2015
/// bis 2025 mit dem CLIP der App, drei Satzgruppen im Vergleich:
///
/// ```
///                                      Schärfe 50        Schärfe 100
///                                    Mittel  Spanne    Mittel  Spanne
/// „photo/photograph/old family …“     1986    61 J.     2003    30 J.
/// „a photo from the …s“ allein        1977    74 J.     1993    47 J.
/// diese hier                          1989    52 J.     2005    22 J.
/// ```
///
/// „old family photo“ zog alles nach hinten: Das Wort „old“ sagt dem
/// Modell schon, was herauskommen soll.
List<String> datierungsSaetze(int jahrzehnt) => [
  'a photo taken in the ${jahrzehnt}s.',
  'a ${jahrzehnt}s photo.',
  'a snapshot from the ${jahrzehnt}s.',
  'a photo taken in ${jahrzehnt + 5}.',
];

/// Wie scharf die Verteilung wird – der Faktor, mit dem CLIP selbst
/// rechnet. Weicher (50) verschob in der Probe oben jedes moderne Foto um
/// fünfzehn Jahre nach hinten: Die Verteilung lief in die vielen alten
/// Jahrzehnte aus, und das Mittel folgte ihr.
const _schaerfe = 100.0;

/// Breiter als das, und die Schätzung ist keine: Sie wird gezeigt, aber
/// nicht zum Übernehmen angeboten. An künstlich gealterten Fassungen der
/// Probe (grau, Sepia, weicher) lagen die Spannen bei rund 70 Jahren –
/// das Modell sieht dann „alt“, aber nicht „wann“.
const datierungHoechsteSpanne = 40;

/// Anteil der Verteilung, den die angegebene Spanne mindestens enthält.
const datierungAnteil = 0.7;

class Datierung {
  /// Das Jahr in der Mitte der Schätzung (gewichtetes Mittel).
  final int jahr;

  /// Erstes und letztes Jahr der Spanne, die [datierungAnteil] der
  /// Verteilung enthält.
  final int von;
  final int bis;

  /// Wahrscheinlichkeit je Jahrzehnt, Summe 1.
  final Map<int, double> verteilung;

  const Datierung({
    required this.jahr,
    required this.von,
    required this.bis,
    required this.verteilung,
  });

  /// Ob das Foto alt aussieht: Die ganze Spanne liegt vor 2000. Danach
  /// sind die Fotos digital und tragen ihr Datum meist selbst.
  bool get siehtAltAus => bis < 2000;

  /// Ob die Spanne eng genug ist, um ein Datum daraus zu machen.
  bool get belastbar => bis - von + 1 <= datierungHoechsteSpanne;
}

/// Schätzt aus dem Bildvektor [bild] und den gemittelten Satzvektoren
/// [saetze] (je Jahrzehnt, siehe [datierungsSaetze]) das Jahrzehnt.
/// Beide normiert, wie sie aus `ClipService` kommen.
Datierung schaetzeDatierung(Float32List bild, Map<int, Float32List> saetze) {
  final jahrzehnte = saetze.keys.toList()..sort();
  final werte = [
    for (final j in jahrzehnte) _skalar(bild, saetze[j]!) * _schaerfe,
  ];
  final groesster = werte.reduce(math.max);
  final exp = [for (final w in werte) math.exp(w - groesster)];
  final summe = exp.fold(0.0, (a, b) => a + b);
  final p = [for (final e in exp) e / summe];

  var mittel = 0.0;
  for (var i = 0; i < p.length; i++) {
    mittel += p[i] * (jahrzehnte[i] + 5);
  }

  // Die kürzeste zusammenhängende Folge mit genug Anteil; bei gleicher
  // Länge die mit dem grösseren.
  var besteVon = 0, besteBis = p.length - 1;
  var besteMasse = 1.0;
  for (var a = 0; a < p.length; a++) {
    var masse = 0.0;
    for (var b = a; b < p.length; b++) {
      masse += p[b];
      if (masse >= datierungAnteil) {
        final kuerzer = b - a < besteBis - besteVon;
        final gleichLang = b - a == besteBis - besteVon;
        if (kuerzer || (gleichLang && masse > besteMasse)) {
          besteVon = a;
          besteBis = b;
          besteMasse = masse;
        }
        break;
      }
    }
  }

  return Datierung(
    jahr: mittel.round(),
    von: jahrzehnte[besteVon],
    bis: jahrzehnte[besteBis] + 9,
    verteilung: {for (var i = 0; i < p.length; i++) jahrzehnte[i]: p[i]},
  );
}

/// Mittelt mehrere normierte Satzvektoren und normiert das Ergebnis neu.
Float32List mittlererVektor(List<Float32List> vektoren) {
  final n = vektoren.first.length;
  final summe = Float32List(n);
  for (final v in vektoren) {
    for (var i = 0; i < n; i++) {
      summe[i] += v[i];
    }
  }
  var laenge = 0.0;
  for (final x in summe) {
    laenge += x * x;
  }
  laenge = math.sqrt(laenge);
  if (laenge == 0) return summe;
  for (var i = 0; i < n; i++) {
    summe[i] /= laenge;
  }
  return summe;
}

double _skalar(Float32List a, Float32List b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}
