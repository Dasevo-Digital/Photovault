/// „41 von 252 Ländern" – der Zähler, der süchtig macht.
///
/// Andere Reisetagebücher lassen ihn von Hand füttern. Hier steht er
/// längst in der Datenbank: Jede verortete Aufnahme trägt Land, Region
/// und Ort aus der Umkehr-Geokodierung. Es fehlte nur die Auswertung.
///
/// Rein und ohne Datenbankklassen – am fertigen Balken sieht man nicht,
/// ob „Bayern" einmal oder zweimal gezählt wurde.
library;

import 'laenderkatalog.dart';

/// Was eine Aufnahme über ihren Ort weiß, samt Anzahl.
typedef Besuchsangabe = ({String? land, String? region, String? ort, int anzahl});

/// Ein besuchtes Land mit der Zahl seiner Aufnahmen.
typedef Landeintrag = ({String name, int aufnahmen});

class Reisefortschritt {
  /// Besuchte Länder, häufigste zuerst.
  final List<Landeintrag> laender;

  /// Wie viele Länder und Gebiete der Datensatz überhaupt kennt.
  final int laenderGesamt;

  /// Verschiedene Regionen und Orte.
  final int regionen;
  final int orte;

  /// Gesamtzahl der verorteten Aufnahmen.
  final int aufnahmen;

  const Reisefortschritt({
    required this.laender,
    required this.laenderGesamt,
    required this.regionen,
    required this.orte,
    required this.aufnahmen,
  });

  int get laenderBesucht => laender.length;

  /// Anteil zwischen 0 und 1 – für den Balken.
  double get anteil =>
      laenderGesamt == 0 ? 0 : laenderBesucht / laenderGesamt;

  bool get istLeer => aufnahmen == 0;
}

/// Zählt zusammen.
///
/// **Regionen und Orte werden je Land gezählt.** „Bayern" gibt es einmal,
/// „Springfield" über zwanzigmal – ohne das Land davor wäre der Zähler
/// nicht die Zahl der besuchten Orte, sondern die Zahl der verschiedenen
/// Ortsnamen. Das ist nicht dasselbe und immer zu klein.
Reisefortschritt reisefortschritt(
  Iterable<Besuchsangabe> angaben, {
  required int laenderGesamt,
}) {
  final proLand = <String, int>{};
  final regionen = <String>{};
  final orte = <String>{};
  var summe = 0;

  for (final a in angaben) {
    summe += a.anzahl;
    final land = a.land;
    if (land == null || land.isEmpty) continue;
    proLand[land] = (proLand[land] ?? 0) + a.anzahl;
    final region = a.region;
    if (region != null && region.isNotEmpty) regionen.add('$land|$region');
    final ort = a.ort;
    if (ort != null && ort.isNotEmpty) orte.add('$land|$region|$ort');
  }

  final liste = [
    for (final e in proLand.entries) (name: e.key, aufnahmen: e.value),
  ]..sort((a, b) {
      final z = b.aufnahmen.compareTo(a.aufnahmen);
      return z != 0 ? z : a.name.compareTo(b.name);
    });

  return Reisefortschritt(
    laender: liste,
    laenderGesamt: laenderGesamt,
    regionen: regionen.length,
    orte: orte.length,
    aufnahmen: summe,
  );
}

/// Wie vollständig ein Land bereist ist.
enum Besuchsgrad {
  /// Kein Foto, keine Marke.
  nicht,

  /// Angefangen, aber nicht jede Region.
  teilweise,

  /// Jede Region des Datensatzes hat einen Beleg.
  vollstaendig,
}

/// Was eine selbst gesetzte Marke bedeutet.
enum Markenart { besucht, geplant }

/// Eine selbst gesetzte Marke, wie die Auswertung sie braucht.
typedef Markeneintrag = ({String art, String schluessel, Markenart wert});

/// Was in einer Ortsmarke steht, aufgeschlüsselt.
typedef Ortsmarkenteile = ({String iso, String region, String ort});

