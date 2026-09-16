/// Die Verwandtschaftslogik des Stammbaums – ohne Datenbank und ohne
/// Oberfläche.
///
/// Hier liegt der Teil, den man am fertigen Bild nicht beurteilen kann:
/// Ein Stammbaum sieht auch dann richtig aus, wenn eine Person versehentlich
/// ihre eigene Urgroßmutter ist – bis eine Auswertung im Kreis läuft. Als
/// Funktionen ist beides nachrechenbar.
library;

import 'package:meta/meta.dart';

/// Wie zwei Personen zusammenhängen.
enum Verwandtschaft {
  /// Die andere Person ist ein Elternteil. Gerichtet: Die Gegenrichtung
  /// heißt „Kind" und steckt in derselben Kante.
  elternteil,

  /// Adoptivelternteil. Zählt überall als Elternteil – im Baum, im
  /// Fächer, bei der Kreisprüfung –, nur die Bezeichnung ist eine andere.
  ///
  /// Als eigene Kantenart und nicht als Merkmal an der Person: Wer wen
  /// adoptiert hat, ist eine Eigenschaft der Verbindung, nicht des
  /// Menschen. Dieselbe Person kann leiblicher Vater des einen und
  /// Adoptivvater des anderen Kindes sein.
  adoptivelternteil,

  /// Pflegeelternteil. Wie [adoptivelternteil], aber ohne die
  /// Rechtsfolge – für Familien, die das unterscheiden.
  pflegeelternteil,

  /// Partnerschaft. Ungerichtet, deshalb nur einmal je Paar gespeichert.
  partner,
}

/// Die drei Arten, auf die jemand Elternteil sein kann.
const elternArten = {
  Verwandtschaft.elternteil,
  Verwandtschaft.adoptivelternteil,
  Verwandtschaft.pflegeelternteil,
};

bool istElternArt(Verwandtschaft art) => elternArten.contains(art);

/// Der Datenbankwert einer [Verwandtschaft]. Ausgeschrieben statt über
/// `index`, damit eine spätere Ergänzung der Aufzählung nicht die
/// Bedeutung bereits gespeicherter Zeilen verschiebt.
String artZuText(Verwandtschaft art) => switch (art) {
      Verwandtschaft.elternteil => 'elternteil',
      Verwandtschaft.adoptivelternteil => 'adoptiv',
      Verwandtschaft.pflegeelternteil => 'pflege',
      Verwandtschaft.partner => 'partner',
    };

Verwandtschaft? artAusText(String text) => switch (text) {
      'elternteil' => Verwandtschaft.elternteil,
      'adoptiv' => Verwandtschaft.adoptivelternteil,
      'pflege' => Verwandtschaft.pflegeelternteil,
      'partner' => Verwandtschaft.partner,
      _ => null,
    };

/// Eine gespeicherte Kante, gelesen wie in [Verwandtschaft] beschrieben.
typedef Kante = ({String personId, String andereId, Verwandtschaft art});

Kante kante(String personId, String andereId, Verwandtschaft art) =>
    (personId: personId, andereId: andereId, art: art);

/// Bringt eine Partnerkante in ihre gespeicherte Form: die kleinere
/// Kennung zuerst.
///
/// Ohne diese Festlegung entstünden für dasselbe Paar je nach
/// Eingaberichtung zwei verschiedene Zeilen – und ein späteres Entfernen
/// träfe nur eine davon.
Kante partnerKanteFuer(String a, String b) =>
    a.compareTo(b) <= 0 ? kante(a, b, Verwandtschaft.partner) : kante(b, a, Verwandtschaft.partner);

/// Alle Kanten in nachschlagbarer Form.
class Verwandtschaftsnetz {
  /// personId -> Elternteile
  final Map<String, Set<String>> _eltern = {};

  /// personId -> Kinder
  final Map<String, Set<String>> _kinder = {};

  /// personId -> Partner
  final Map<String, Set<String>> _partner = {};

