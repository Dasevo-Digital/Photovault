/// Die Geometrie des Fächerdiagramms – ohne Oberfläche.
///
/// Ein Fächer ist eine Ahnentafel in Polarkoordinaten: Die Person sitzt in
/// der Mitte, jede Generation ist ein Ring darüber, und jeder Ring hat
/// doppelt so viele Plätze wie der darunter. Genau daher kommt seine
/// Stärke – ein Platz hat immer **genau einen** Nachfolger im Ring
/// darunter, also kann keine Linie mehrdeutig werden. Das ist der Grund,
/// warum diese Form vier Generationen zeigen darf, wo die Reihen-Ansicht
/// bei einer bleiben muss.
///
/// Ausgelagert, weil sich Winkel am fertigen Bild nicht prüfen lassen: Ob
/// ein Ring lückenlos gefüllt ist oder sich zwei Plätze um ein
/// Hundertstel überlappen, sieht man nicht – man rechnet es nach.
library;

import 'dart:math' as math;

import 'stammbaum.dart';

/// Ein Platz im Fächer.
class Fachplatz {
  /// Die Nummer nach Ahnentafel-Zählung: 1 ist die Person in der Mitte,
  /// die Eltern von *n* sind *2n* und *2n+1*.
  ///
  /// Diese Zählung ist keine Zierde, sondern die Verbindung zwischen
  /// Geometrie und Bestand: Aus der Nummer allein ergeben sich Ring und
  /// Platz im Ring, ohne dass die Zeichenroutine den Baum kennen müsste.
  final int nummer;

  /// Der Ring, in dem der Platz liegt – 0 ist die Mitte.
  final int ring;

  /// `null`, wenn dort niemand eingetragen ist. Solche Plätze werden
  /// trotzdem geliefert: Eine Lücke im Fächer ist eine Aussage („hier
  /// fehlt ein Elternteil") und soll sichtbar sein.
  final String? personId;

  /// Anfangswinkel und Öffnung im Bogenmaß, in Flutters Zählweise:
  /// 0 zeigt nach rechts, wachsende Winkel drehen im Uhrzeigersinn.
  final double vonWinkel;
  final double oeffnung;

  const Fachplatz({
    required this.nummer,
    required this.ring,
    required this.personId,
    required this.vonWinkel,
    required this.oeffnung,
  });

  double get mittelWinkel => vonWinkel + oeffnung / 2;
  bool get istLeer => personId == null;

  @override
  String toString() => 'Fachplatz($nummer, Ring $ring, ${personId ?? "leer"})';
}

/// Der Fächer wird als obere Halbkreisscheibe gezeichnet.
///
/// In Flutters Zählweise (0 zeigt nach rechts, positive Winkel drehen im
/// Uhrzeigersinn, y wächst nach unten) beginnt die obere Hälfte bei π und
/// überstreicht π.
const fachAnfang = math.pi;
const fachOeffnung = math.pi;

/// Höchste sinnvolle Ringzahl.
///
/// Vier Ringe sind sechzehn Plätze im äußersten – bei einem Fächer von
/// 320 Punkten Durchmesser bleiben je Platz noch gut zwanzig Grad, in die
/// ein Vorname passt. Fünf Ringe halbieren das auf zehn Grad; dort steht
/// dann nichts Lesbares mehr.
const maxFachRinge = 4;

/// Ordnet Elternteile für die Tafel.
///
/// Eine Elternkante trägt kein „Vater"/„Mutter" – im Bestand ist es eine
/// Menge. Für die Tafel braucht es aber eine feste Reihenfolge, sonst
/// springen die Plätze bei jedem Aufbau. Sortiert wird nach der
/// mitgegebenen Ordnung (in der App: Geschlecht, dann Alter, dann Name).
///
/// **Mehr als zwei Elternteile** kann eine Ahnentafel nicht abbilden – sie
/// ist auf Verdopplung gebaut. Überzählige fallen deshalb weg; welche,
/// entscheidet dieselbe Ordnung. Die Reihen-Ansicht zeigt weiterhin alle.
List<String?> elternFuerTafel(
  Verwandtschaftsnetz netz,
  String id,
  int Function(String) ordnung,
) {
  final eltern = netz.eltern(id).toList()
    ..sort((a, b) => ordnung(a).compareTo(ordnung(b)));
  return [
    eltern.isNotEmpty ? eltern[0] : null,
    eltern.length > 1 ? eltern[1] : null,
  ];
}

/// Baut die Plätze für [ringe] Generationen über [wurzel].
///
/// Geliefert werden **alle** Plätze bis zum äußersten Ring, auch leere –
/// aber ein Ast wird nicht weiterverfolgt, sobald er niemanden mehr
/// enthält. Ohne diesen Abbruch entstünden bei vier Ringen immer 31
/// Plätze, auch für eine Person ohne einen einzigen eingetragenen
/// Vorfahren, und der Fächer wäre eine leere Zielscheibe.
List<Fachplatz> faechertafel(
  Verwandtschaftsnetz netz,
  String wurzel,
  int Function(String) ordnung, {
  int ringe = maxFachRinge,
}) {
  final plaetze = <Fachplatz>[
    Fachplatz(
      nummer: 1,
      ring: 0,
      personId: wurzel,
      vonWinkel: fachAnfang,
      oeffnung: fachOeffnung,
    ),
  ];
  // Nummer -> Person, für die jeweils nächste Generation.
  var aktuell = <int, String>{1: wurzel};

  for (var ring = 1; ring <= ringe && aktuell.isNotEmpty; ring++) {
    final plaetzeImRing = 1 << ring;
    final breite = fachOeffnung / plaetzeImRing;
    final naechste = <int, String>{};

    for (final eintrag in aktuell.entries) {
      final eltern = elternFuerTafel(netz, eintrag.value, ordnung);
      for (var seite = 0; seite < 2; seite++) {
        final nummer = eintrag.key * 2 + seite;
        final index = nummer - plaetzeImRing;
        final person = eltern[seite];
        plaetze.add(Fachplatz(
          nummer: nummer,
          ring: ring,
          personId: person,
          vonWinkel: fachAnfang + index * breite,
          oeffnung: breite,
        ));
        if (person != null) naechste[nummer] = person;
      }
    }
    aktuell = naechste;
  }
  return _ohneLeereAussenringe(plaetze);
}

