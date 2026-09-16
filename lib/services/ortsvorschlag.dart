/// Ortsvorschläge: Was eine unverortete Aufnahme von ihren zeitlichen
/// Nachbarn erben könnte.
///
/// **Diese Rechnung war schon einmal verworfen.** In der 6.
/// Vergleichsauflage (30.08.2026) gemessen und abgelehnt: 68 Treffer bei
/// ±30 min, „verortete und unverortete stammen aus verschiedenen
/// Jahrzehnten, es gibt keine Nachbarn". Das stimmte – für den damaligen
/// Datenstand.
///
/// Seitdem haben 246 Videos ihren Ort aus der Datei bekommen und 228
/// Aufnahmen einen von Hand. Dieselbe Messung an derselben Bibliothek:
///
/// ```
///                                  30.08.   03.09.
/// ±30 min, Nachbarn einig ~2 km        68      286
/// ±2 h,    Nachbarn einig ~25 km        -      547
/// ```
///
/// **Eine verworfene Messung gilt nur für ihren Datenstand.**
library;

import 'reverse_geocoder.dart';

/// Eine verortete Aufnahme, wie die Rechnung sie braucht.
typedef Ortsnachbar = ({DateTime wann, double breite, double laenge});

/// Eine unverortete Aufnahme.
typedef Ortsloser = ({String id, DateTime wann});

/// Was eine Aufnahme erben könnte – samt der Begründung, denn ohne die
/// wäre es eine Behauptung statt eines Vorschlags.
class Ortsvorschlag {
  final String assetId;
  final double breite;
  final double laenge;

  /// Wie viele verortete Nachbarn im Zeitfenster lagen.
  final int nachbarn;

  /// Wie weit die Nachbarn untereinander auseinanderlagen. Klein heisst:
  /// Sie sind sich einig, und dann ist der Vorschlag etwas wert.
  final double spanneKm;

  /// Abstand zum nächsten verorteten Nachbarn.
  final Duration abstand;

  const Ortsvorschlag({
    required this.assetId,
    required this.breite,
    required this.laenge,
    required this.nachbarn,
    required this.spanneKm,
    required this.abstand,
  });
}

/// Die Vorgaben, an denen die 547 gemessen sind.
class Ortsvorschlagsregeln {
  /// Wie weit eine Aufnahme zeitlich von einem verorteten Nachbarn
  /// entfernt sein darf.
  final Duration fenster;

  /// Wie weit die Nachbarn im Fenster untereinander auseinanderliegen
  /// dürfen, damit ihr Ort noch eine Aussage ist.
  final double spanneKm;

  const Ortsvorschlagsregeln({
    this.fenster = const Duration(hours: 2),
    this.spanneKm = 25,
  });
}

/// Sucht für jede Aufnahme aus [ohneOrt] den Ort, den ihre zeitlichen
/// Nachbarn nahelegen.
///
/// **Der springende Punkt ist die Uneinigkeit.** Der nächstgelegene
/// verortete Nachbar allein wäre ein schlechter Ratgeber: Wer am selben
/// Nachmittag in Hannover und in Hamburg fotografiert hat, bekäme für
/// alles dazwischen den Ort, der zufällig zeitlich näher lag. Deshalb
/// zählt nicht der nächste Nachbar, sondern ob **alle** Nachbarn im
/// Fenster am selben Ort waren. An der echten Bibliothek fallen dadurch
/// 35 von 582 Kandidaten weg – und genau die wären die falschen gewesen.
///
/// Die Koordinate kommt danach vom zeitlich nächsten Nachbarn. Innerhalb
/// einer Spanne von 25 km ist die Wahl ohnehin fast gleichgültig; der
/// nächste ist die Wahl, die sich am leichtesten begründen lässt.
List<Ortsvorschlag> ortsvorschlaege(
  List<Ortsloser> ohneOrt,
  List<Ortsnachbar> verortet, {
  Ortsvorschlagsregeln regeln = const Ortsvorschlagsregeln(),
}) {
  if (ohneOrt.isEmpty || verortet.isEmpty) return const [];

  // Einmal sortieren, dann je Aufnahme ein Fenster darüber schieben.
  // Ohne das wäre die Suche 5351 x 2092 Vergleiche; so ist sie zweimal
  // Sortieren und einmal Durchlaufen.
  final nachbarn = [...verortet]..sort((a, b) => a.wann.compareTo(b.wann));
  final gesucht = [...ohneOrt]..sort((a, b) => a.wann.compareTo(b.wann));

  final ergebnis = <Ortsvorschlag>[];
  var von = 0;
  var bis = 0;
  for (final a in gesucht) {
    final frueheste = a.wann.subtract(regeln.fenster);
    final spaeteste = a.wann.add(regeln.fenster);
    // Beide Ränder wandern nur vorwärts – die Aufnahmen sind sortiert.
    while (von < nachbarn.length && nachbarn[von].wann.isBefore(frueheste)) {
      von++;
    }
    if (bis < von) bis = von;
    while (bis < nachbarn.length && !nachbarn[bis].wann.isAfter(spaeteste)) {
      bis++;
    }
    if (bis == von) continue;

    var minBreite = double.infinity, maxBreite = double.negativeInfinity;
    var minLaenge = double.infinity, maxLaenge = double.negativeInfinity;
    var naechster = von;
    var kleinsterAbstand = const Duration(days: 3650);
    for (var i = von; i < bis; i++) {
      final n = nachbarn[i];
      if (n.breite < minBreite) minBreite = n.breite;
      if (n.breite > maxBreite) maxBreite = n.breite;
      if (n.laenge < minLaenge) minLaenge = n.laenge;
      if (n.laenge > maxLaenge) maxLaenge = n.laenge;
      final d = n.wann.difference(a.wann).abs();
      if (d < kleinsterAbstand) {
        kleinsterAbstand = d;
        naechster = i;
      }
    }
    // Die Diagonale des umschliessenden Rechtecks: ein Mass, das nicht
    // davon abhaengt, welche zwei Nachbarn man vergleicht.
    final spanne = ReverseGeocoder.haversineKm(
        minBreite, minLaenge, maxBreite, maxLaenge);
    if (spanne > regeln.spanneKm) continue;

    ergebnis.add(Ortsvorschlag(
      assetId: a.id,
      breite: nachbarn[naechster].breite,
      laenge: nachbarn[naechster].laenge,
      nachbarn: bis - von,
      spanneKm: spanne,
      abstand: kleinsterAbstand,
    ));
  }
  return ergebnis;
}