  /// personId -> (Elternteil -> auf welche Art)
  ///
  /// Getrennt von [_eltern], damit alle Auswertungen – Baum, Fächer,
  /// Kreisprüfung – Adoptiv- und Pflegeeltern ohne Sonderfall als Eltern
  /// behandeln und trotzdem nachschlagen können, wie die Verbindung
  /// zustande kam.
  final Map<String, Map<String, Verwandtschaft>> _elternArt = {};

  Verwandtschaftsnetz(Iterable<Kante> kanten) {
    for (final k in kanten) {
      ergaenze(k);
    }
  }

  /// Trägt eine weitere Kante nach.
  ///
  /// Für Abläufe, die Kante um Kante gegen den **fortgeschriebenen**
  /// Stand prüfen – das Einlesen einer GEDCOM-Datei etwa. Der Weg über
  /// einen neuen `Verwandtschaftsnetz([...alt, neu])` je Kante wäre
  /// quadratisch und bei dreitausend Personen spürbar.
  void ergaenze(Kante k) {
    switch (k.art) {
      case Verwandtschaft.elternteil:
      case Verwandtschaft.adoptivelternteil:
      case Verwandtschaft.pflegeelternteil:
        _eltern.putIfAbsent(k.personId, () => {}).add(k.andereId);
        _kinder.putIfAbsent(k.andereId, () => {}).add(k.personId);
        _elternArt.putIfAbsent(k.personId, () => {})[k.andereId] = k.art;
      case Verwandtschaft.partner:
        // In beide Richtungen eingetragen, obwohl nur eine Zeile
        // gespeichert ist: Beim Nachschlagen soll die Richtung keine
        // Rolle spielen.
        _partner.putIfAbsent(k.personId, () => {}).add(k.andereId);
        _partner.putIfAbsent(k.andereId, () => {}).add(k.personId);
    }
  }

  Set<String> eltern(String id) => _eltern[id] ?? const {};

  /// Auf welche Art [elternteil] Elternteil von [kind] ist.
  ///
  /// `null`, wenn zwischen den beiden gar keine Elternkante steht.
  Verwandtschaft? elternArt(String kind, String elternteil) =>
      _elternArt[kind]?[elternteil];
  Set<String> kinder(String id) => _kinder[id] ?? const {};
  Set<String> partner(String id) => _partner[id] ?? const {};

  /// Geschwister: alle weiteren Kinder der eigenen Eltern.
  ///
  /// Halbgeschwister zählen mit – ein gemeinsamer Elternteil genügt. Die
  /// Unterscheidung wäre eine eigene Angabe, die hier niemand gemacht hat.
  Set<String> geschwister(String id) {
    final ergebnis = <String>{};
    for (final e in eltern(id)) {
      ergebnis.addAll(kinder(e));
    }
    return ergebnis..remove(id);
  }

  /// Ob [moeglicherVorfahre] über Elternkanten von [id] aus erreichbar ist
  /// – die Person selbst zählt mit.
  ///
  /// Die Suche merkt sich Besuchtes. Das ist nicht nur Beschleunigung:
  /// Enthält der Bestand bereits einen Kreis (etwa aus einer früheren
  /// Fassung ohne diese Prüfung), liefe sie sonst nicht mehr zurück.
  bool istVorfahreVon(String moeglicherVorfahre, String id) {
    final gesehen = <String>{};
    final rand = <String>[id];
    while (rand.isNotEmpty) {
      final aktuell = rand.removeLast();
      if (aktuell == moeglicherVorfahre) return true;
      if (!gesehen.add(aktuell)) continue;
      rand.addAll(eltern(aktuell));
    }
    return false;
  }
}

/// Warum sich eine Verwandtschaft nicht eintragen lässt.
enum Beziehungsfehler {
  /// Eine Person kann nicht mit sich selbst verwandt sein.
  mitSichSelbst,

  /// Der neue Elternteil ist bereits ein Nachkomme – die Kante würde einen
  /// Kreis schließen, in dem jede Auswertung nach oben endlos liefe.
  kreis,

  /// Genau diese Verwandtschaft steht schon fest.
  schonVorhanden,
}

