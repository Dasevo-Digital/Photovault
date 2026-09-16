/// Zahlen über eine Familie – Lebensalter, Heiratsalter, Kinderzahl,
/// Namen.
///
/// Statistik gab es bisher nur über Fotos. Über die Menschen, die auf
/// ihnen sind, sagte die App nichts, obwohl alle Angaben dafür längst
/// eingetragen sind.
///
/// **Reine Funktionen, ohne Datenbankklassen** – wie `lebenslauf.dart`.
/// Nur so lassen sich die Zahlen nachrechnen; eine falsche Statistik
/// sieht richtig aus, und am fertigen Balkendiagramm ist sie nicht zu
/// erkennen.
library;

import 'lebenslauf.dart';
import 'stammbaum.dart';
import 'verwandtschaftsgrad.dart';

/// Eine Person, wie die Auswertung sie braucht.
typedef StatPerson = ({
  String id,
  String name,
  Geschlecht? geschlecht,
  DateTime? geburt,
  DateTime? tod,
});

/// Ein Ereignis, wie die Auswertung es braucht.
typedef StatEreignis = ({String personId, Ereignisart art, DateTime? datum});

/// Vollendete Lebensjahre zwischen zwei Zeitpunkten.
///
/// `null`, wenn eine Angabe fehlt **oder widersprüchlich ist** – ein Tod
/// vor der Geburt ergäbe ein negatives Alter, und das zöge einen
/// Durchschnitt nach unten, ohne dass jemand die Ursache fände.
///
/// Gerechnet wird nach dem Geburtstag, nicht nach der Jahreszahl: Wer im
/// Dezember 1900 geboren wurde und im Januar 1980 starb, wurde 79 und
/// nicht 80.
int? alterInJahren(DateTime? von, DateTime? bis) {
  if (von == null || bis == null) return null;
  if (bis.isBefore(von)) return null;
  var jahre = bis.year - von.year;
  final geburtstagWar = bis.month > von.month ||
      (bis.month == von.month && bis.day >= von.day);
  if (!geburtstagWar) jahre--;
  return jahre < 0 ? null : jahre;
}

/// Eine Altersauswertung – und was sie **nicht** enthält.
///
/// [nichtGezaehlt] ist der wichtigste Wert hier. Lebende haben kein
/// Sterbedatum; zählte man sie als „0 Jahre" mit, käme ein
/// Durchschnittsalter heraus, das grob falsch ist und dabei völlig
/// plausibel aussieht. Sie sind deshalb ausgeschlossen – und die Zahl
/// der Ausgeschlossenen gehört neben das Ergebnis, sonst wäre das
/// Ergebnis wieder eine halbe Auskunft.
class Altersauswertung {
  /// Wie viele Personen einen vollständigen Wert beitragen konnten.
  final int anzahl;

  /// Wie viele nicht – fehlendes oder widersprüchliches Datum.
  final int nichtGezaehlt;

  final double? durchschnitt;
  final int? kleinstes;
  final int? groesstes;

  const Altersauswertung({
    required this.anzahl,
    required this.nichtGezaehlt,
    this.durchschnitt,
    this.kleinstes,
    this.groesstes,
  });

  bool get istLeer => anzahl == 0;

  factory Altersauswertung.aus(Iterable<int?> werte) {
    final gute = [for (final w in werte) if (w != null) w]..sort();
    return Altersauswertung(
      anzahl: gute.length,
      nichtGezaehlt: werte.length - gute.length,
      durchschnitt: gute.isEmpty
          ? null
          : gute.reduce((a, b) => a + b) / gute.length,
      kleinstes: gute.isEmpty ? null : gute.first,
      groesstes: gute.isEmpty ? null : gute.last,
    );
  }
}