/// Ein Bündel von Vorschlägen, wie es der Bildschirm zeigt: ein Tag, ein
/// Ort, viele Aufnahmen.
///
/// **Warum gebündelt.** 547 Vorschläge einzeln zu bestätigen sind 547
/// Klicks – derselbe Fehler, den die Serienerkennung bis Fassung 62
/// machte (286 Gruppen, 286 Klicks). Wer an einem Tag an einem Ort war,
/// entscheidet einmal.
class Ortsbuendel {
  /// Der Kalendertag, an dem die Aufnahmen entstanden.
  final DateTime tag;
  final List<Ortsvorschlag> vorschlaege;

  const Ortsbuendel(this.tag, this.vorschlaege);

  /// Der Schlüssel, unter dem ein abgelehntes Bündel gemerkt wird –
  /// dieselbe Bildung wie bei Reisen, Aktivitäten und Serien: die
  /// **kleinste** Kennung der Gruppe. Nicht die erste: Die Reihenfolge,
  /// in der die Bündelung ihre Mitglieder zurückgibt, ist nicht
  /// zugesichert.
  String get schluessel =>
      ([for (final v in vorschlaege) v.assetId]..sort()).first;

  double get breite => vorschlaege.first.breite;
  double get laenge => vorschlaege.first.laenge;

  /// Der grösste Zeitabstand im Bündel – die ehrlichste einzelne Zahl
  /// darüber, wie weit der Vorschlag trägt.
  Duration get groessterAbstand => vorschlaege
      .map((v) => v.abstand)
      .reduce((a, b) => a > b ? a : b);
}

/// Fasst Vorschläge zu Bündeln zusammen: gleicher Kalendertag und
/// derselbe Ort auf ein Zehntelgrad genau (rund 11 km – also innerhalb
/// dessen, was [Ortsvorschlagsregeln.spanneKm] ohnehin zulässt).
///
/// Die Aufnahmezeiten kommen von aussen: Sie stehen in der Datenbank,
/// nicht im Vorschlag.
List<Ortsbuendel> buendleOrtsvorschlaege(
    List<Ortsvorschlag> vorschlaege, Map<String, DateTime> zeiten) {
  final nach = <(int, int, int, int, int), List<Ortsvorschlag>>{};
  final tage = <(int, int, int, int, int), DateTime>{};
  for (final v in vorschlaege) {
    final wann = zeiten[v.assetId];
    if (wann == null) continue;
    final schluessel = (
      wann.year,
      wann.month,
      wann.day,
      (v.breite * 10).round(),
      (v.laenge * 10).round(),
    );
    nach.putIfAbsent(schluessel, () => []).add(v);
    tage[schluessel] = DateTime(wann.year, wann.month, wann.day);
  }
  final buendel = [
    for (final e in nach.entries) Ortsbuendel(tage[e.key]!, e.value),
  ];
  // Neueste zuerst – dieselbe Ordnung wie überall sonst in der App.
  buendel.sort((a, b) => b.tag.compareTo(a.tag));
  return buendel;
}