/// Prüft, ob sich [andereId] als [art] von [personId] eintragen lässt.
///
/// Gibt `null` zurück, wenn nichts dagegen spricht.
Beziehungsfehler? pruefeBeziehung(
  Verwandtschaftsnetz netz,
  String personId,
  String andereId,
  Verwandtschaft art,
) {
  if (personId == andereId) return Beziehungsfehler.mitSichSelbst;
  // Gegen ALLE Elternarten geprüft, nicht nur gegen die gerade gewählte:
  // Jemanden, der schon leiblicher Vater ist, zusätzlich als Adoptivvater
  // einzutragen, wäre eine zweite Kante zwischen denselben beiden – und
  // die Bezeichnung wäre dann nicht mehr entscheidbar.
  final schonDa = istElternArt(art)
      ? netz.eltern(personId).contains(andereId)
      : netz.partner(personId).contains(andereId);
  if (schonDa) return Beziehungsfehler.schonVorhanden;
  if (istElternArt(art) && netz.istVorfahreVon(personId, andereId)) {
    return Beziehungsfehler.kreis;
  }
  return null;
}

/// Der Ausschnitt des Stammbaums, der um eine Person herum gezeigt wird.
///
/// Bewusst nur die unmittelbare Verwandtschaft. Großeltern und Enkel
/// stehen nicht mit im Bild, weil sich für sie keine Verbindungslinie
/// zeichnen lässt, die stimmt: Welcher Großelternteil zu welchem Elternteil
/// gehört, ginge in einer gemeinsamen Reihe verloren. Sie sind einen Klick
/// entfernt – wer auf einen Elternteil tippt, rückt ihn in die Mitte.
/// [weitereOben] und [weitereUnten] sagen vorher, ob dort etwas wartet.
class Stammbaumausschnitt {
  final String fokus;
  final List<String> eltern;
  final List<String> geschwister;
  final List<String> partner;
  final List<String> kinder;

  /// Die Seitenäste – leer, solange sie nicht angefordert werden.
  ///
  /// Der Baum zeigte bisher genau fünf Rollen: Eltern, Geschwister,
  /// Fokus, Partner, Kinder. Wer wissen wollte, wo seine Tante steht,
  /// musste erst auf sie zurücken. Diese vier Mengen sind der Rest der
  /// engeren Verwandtschaft, den man auf einem Blatt noch unterbringt.
  final List<String> grosseltern;

  /// Die Geschwister der Eltern.
  final List<String> onkelTanten;

  /// Die Kinder der Geschwister.
  final List<String> neffenNichten;

  /// Die Eltern der Partner.
  final List<String> schwiegereltern;

  /// Schwager und Schwägerin: die Partner der Geschwister **und** die
  /// Geschwister der Partner.
  ///
  /// **Eine Liste und nicht zwei.** Die beiden Wege dorthin sind
  /// verschieden, das Ergebnis ist es nicht – [verwandtschaftsgrad]
  /// kennt für beide nur `Gradart.schwager`, und im Sprachgebrauch gibt
  /// es die Unterscheidung auch nicht. Der Baum nannte diese Personen
  /// bisher gar nicht, obwohl der Verwandtschaftsrechner sie beim Namen
  /// nennt: Er sagte „Schwager", und der Baum zeigte niemanden.
  final List<String> schwaeger;

  /// Je Person: ob sie ihrerseits Eltern bzw. Kinder hat, die hier nicht
  /// gezeigt werden.
  final Map<String, bool> weitereOben;
  final Map<String, bool> weitereUnten;

  const Stammbaumausschnitt({
    required this.fokus,
    required this.eltern,
    required this.geschwister,
    required this.partner,
    required this.kinder,
    required this.weitereOben,
    required this.weitereUnten,
    this.grosseltern = const [],
    this.onkelTanten = const [],
    this.neffenNichten = const [],
    this.schwiegereltern = const [],
    this.schwaeger = const [],
  });