/// Zerlegt den Schlüssel einer Ortsmarke („Land|Region|Ort").
///
/// **Die eine Stelle, an der aus einer Ortsmarke ihre Region wird.** Vorher
/// stand diese Rechnung nur in [laenderstand]; die Regionenübersicht kannte
/// sie nicht, und deshalb galt eine von Hand markierte Stadt dort als
/// nirgends. Zwei Bildschirme, dieselben Daten, gegenteilige Auskunft –
/// siehe die Prüfung „eine markierte Stadt färbt ihr Bundesland".
///
/// Gibt `null` zurück, wenn der Schlüssel nicht die drei Teile hat.
/// [region] darf **leer** sein: 24 Länder haben keine verzeichnete Region,
/// und ein Ort in Monaco ist trotzdem ein besuchter Ort. Wer eine Region
/// braucht, prüft das selbst – hier stillschweigend zu verwerfen hiesse,
/// diese Orte aus dem Zähler zu streichen.
Ortsmarkenteile? ortsmarkeZerlegen(
    String schluessel, Map<String, String> nachIso) {
  final teile = schluessel.split('|');
  if (teile.length < 3) return null;
  return (
    iso: nachIso[teile[0]] ?? teile[0].toUpperCase(),
    region: teile[1],
    ort: teile[2],
  );
}

/// Ein Land mit allem, was über den Besuch bekannt ist.
///
/// **Fotos und Marken bleiben getrennt sichtbar.** [aufnahmen] ist der
/// Beleg der Kamera, [marke] die eigene Angabe. Wer beides in eine Zahl
/// rechnete, könnte hinterher nicht mehr sagen, worauf ein Haken beruht –
/// und genau das ist bei einer Landkarte die interessante Frage.
class Landstand {
  final String iso;

  /// Der Name aus dem Katalog – **englisch**, und damit derselbe, der in
  /// den Aufnahmen steht. Zum Anzeigen [nameDe] bzw. [anzeige].
  final String name;

  /// Derselbe Name auf Deutsch.
  final String nameDe;

  /// Der Name, wie er in der Sprache [sprache] dastehen soll.
  String anzeige(String sprache) => sprache.startsWith('de') ? nameDe : name;
  final String? hauptstadt;
  final String kontinent;

  /// Wie viele Regionen der Datensatz für dieses Land kennt. **0 ist
  /// möglich** – Monaco und der Vatikan haben keine.
  final int regionenGesamt;

  /// Wie viele davon belegt sind, aus Fotos oder von Hand.
  final int regionenBesucht;

  /// Verschiedene Orte, aus Fotos oder von Hand.
  final int orte;

  /// Verortete Aufnahmen aus diesem Land.
  final int aufnahmen;

  /// Die eigene Marke, falls eine gesetzt ist.
  final Markenart? marke;

  const Landstand({
    required this.iso,
    required this.name,
    required this.nameDe,
    required this.hauptstadt,
    required this.kontinent,
    required this.regionenGesamt,
    required this.regionenBesucht,
    required this.orte,
    required this.aufnahmen,
    required this.marke,
  });

  /// Ob überhaupt etwas für einen Besuch spricht.
  ///
  /// „Geplant" zählt ausdrücklich **nicht**: Ein Vorhaben ist kein
  /// Besuch, und ein Länderzähler, der Absichten mitzählt, wäre wertlos.
  ///
  /// [orte] steht mit in der Reihe, und zwar wegen der 24 Länder **ohne
  /// verzeichnete Region**: Dort führt eine von Hand markierte Stadt zu
  /// keiner belegten Region, weil es keine gibt. Monte-Carlo abzuhaken und
  /// Monaco dennoch als unbesucht zu führen wäre für den, der es tut, nicht
  /// zu erklären. Bei allen übrigen Ländern ändert es nichts – dort belegt
  /// dieselbe Marke ohnehin schon ihre Region.
  bool get besucht =>
      aufnahmen > 0 ||
      regionenBesucht > 0 ||
      orte > 0 ||
      marke == Markenart.besucht;

  /// Ob für diesen Besuch **kein Foto** spricht, sondern nur die eigene
  /// Angabe.
  ///
  /// Die interessante Frage bei einer Länderliste: Worauf beruht der
  /// Haken? [aufnahmen] ist der Beleg der Kamera; alles andere –
  /// belegte Regionen, verzeichnete Orte, die Landmarke – kann von Hand
  /// gesetzt sein. Ein Land ohne eine einzige verortete Aufnahme zählt
  /// also, weil jemand es abgehakt hat, und das gehört sichtbar
  /// unterschieden statt in derselben Farbe zu verschwinden.
  bool get nurVonHand => besucht && aufnahmen == 0;