/// Kürzt den Fächer auf **einen** leeren Ring hinter dem letzten belegten.
///
/// Ein Ring leerer Plätze ist die Aussage „hier fehlt jemand" und gehört
/// ins Bild – aber nur einer. Ohne diesen Schnitt entstünde für jede
/// Person, deren Vorfahren nicht bis zur vierten Generation eingetragen
/// sind, ein breiter grauer Streifen am Rand, der wie ein Zeichenfehler
/// aussieht statt wie eine Einladung.
///
/// Vorher wurde **jeder** leere Außenring entfernt, auch der erste. Der
/// Fächer endete damit bündig mit der letzten belegten Generation: Wer
/// seine Eltern erfasst hatte und sonst nichts, sah eine Mitte und zwei
/// Elternhälften – und keinen Hinweis darauf, dass darüber noch zwei
/// Generationen Platz haben. Genau das war der gemeldete Eindruck, „hier
/// werden nur die Eltern aufgeführt". Jetzt stehen dort vier gestrichelte
/// Großelternplätze.
///
/// Ring 1 bleibt ohnehin immer stehen: Wer keine Eltern eingetragen hat,
/// soll genau dort die beiden leeren Plätze sehen.
List<Fachplatz> _ohneLeereAussenringe(List<Fachplatz> plaetze) {
  final letzterBelegte = plaetze
      .where((p) => !p.istLeer)
      .fold(0, (m, p) => p.ring > m ? p.ring : m);
  // Einer mehr als der letzte belegte – aber mindestens Ring 1, und nie
  // mehr, als überhaupt gebaut wurde.
  final gebaut = plaetze.fold(0, (m, p) => p.ring > m ? p.ring : m);
  final behalten = math.min(math.max(letzterBelegte + 1, 1), gebaut);
  return plaetze.where((p) => p.ring <= behalten).toList();
}

/// Findet den Platz, der an [winkel] und [abstand] liegt – für das
/// Antippen.
///
/// [abstand] ist der Abstand vom Mittelpunkt, gemessen in Ringbreiten:
/// 0,5 liegt in der Mitte, 1,5 im ersten Ring. So bleibt die Funktion von
/// der tatsächlichen Größe des Fächers unabhängig.
Fachplatz? platzBei(List<Fachplatz> plaetze, double winkel, double abstand) {
  final ring = abstand.floor();
  if (ring < 0) return null;
  // Winkel auf das Halbkreis-Intervall bringen; ein Tipp unterhalb der
  // Mittellinie liegt außerhalb und trifft nichts.
  var w = winkel;
  while (w < fachAnfang) {
    w += 2 * math.pi;
  }
  if (w > fachAnfang + fachOeffnung) return null;
  for (final p in plaetze) {
    if (p.ring != ring) continue;
    if (w >= p.vonWinkel && w < p.vonWinkel + p.oeffnung) return p;
  }
  return null;
}

/// Alle Nachkommen von [wurzel] als eingerückte Gliederung.
///
/// Die Gegenrichtung zum Fächer, und bewusst als Liste statt als
/// Zeichnung: Nachkommen verzweigen nicht regelmäßig – eine Person hat
/// keine, sieben oder zwei Kinder –, und eine Fläche, die sich danach
/// richtet, wird entweder leer oder unlesbar. Eine Einrückung verträgt
/// jede Form.
class Nachfahrenzeile {
  final String personId;

  /// 0 für die Ausgangsperson, 1 für ihre Kinder, und so fort.
  final int stufe;

  /// Ob unter dieser Zeile noch weitere folgen.
  final bool hatKinder;

  const Nachfahrenzeile(this.personId, this.stufe, this.hatKinder);
}

/// Baut die Gliederung. [tiefe] begrenzt die Rekursion.
///
/// Bereits besuchte Personen werden übersprungen: Enthält der Bestand
/// einen Kreis, liefe die Rekursion sonst nicht zurück. Dass die
/// Datenbank Kreise abweist, ist kein Grund, hier darauf zu vertrauen –
/// ein Bestand aus einer früheren Fassung könnte einen enthalten.
List<Nachfahrenzeile> nachfahren(
  Verwandtschaftsnetz netz,
  String wurzel,
  int Function(String) ordnung, {
  int tiefe = 8,
}) {
  final zeilen = <Nachfahrenzeile>[];
  final gesehen = <String>{};

  void gehe(String id, int stufe) {
    if (stufe > tiefe || !gesehen.add(id)) return;
    final kinder = netz.kinder(id).toList()
      ..sort((a, b) => ordnung(a).compareTo(ordnung(b)));
    zeilen.add(Nachfahrenzeile(id, stufe, kinder.isNotEmpty));
    for (final k in kinder) {
      gehe(k, stufe + 1);
    }
  }

  gehe(wurzel, 0);
  return zeilen;
}