  /// „Leer" heißt weiterhin: um die Person herum steht niemand. Die
  /// Seitenäste zählen dabei nicht mit – sie können ohne Eltern gar nicht
  /// entstehen, und ein Ausschnitt, der nur aus Grosseltern bestünde,
  /// gibt es nicht.
  bool get istLeer =>
      eltern.isEmpty && geschwister.isEmpty && partner.isEmpty && kinder.isEmpty;
}

/// Stellt den Ausschnitt um [fokus] zusammen.
///
/// [reihenfolge] bestimmt, wie die Personen innerhalb einer Reihe stehen –
/// übergeben wird die nach Geburtsdatum und Name sortierte Liste aller
/// Kennungen. Ohne feste Reihenfolge sprängen die Karten bei jedem Aufbau
/// umher, weil die Mengen oben unsortiert sind.
///
/// [seitenlinien] nimmt Grosseltern, Onkel und Tanten, Neffen und Nichten,
/// Schwiegereltern sowie Schwager und Schwägerin dazu. Standardmäßig aus: Der schmale Ausschnitt
/// ist der, der auf jedem Fenster steht, und wer nur die gerade Linie
/// sucht, soll sie nicht zwischen Seitenästen suchen müssen.
Stammbaumausschnitt ausschnittUm(
  Verwandtschaftsnetz netz,
  String fokus,
  List<String> reihenfolge, {
  bool seitenlinien = false,
}) {
  final rang = {for (var i = 0; i < reihenfolge.length; i++) reihenfolge[i]: i};
  List<String> sortiert(Iterable<String> ids) =>
      ids.toList()..sort((a, b) => (rang[a] ?? 1 << 30).compareTo(rang[b] ?? 1 << 30));

  final eltern = sortiert(netz.eltern(fokus));
  final geschwister = sortiert(netz.geschwister(fokus));
  final partner = sortiert(netz.partner(fokus));
  final kinder = sortiert(netz.kinder(fokus));

  // Die Seitenäste. Jeder wird gegen die schon gezeigten Personen
  // abgezogen: In einer Familie, in der ein Cousin zugleich ein
  // Halbgeschwister ist, stünde dieselbe Karte sonst zweimal im Bild –
  // und zwei Karten für einen Menschen sind kein Baum, sondern ein
  // Fehler.
  final kern = {fokus, ...eltern, ...geschwister, ...partner, ...kinder};
  // Das `toSet()` ist nicht kosmetisch: Eine Person kann auf zwei Wegen
  // in dieselbe Liste geraten. Ein Schwager, der zugleich der Bruder der
  // eigenen Frau IST – zwei Geschwister haben zwei Geschwister geheiratet
  // –, kam sonst zweimal. Dasselbe gilt für Grosseltern, wenn die Eltern
  // Cousins sind. Beides kommt in echten Familien vor.
  List<String> ohneKern(Iterable<String> ids, Set<String> schon) => sortiert(
      ids.toSet().where((id) => !kern.contains(id) && !schon.contains(id)));

  var grosseltern = const <String>[];
  var onkelTanten = const <String>[];
  var neffenNichten = const <String>[];
  var schwiegereltern = const <String>[];
  var schwaeger = const <String>[];
  if (seitenlinien) {
    final belegt = <String>{};
    grosseltern = ohneKern(
        [for (final e in eltern) ...netz.eltern(e)], belegt);
    belegt.addAll(grosseltern);
    onkelTanten =
        ohneKern([for (final e in eltern) ...netz.geschwister(e)], belegt);
    belegt.addAll(onkelTanten);
    schwiegereltern =
        ohneKern([for (final p in partner) ...netz.eltern(p)], belegt);
    belegt.addAll(schwiegereltern);
    neffenNichten =
        ohneKern([for (final g in geschwister) ...netz.kinder(g)], belegt);
    belegt.addAll(neffenNichten);
    // Beide Richtungen, wie im Verwandtschaftsrechner: der Partner meines
    // Geschwisters und das Geschwister meines Partners.
    schwaeger = ohneKern([
      for (final g in geschwister) ...netz.partner(g),
      for (final p in partner) ...netz.geschwister(p),
    ], belegt);
  }

  // Ein Hinweis bedeutet: „von dieser Person geht es weiter, aber das
  // Weitere steht nicht in diesem Bild". Also genau dann, wenn nicht alle
  // Eltern bzw. Kinder unter den gezeigten Personen sind.
  //
  // Als eine Regel statt als Aufzählung von Sonderfällen. Der erste Versuch
  // setzte den Hinweis an Eltern, Fokus und Kindern von Hand ab – und
  // übersah dabei die Geschwister, deren Eltern ja mit im Bild stehen. Wer
  // dagegen fragt „ist alles Angrenzende zu sehen?", trifft auch die Fälle,
  // an die niemand gedacht hat: das Halbgeschwister mit einem zweiten,
  // nicht gezeigten Elternteil, oder den Partner mit Kindern aus einer
  // früheren Verbindung.
  final imBild = {
    ...kern,
    ...grosseltern,
    ...onkelTanten,
    ...neffenNichten,
    ...schwiegereltern,
    ...schwaeger,
  };
  final weitereOben = <String, bool>{};
  final weitereUnten = <String, bool>{};
  for (final id in imBild) {
    weitereOben[id] = !imBild.containsAll(netz.eltern(id));
    weitereUnten[id] = !imBild.containsAll(netz.kinder(id));
  }

  return Stammbaumausschnitt(
    fokus: fokus,
    eltern: eltern,
    geschwister: geschwister,
    partner: partner,
    kinder: kinder,
    grosseltern: grosseltern,
    onkelTanten: onkelTanten,
    neffenNichten: neffenNichten,
    schwiegereltern: schwiegereltern,
    schwaeger: schwaeger,
    weitereOben: weitereOben,
    weitereUnten: weitereUnten,
  );
}