/// Die Generation jeder Person, bezogen auf [ich]: Eltern −1, Kinder +1.
///
/// Breitensuche über die vorhandenen Eltern- und Kindkanten – kein neues
/// Feld an der Person. Adoptiv- und Pflegekanten zählen mit, wie überall
/// sonst auch.
///
/// **Partner bekommen die Generation ihres Partners**, aber erst danach
/// und nur, wenn sie keine eigene haben. Das ist eine Übereinkunft und
/// keine Tatsache: Eine angeheiratete Person hat ihre eigene Herkunft
/// und stünde in ihrer eigenen Familie woanders. Ohne diesen Schritt
/// fiele jedoch bei jedem Paar die Hälfte aus der Auswertung – und
/// gerade Ehepaare gehören beim Lebensalter nebeneinander.
Map<String, int> generationen(Verwandtschaftsnetz netz, String ich) {
  final ergebnis = <String, int>{ich: 0};
  final rand = <String>[ich];
  while (rand.isNotEmpty) {
    final aktuell = rand.removeAt(0);
    final stufe = ergebnis[aktuell]!;
    for (final (nachbarn, richtung) in [
      (netz.eltern(aktuell), -1),
      (netz.kinder(aktuell), 1),
    ]) {
      for (final n in nachbarn) {
        if (ergebnis.containsKey(n)) continue;
        ergebnis[n] = stufe + richtung;
        rand.add(n);
      }
    }
  }

  // Der zweite Durchgang, in fester Reihenfolge: Wer mit zwei Personen
  // verschiedener Generationen verbunden ist, soll nicht bei jedem Aufruf
  // in einer anderen landen.
  for (final id in ergebnis.keys.toList()..sort()) {
    for (final p in netz.partner(id).toList()..sort()) {
      ergebnis.putIfAbsent(p, () => ergebnis[id]!);
    }
  }
  return ergebnis;
}

/// Zerlegt einen Namen so, wie es der GEDCOM-Export tut.
///
/// Diese App führt **ein** Namensfeld. Als Nachname gilt deshalb das
/// letzte Wort, sofern es mehr als eines gibt – dieselbe Vermutung wie
/// in `gedcom_export.dart`, damit die Auswertung nicht anders zählt, als
/// die Datei später aussieht.
({String? vorname, String? nachname}) namensteile(String name) {
  final teile = name.trim().split(RegExp(r'\s+'))
    ..removeWhere((t) => t.isEmpty);
  if (teile.isEmpty) return (vorname: null, nachname: null);
  if (teile.length == 1) return (vorname: teile.first, nachname: null);
  return (vorname: teile.first, nachname: teile.last);
}