  Besuchsgrad get grad {
    if (!besucht) return Besuchsgrad.nicht;
    // Ein Land ohne verzeichnete Regionen ist mit dem ersten Beleg fertig
    // – es gibt nichts, was noch fehlen könnte. Die Alternative wäre,
    // Monaco für immer als „teilweise" zu führen.
    if (regionenGesamt == 0) return Besuchsgrad.vollstaendig;
    return regionenBesucht >= regionenGesamt
        ? Besuchsgrad.vollstaendig
        : Besuchsgrad.teilweise;
  }
}

/// Der Stand aller Länder, nach Namen sortiert.
///
/// [angaben] sind die Fotos, gruppiert wie in [reisefortschritt].
/// [nachIso] übersetzt den **Ländernamen** aus der Umkehr-Geokodierung in
/// den Code des Katalogs – beide stammen aus derselben Datei, der Name
/// trifft also. [regionscodes] tut dasselbe für Regionen, mit
/// „ISO|Regionsname" als Schlüssel.
///
/// [marken] sind die selbst gesetzten Haken. Eine Regionsmarke zählt für
/// den Regionenfortschritt ihres Landes mit – sonst hätte das Markieren
/// von Hand auf den Balken keine Wirkung, und niemand verstünde, warum.
List<Landstand> laenderstand({
  required Iterable<Besuchsangabe> angaben,
  required Iterable<Landeintragung> katalog,
  required Map<String, String> nachIso,
  required Map<String, String> regionscodes,
  Iterable<Markeneintrag> marken = const [],
}) {
  final aufnahmen = <String, int>{};
  final regionen = <String, Set<String>>{};
  final orte = <String, Set<String>>{};

  void merkeRegion(String iso, String schluessel) =>
      regionen.putIfAbsent(iso, () => {}).add(schluessel);

  for (final a in angaben) {
    final land = a.land;
    if (land == null || land.isEmpty) continue;
    final iso = nachIso[land];
    if (iso == null) continue;
    aufnahmen[iso] = (aufnahmen[iso] ?? 0) + a.anzahl;
    final region = a.region;
    if (region != null && region.isNotEmpty) {
      // Der Regionscode, wenn er sich auflösen lässt, sonst der Name.
      // Beides in denselben Topf: Zwei Schreibweisen derselben Region
      // wären zwei Regionen, und der Zähler liefe über sein eigenes Ziel
      // hinaus.
      merkeRegion(iso, regionscodes['$iso|$region'] ?? region);
    }
    final ort = a.ort;
    if (ort != null && ort.isNotEmpty) {
      orte.putIfAbsent(iso, () => {}).add('$region|$ort');
    }
  }

  final landmarken = <String, Markenart>{};
  for (final m in marken) {
    switch (m.art) {
      case 'land':
        // Eine zweite Marke für dasselbe Land kann es nicht geben – der
        // Schlüssel der Tabelle verhindert das.
        landmarken[m.schluessel.toUpperCase()] = m.wert;
      case 'region':
        if (m.wert != Markenart.besucht) continue;
        final punkt = m.schluessel.indexOf('.');
        if (punkt <= 0) continue;
        merkeRegion(m.schluessel.substring(0, punkt).toUpperCase(),
            m.schluessel);
      case 'ort':
        if (m.wert != Markenart.besucht) continue;
        final teile = ortsmarkeZerlegen(m.schluessel, nachIso);
        if (teile == null) continue;
        orte.putIfAbsent(teile.iso, () => {}).add('${teile.region}|${teile.ort}');
        if (teile.region.isNotEmpty) {
          merkeRegion(teile.iso,
              regionscodes['${teile.iso}|${teile.region}'] ?? teile.region);
        }
    }
  }

  return [
    for (final l in katalog)
      Landstand(
        iso: l.iso,
        name: l.name,
        nameDe: l.nameDe,
        hauptstadt: l.hauptstadt,
        kontinent: l.kontinent,
        regionenGesamt: l.regionen,
        regionenBesucht: regionen[l.iso]?.length ?? 0,
        orte: orte[l.iso]?.length ?? 0,
        aufnahmen: aufnahmen[l.iso] ?? 0,
        marke: landmarken[l.iso],
      ),
  ];
}