/// Die Lebensspanne als Zeile unter dem Namen, etwa „1931–2004", „*1972"
/// oder „†2004".
///
/// Gibt `null` zurück, wenn nichts bekannt ist – dann bleibt die Zeile
/// weg, statt einen leeren Gedankenstrich zu zeigen.
String? lebensspanne(DateTime? geburt, DateTime? tod, {String geboren = '*', String gestorben = '†'}) {
  if (geburt == null && tod == null) return null;
  if (geburt != null && tod != null) return '${geburt.year}–${tod.year}';
  if (geburt != null) return '$geboren${geburt.year}';
  return '$gestorben${tod!.year}';
}

// ---------------------------------------------------------------------
// Das Geflecht: Haushalte statt Reihen
// ---------------------------------------------------------------------

/// Eine Person und ihre Partner als **eine** Einheit.
///
/// **Warum das die richtige Klammer ist.** Der Ausschnitt oben führt
/// Listen nach Rolle: Eltern, Geschwister, Schwäger. Eine Reihe kann aber
/// nicht ausdrücken, zu **welcher** Schwester ein Schwager gehört – bei
/// den Grosseltern steht dieser Verzicht sogar ausdrücklich im Baum
/// („bewusst ohne Verbindungslinie"). Genau danach war gefragt: den Ast
/// zu sehen, nicht die Reihe.
///
/// Ein Haushalt löst das, ohne einen Sonderfall zu brauchen. Der Schwager
/// steht im Haushalt seiner Frau, seine Eltern hängen an **ihm** – und
/// das ist dieselbe Elternkante wie die von der Mitte zu ihren Eltern.
@immutable
class Haushalt {
  /// Die Person, an der der Haushalt hängt.
  final String anker;

  /// Ihre Partner, in der Reihenfolge des Baums.
  final List<String> partner;

  const Haushalt(this.anker, this.partner);

  /// Alle Bewohner, Anker zuerst.
  List<String> get personen => [anker, ...partner];

  /// Der Haushalt wird über seinen Anker benannt.
  String get id => anker;

  @override
  bool operator ==(Object other) =>
      other is Haushalt &&
      other.anker == anker &&
      other.partner.length == partner.length &&
      other.partner.every(partner.contains);

  @override
  int get hashCode => Object.hash(anker, Object.hashAllUnordered(partner));

  @override
  String toString() => 'Haushalt($anker${partner.isEmpty ? '' : '+$partner'})';
}