/// Eine Häufigkeitsliste, die häufigsten zuerst.
///
/// Bei gleicher Zahl alphabetisch – ohne das sprängen die Zeilen bei
/// jedem Aufbau umher.
List<({String name, int anzahl})> haeufigkeiten(
  Iterable<String?> namen, {
  int hoechstens = 8,
}) {
  final gezaehlt = <String, int>{};
  for (final n in namen) {
    if (n == null || n.isEmpty) continue;
    gezaehlt[n] = (gezaehlt[n] ?? 0) + 1;
  }
  final liste = [
    for (final e in gezaehlt.entries) (name: e.key, anzahl: e.value),
  ]..sort((a, b) {
      final z = b.anzahl.compareTo(a.anzahl);
      return z != 0 ? z : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  return liste.take(hoechstens).toList();
}

/// Das Ergebnis einer Auswertung.
class Familienstatistik {
  final int personen;

  /// Wie alt die Verstorbenen wurden.
  final Altersauswertung sterbealter;

  /// Dasselbe je Generation – **1 ist die älteste**, die in dieser
  /// Familie vorkommt. Absolut gezählt und nicht als „zwei über dir":
  /// Eine Auswertung soll dieselbe bleiben, wenn jemand anders in der
  /// Mitte steht.
  final Map<int, Altersauswertung> alterJeGeneration;

  /// Wie alt beim **ersten** Mal geheiratet wurde.
  final Altersauswertung heiratsalter;

  /// Wie viele Personen wie viele Kinder haben: Kinderzahl → Anzahl.
  ///
  /// Eine Verteilung und kein Durchschnitt. Ein Durchschnitt müsste
  /// entscheiden, wen er mitzählt – ein Kind hat noch keine Kinder, und
  /// es auszuschließen hiesse, die Grenze willkürlich zu ziehen. Die
  /// Verteilung sagt beides zugleich.
  final Map<int, int> kinderverteilung;

  final List<({String name, int anzahl})> nachnamen;
  final List<({String name, int anzahl})> vornamen;

  const Familienstatistik({
    required this.personen,
    required this.sterbealter,
    required this.alterJeGeneration,
    required this.heiratsalter,
    required this.kinderverteilung,
    required this.nachnamen,
    required this.vornamen,
  });

  /// Ob überhaupt jemand ausgewertet wurde.
  ///
  /// Bewusst **nur** die Personenzahl und nicht „keine Lebensdaten": Eine
  /// Familie ohne ein einziges Datum hat immer noch Namen und
  /// Kinderzahlen, und beides ist eine Auskunft. Statt dessen steht bei
  /// den Altersangaben „keine Angabe" – das ist ehrlicher als ein
  /// Bildschirm, der behauptet, es gäbe nichts.
  bool get istLeer => personen == 0;
}

/// Rechnet alles aus.
///
/// [personen] ist die Menge, die ausgewertet wird – in der Oberfläche
/// die Familie um die Person in der Mitte. [netz] darf mehr enthalten;
/// gezählt wird nur, was in [personen] steht.
Familienstatistik familienstatistik({
  required List<StatPerson> personen,
  required Verwandtschaftsnetz netz,
  required String fokus,
  required List<StatEreignis> ereignisse,
}) {
  final stufen = generationen(netz, fokus);
  final dabei = {for (final p in personen) p.id};

  // Nur Generationen, in denen auch jemand aus der Menge steht. Sonst
  // stünde eine leere Spalte im Diagramm, weil irgendwo im Netz noch ein
  // Urahn hängt, der hier gar nicht gezeigt wird.
  final belegt = <int, List<StatPerson>>{};
  for (final p in personen) {
    final stufe = stufen[p.id];
    if (stufe == null) continue;
    belegt.putIfAbsent(stufe, () => []).add(p);
  }
  final aelteste =
      belegt.keys.isEmpty ? 0 : belegt.keys.reduce((a, b) => a < b ? a : b);

  // Die erste datierte Hochzeit je Person. Zweite Ehen bleiben außen
  // vor: „Heiratsalter" meint den Schritt in die erste Ehe, und ein
  // Wiederverheirateter mit sechzig verschöbe den Wert, ohne dass es
  // jemand am Ergebnis sähe.
  final ersteHochzeit = <String, DateTime>{};
  for (final e in ereignisse) {
    if (e.art != Ereignisart.hochzeit || e.datum == null) continue;
    if (!dabei.contains(e.personId)) continue;
    final bisher = ersteHochzeit[e.personId];
    if (bisher == null || e.datum!.isBefore(bisher)) {
      ersteHochzeit[e.personId] = e.datum!;
    }
  }

  final kinder = <int, int>{};
  for (final p in personen) {
    final anzahl = netz.kinder(p.id).where(dabei.contains).length;
    kinder[anzahl] = (kinder[anzahl] ?? 0) + 1;
  }

  return Familienstatistik(
    personen: personen.length,
    sterbealter:
        Altersauswertung.aus([for (final p in personen) alterInJahren(p.geburt, p.tod)]),
    alterJeGeneration: {
      for (final e in belegt.entries)
        if (Altersauswertung.aus(
                [for (final p in e.value) alterInJahren(p.geburt, p.tod)])
            case final a when !a.istLeer)
          e.key - aelteste + 1: a,
    },
    heiratsalter: Altersauswertung.aus([
      for (final p in personen)
        if (ersteHochzeit.containsKey(p.id))
          alterInJahren(p.geburt, ersteHochzeit[p.id]),
    ]),
    kinderverteilung: kinder,
    nachnamen:
        haeufigkeiten([for (final p in personen) namensteile(p.name).nachname]),
    vornamen:
        haeufigkeiten([for (final p in personen) namensteile(p.name).vorname]),
  );
}