/// Wie viele Haushalte ein Generationsband höchstens trägt.
///
/// Vier Geschwister mit Partnern, deren Eltern und deren Geschwistern sind
/// schnell zwanzig Schilder in zwei Bändern – und ein Bild, in dem man
/// nichts mehr findet. Was die Grenze schluckt, wird gezählt und genannt
/// (siehe [Stammbaumgeflecht.verschwiegen]); stillschweigend wegzulassen
/// wäre das Schlimmste von beidem.
const maxHaushalteJeBand = 12;

/// Das Geflecht um eine Person: wer mit wem lebt, wer von wem abstammt.
@immutable
class Stammbaumgeflecht {
  final String fokus;

  /// Alle Haushalte, nach Band und darin nach der Reihenfolge des Baums.
  final List<Haushalt> haushalte;

  /// Haushalt -> Generationsband. 0 ist die Mitte, negativ nach oben.
  final Map<String, int> band;

  /// **Person** -> die Haushalte ihrer Eltern, in der Reihenfolge des Baums.
  ///
  /// An der Person und nicht am Haushalt: In einem Geschwisterhaushalt
  /// leben zwei Menschen mit **verschiedenen** Eltern. Die Schwester
  /// stammt von meinen Eltern ab, ihr Mann von seinen. Genau diese beiden
  /// Linien nebeneinander sind das, was ein Ast zeigen soll – am Haushalt
  /// festgemacht wäre eine von beiden gelogen.
  ///
  /// **Und es ist eine Liste, kein einzelner Wert.** Wohnen Vater und
  /// Mutter zusammen, ist es ein Haushalt und damit ein Ast. Leben sie
  /// getrennt, sind es zwei – und wer hier nur den ersten führt, lässt
  /// den zweiten Elternteil ohne Ast im Bild stehen. Genau so war es
  /// gemeldet: Der Vater hing an nichts, weil die Mutter zuerst kam.
  final Map<String, List<String>> elternhaeuserVon;

  /// Je Person: ob über bzw. unter ihr noch etwas steht, das dieses Bild
  /// nicht zeigt.
  final Map<String, bool> weitereOben;
  final Map<String, bool> weitereUnten;

  /// Wie viele Haushalte die Bandgrenze weggelassen hat.
  final int verschwiegen;

  const Stammbaumgeflecht({
    required this.fokus,
    required this.haushalte,
    required this.band,
    required this.elternhaeuserVon,
    required this.weitereOben,
    required this.weitereUnten,
    this.verschwiegen = 0,
  });

  /// Der Haushalt, in dem [person] lebt, oder `null`.
  Haushalt? haushaltVon(String person) {
    for (final h in haushalte) {
      if (h.personen.contains(person)) return h;
    }
    return null;
  }

  /// Alle Haushalte eines Bandes, in ihrer Reihenfolge.
  List<Haushalt> imBand(int nummer) =>
      [for (final h in haushalte) if (band[h.id] == nummer) h];

  /// Alle Personen im Bild.
  Set<String> get personen => {for (final h in haushalte) ...h.personen};
}

/// Stellt das Geflecht um [fokus] zusammen.
///
/// [reihenfolge] ist dieselbe Liste wie bei [ausschnittUm] – nach
/// Geburtsdatum und Name. Ohne sie sprängen die Haushalte bei jedem
/// Aufbau umher.
///
/// Der Baum reicht in beide Richtungen gleich weit: drei Generationen
/// hinauf (Urgrosseltern) und drei hinab (Urenkel). Die erste Fassung
/// ging nur eine hinab – ein Fehler, der beim ersten Blick auf eine
/// echte Familie auffiel und den die App sogar selbst zugab, indem sie
/// unter den Kindern ein Mehrzeichen setzte.
///
/// **Die Ringe sind aufgezählt, nicht gerechnet.** Ein Suchlauf mit
/// Schrittbudget wäre kürzer und brächte lauter Verwandte mit, nach denen
/// niemand gefragt hat – Cousins ersten Grades allein sind bei vier
/// Onkeln mit je drei Kindern zwölf zusätzliche Schilder in derselben
/// Reihe wie die Geschwister. Was hier steht, steht hier absichtlich.
Stammbaumgeflecht geflechtUm(
  Verwandtschaftsnetz netz,
  String fokus,
  List<String> reihenfolge,
) {
  final rang = {for (var i = 0; i < reihenfolge.length; i++) reihenfolge[i]: i};
  int platz(String id) => rang[id] ?? 1 << 30;
  List<String> sortiert(Iterable<String> ids) =>
      ids.toSet().toList()..sort((a, b) => platz(a).compareTo(platz(b)));

  final vergeben = <String>{};
  final haushalte = <Haushalt>[];
  final band = <String, int>{};
  var verschwiegen = 0;

  /// Legt für jeden noch freien Anker einen Haushalt im Band [nummer] an.
  ///
  /// Wer schon wohnt, zieht nicht um: Eine Person, die auf zwei Wegen
  /// erreichbar ist – der Cousin, der zugleich ein Halbgeschwister ist –,
  /// stünde sonst zweimal im Bild. Zwei Schilder für einen Menschen sind
  /// kein Baum, sondern ein Fehler.
  void hausen(Iterable<String> anker, int nummer) {
    var imBand = band.values.where((b) => b == nummer).length;
    for (final a in sortiert(anker)) {
      if (vergeben.contains(a)) continue;
      if (imBand >= maxHaushalteJeBand) {
        verschwiegen++;
        continue;
      }
      final mitbewohner =
          sortiert(netz.partner(a).where((x) => x != a && !vergeben.contains(x)));
      haushalte.add(Haushalt(a, mitbewohner));
      band[a] = nummer;
      vergeben.add(a);
      vergeben.addAll(mitbewohner);
      imBand++;
    }
  }

  // Ring 0 – die Mitte. Zuerst, damit ihr Partner nirgends sonst landet.
  hausen([fokus], 0);
  final eigenePartner = netz.partner(fokus);

  // Ring 1 – Eltern, Geschwister, Kinder.
  hausen(netz.eltern(fokus), -1);
  hausen(netz.geschwister(fokus), 0);
  hausen(netz.kinder(fokus), 1);

  // Ring 2. Die Schwäger stehen hier NICHT als eigener Punkt: Der Partner
  // eines Geschwisters wohnt längst in dessen Haushalt, und genau das war
  // der Sinn der Übung.
  final eltern = sortiert(netz.eltern(fokus));
  final geschwister = sortiert(netz.geschwister(fokus));
  hausen([for (final e in eltern) ...netz.eltern(e)], -2);
  hausen([for (final e in eltern) ...netz.geschwister(e)], -1);
  hausen([for (final p in eigenePartner) ...netz.eltern(p)], -1);
  hausen([for (final p in eigenePartner) ...netz.geschwister(p)], 0);
  hausen([for (final g in geschwister) ...netz.kinder(g)], 1);
  // Enkel. **Sie fehlten bis zur Meldung ganz**: Der Baum reichte drei
  // Generationen hinauf und eine hinab. Eine Ahnentafel darf das, ein
  // Familienbaum nicht – zumal die App mit ihrem Mehrzeichen selbst
  // sagte, dass da unten noch etwas ist.
  final kinder = sortiert(netz.kinder(fokus));
  hausen([for (final k in kinder) ...netz.kinder(k)], 2);

  // Ring 3 – eine Stufe weiter, wie besprochen. Die Schwäger sind hier
  // die Partner der Geschwister; ihre Eltern und Geschwister sind das,
  // wonach ausdrücklich gefragt war.
  final schwaeger = sortiert([for (final g in geschwister) ...netz.partner(g)]);
  final grosseltern =
      sortiert([for (final e in eltern) ...netz.eltern(e)]);
  hausen([for (final g in grosseltern) ...netz.eltern(g)], -3);
  hausen([for (final s in schwaeger) ...netz.eltern(s)], -1);
  hausen([for (final s in schwaeger) ...netz.geschwister(s)], 0);
  hausen([
    for (final p in eigenePartner)
      for (final se in netz.eltern(p)) ...netz.eltern(se)
  ], -2);
  // Und ebenso weit hinab: Urenkel, und die Kinder der Neffen und
  // Nichten. Damit reicht der Baum in beide Richtungen gleich weit.
  final enkel = sortiert([for (final k in kinder) ...netz.kinder(k)]);
  final neffenNichten =
      sortiert([for (final g in geschwister) ...netz.kinder(g)]);
  hausen([for (final e in enkel) ...netz.kinder(e)], 3);
  hausen([for (final n in neffenNichten) ...netz.kinder(n)], 2);

  // Die Elternkante je Person – nur dorthin, wo das Elternhaus im Bild
  // steht. Ein Ast ins Leere wäre eine Behauptung über etwas, das man
  // nicht sieht; dafür gibt es das Mehrzeichen unten.
  final wohntIn = <String, String>{
    for (final h in haushalte)
      for (final person in h.personen) person: h.id,
  };
  final elternhaeuserVon = <String, List<String>>{};
  for (final person in wohntIn.keys) {
    final haeuser = <String>[];
    for (final e in sortiert(netz.eltern(person))) {
      final haus = wohntIn[e];
      // Zusammenlebende Eltern sind ein Haushalt und bekommen einen Ast;
      // getrennt lebende zwei. Der Zusatz filtert also nicht doppelte
      // Eltern, sondern doppelte **Häuser**.
      if (haus != null && !haeuser.contains(haus)) haeuser.add(haus);
    }
    if (haeuser.isNotEmpty) elternhaeuserVon[person] = haeuser;
  }

  // Dieselbe Regel wie in [ausschnittUm]: Ein Mehrzeichen heisst „hier
  // geht es weiter, aber nicht in diesem Bild".
  final imBild = wohntIn.keys.toSet();
  final weitereOben = <String, bool>{};
  final weitereUnten = <String, bool>{};
  for (final id in imBild) {
    weitereOben[id] = !imBild.containsAll(netz.eltern(id));
    weitereUnten[id] = !imBild.containsAll(netz.kinder(id));
  }

  haushalte.sort((a, b) {
    final bandVergleich = band[a.id]!.compareTo(band[b.id]!);
    return bandVergleich != 0 ? bandVergleich : platz(a.anker).compareTo(platz(b.anker));
  });

  return Stammbaumgeflecht(
    fokus: fokus,
    haushalte: haushalte,
    band: band,
    elternhaeuserVon: elternhaeuserVon,
    weitereOben: weitereOben,
    weitereUnten: weitereUnten,
    verschwiegen: verschwiegen,
  );
}

/// Der Nachname, der in dieser Familie am häufigsten vorkommt – für die
/// Zeile unter dem Stamm.
///
/// `null`, wenn kein Name mindestens zweimal auftaucht. Bei einer Familie
/// aus lauter verschiedenen Nachnamen einen davon unter den Baum zu
/// schreiben wäre eine Behauptung darüber, wessen Baum das ist.
///
/// Als letztes Wort des Namens gelesen. Das trifft „Anna Meier" und
/// „Hans von Berg", nicht aber Namen, die andersherum geschrieben werden –
/// dafür bräuchte es ein eigenes Feld, und das gibt es nicht.
String? haeufigsterNachname(Iterable<String> namen) {
  final zaehler = <String, int>{};
  for (final name in namen) {
    final teile = name.trim().split(RegExp(r'\s+'));
    if (teile.length < 2) continue;
    final nachname = teile.last;
    if (nachname.isEmpty) continue;
    zaehler.update(nachname, (n) => n + 1, ifAbsent: () => 1);
  }
  String? beste;
  var meiste = 1;
  // Bei Gleichstand der alphabetisch erste – nicht weil er der bessere
  // wäre, sondern damit dieselbe Familie zweimal denselben Namen zeigt.
  for (final name in zaehler.keys.toList()..sort()) {
    if (zaehler[name]! > meiste) {
      meiste = zaehler[name]!;
      beste = name;
    }
  }
  return beste;
}
