/// Wie zwei Personen zueinander stehen – „Schwester", „Urgroßvater",
/// „Schwägerin", „Cousine 2. Grades".
///
/// Getrennt von [stammbaum.dart], weil hier eine andere Frage beantwortet
/// wird: Dort geht es um die Kanten selbst, hier um ihre Deutung. Und weil
/// sich diese Deutung am fertigen Bild nicht prüfen lässt – ob jemand der
/// Großonkel oder der Cousin zweiten Grades ist, sieht man einer Karte
/// nicht an, sondern rechnet es nach.
library;

import 'package:meta/meta.dart';

import 'stammbaum.dart';

/// Nur für die Bezeichnungen erhoben, siehe `People.geschlecht`.
enum Geschlecht { weiblich, maennlich, divers }

String geschlechtZuText(Geschlecht g) => switch (g) {
      Geschlecht.weiblich => 'w',
      Geschlecht.maennlich => 'm',
      Geschlecht.divers => 'd',
    };

Geschlecht? geschlechtAusText(String? text) => switch (text) {
      'w' => Geschlecht.weiblich,
      'm' => Geschlecht.maennlich,
      'd' => Geschlecht.divers,
      _ => null,
    };

/// Der ICU-Auswahlwert für die Textbausteine: `w`, `m` oder `other`.
///
/// „Divers" und „nicht angegeben" fallen beide auf `other` und damit auf
/// die geschlechtsneutrale Form („Geschwister" statt „Bruder"). Das ist
/// kein Gleichsetzen der beiden Zustände, sondern die Feststellung, dass
/// die deutsche wie die englische Verwandtschaftssprache für beide keine
/// eigene Form bereithält.
String auswahlwert(Geschlecht? g) => switch (g) {
      Geschlecht.weiblich => 'w',
      Geschlecht.maennlich => 'm',
      _ => 'other',
    };

/// Die Art der Verwandtschaft. [Grad] hält zusätzlich die Abstände.
enum Gradart {
  /// Die Person selbst.
  selbst,

  /// Vater, Großvater, Urgroßvater … – [Grad.aufwaerts] Stufen nach oben.
  vorfahre,

  /// Sohn, Enkel, Urenkel … – [Grad.abwaerts] Stufen nach unten.
  nachkomme,

  /// Bruder, Schwester – bei [Grad.halb] nur ein gemeinsamer Elternteil.
  geschwister,

  /// Neffe, Großneffe … – [Grad.abwaerts] Stufen unter dem Geschwister.
  geschwisterkind,

  /// Onkel, Großonkel … – Geschwister eines Vorfahren.
  vorfahrengeschwister,

  /// Cousin/Cousine. Der Grad ist `min(aufwaerts, abwaerts) - 1`, die
  /// Entfernung `(aufwaerts - abwaerts).abs()`.
  cousin,

  partner,

  /// Geschwister des Partners oder Partner eines Geschwisters.
  schwager,

  /// Elternteil des Partners.
  schwiegerelternteil,

  /// Partner eines Kindes.
  schwiegerkind,

  /// Partner eines Elternteils, der nicht selbst Elternteil ist.
  stiefelternteil,

  /// Kind des Partners, das nicht das eigene ist.
  stiefkind,

  /// Kind eines Stiefelternteils, das kein Geschwister ist.
  stiefgeschwister,

  /// Über eine Partnerschaft verbunden, aber keiner der obigen Fälle.
  angeheiratet,

  /// Kein Weg zwischen den beiden gefunden.
  keine,
}

/// Das Ergebnis einer Berechnung.
class Grad {
  final Gradart art;

  /// Stufen von der Ausgangsperson zum nächsten gemeinsamen Vorfahren.
  final int aufwaerts;

  /// Stufen vom gemeinsamen Vorfahren zur anderen Person.
  final int abwaerts;

  /// Nur ein gemeinsamer Elternteil (Halbgeschwister).
  final bool halb;

  /// Bei einer **unmittelbaren** Eltern- oder Kindbeziehung: auf welche
  /// Art. Sonst `null`.
  ///
  /// Nur unmittelbar, weil es für alles Weitere keine Wörter gibt: Der
  /// Vater eines Adoptivvaters heißt Großvater, nicht
  /// „Adoptiv-Großvater“. Die Unterscheidung endet dort, wo die Sprache
  /// sie nicht mehr macht.
  final Verwandtschaft? elternArt;

  const Grad(this.art,
      {this.aufwaerts = 0,
      this.abwaerts = 0,
      this.halb = false,
      this.elternArt});

  /// Der Cousin-Grad nach üblicher Zählung: Kinder von Geschwistern sind
  /// Cousins ersten Grades.
  int get cousinGrad =>
      (aufwaerts < abwaerts ? aufwaerts : abwaerts) - 1;

  /// Wie viele Generationen die beiden auseinanderliegen („einmal
  /// entfernt").
  int get entfernung => (aufwaerts - abwaerts).abs();

  @override
  bool operator ==(Object other) =>
      other is Grad &&
      other.art == art &&
      other.aufwaerts == aufwaerts &&
      other.abwaerts == abwaerts &&
      other.halb == halb &&
      other.elternArt == elternArt;

  @override
  int get hashCode => Object.hash(art, aufwaerts, abwaerts, halb, elternArt);

  // Pfeile statt Wörtern: Diese Zeile erscheint nur in Fehlermeldungen
  // von Tests, aber der Wächter für feste Oberflächentexte kann das nicht
  // wissen und hielte „auf"/„ab" für einen deutschen Satz im Quelltext.
  @override
  String toString() =>
      'Grad(${art.name} ↑$aufwaerts ↓$abwaerts${halb ? ' ½' : ''})';
}

/// Wie weit darf gesucht werden.
///
/// Ohne Grenze durchsucht eine große, gut gepflegte Familie bei jeder
/// Karte den kompletten Baum. Zehn Generationen decken alles ab, wofür es
/// überhaupt noch eine Bezeichnung gibt – darüber hinaus stünde ohnehin
/// nur „Vorfahre der 14. Generation".
const _maxTiefe = 10;

/// Alle Vorfahren einer Person mit ihrem Abstand, die Person selbst mit 0.
///
/// Bei mehreren Wegen (dieselbe Person ist Ur- und Ururgroßvater, weil sich
/// zwei Familienzweige wieder treffen) zählt der kürzeste – die üblichere
/// und die für die Bezeichnung passende Lesart.
Map<String, int> vorfahrenMitAbstand(Verwandtschaftsnetz netz, String id) {
  final abstand = <String, int>{id: 0};
  var rand = <String>{id};
  for (var tiefe = 1; tiefe <= _maxTiefe && rand.isNotEmpty; tiefe++) {
    final naechste = <String>{};
    for (final person in rand) {
      for (final elternteil in netz.eltern(person)) {
        if (abstand.containsKey(elternteil)) continue;
        abstand[elternteil] = tiefe;
        naechste.add(elternteil);
      }
    }
    rand = naechste;
  }
  return abstand;
}

/// Bestimmt, wie [andere] zu [ich] steht.
///
/// Blutsverwandtschaft geht vor Anheirat: Wer die Cousine geheiratet hat,
/// bleibt in erster Linie ihr Cousin. Innerhalb der Blutsverwandtschaft
/// gewinnt der kürzeste Weg über den nächsten gemeinsamen Vorfahren.
Grad bestimmeGrad(Verwandtschaftsnetz netz, String ich, String andere) {
  if (ich == andere) return const Grad(Gradart.selbst);

  final blut = _blutsverwandtschaft(netz, ich, andere);
  if (blut != null) return blut;

  return _angeheiratet(netz, ich, andere);
}

Grad? _blutsverwandtschaft(Verwandtschaftsnetz netz, String ich, String andere) {
  final meine = vorfahrenMitAbstand(netz, ich);
  final ihre = vorfahrenMitAbstand(netz, andere);

  int? bestesAuf, bestesAb;
  for (final eintrag in meine.entries) {
    final ab = ihre[eintrag.key];
    if (ab == null) continue;
    final auf = eintrag.value;
    if (bestesAuf == null || auf + ab < bestesAuf + bestesAb!) {
      bestesAuf = auf;
      bestesAb = ab;
    }
  }
  if (bestesAuf == null) return null;
  final auf = bestesAuf, ab = bestesAb!;

  if (auf == 0) {
    return Grad(Gradart.nachkomme,
        abwaerts: ab,
        elternArt: ab == 1 ? netz.elternArt(andere, ich) : null);
  }
  if (ab == 0) {
    return Grad(Gradart.vorfahre,
        aufwaerts: auf,
        elternArt: auf == 1 ? netz.elternArt(ich, andere) : null);
  }
  if (auf == 1 && ab == 1) {
    return Grad(Gradart.geschwister,
        aufwaerts: 1, abwaerts: 1, halb: _istHalbgeschwister(netz, ich, andere));
  }
  if (auf == 1) return Grad(Gradart.geschwisterkind, aufwaerts: 1, abwaerts: ab);
  if (ab == 1) return Grad(Gradart.vorfahrengeschwister, aufwaerts: auf, abwaerts: 1);
  return Grad(Gradart.cousin, aufwaerts: auf, abwaerts: ab);
}

/// Halbgeschwister teilen genau einen Elternteil, obwohl mindestens einer
/// der beiden zwei eingetragen hat.
///
/// Die zweite Bedingung ist der Punkt: Sind bei beiden nur ein Elternteil
/// bekannt, ist der eine gemeinsame Elternteil alles, was man weiß – daraus
/// „halb" zu schließen wäre eine Behauptung über den nicht eingetragenen
/// zweiten. Dann bleibt es bei „Bruder".
bool _istHalbgeschwister(Verwandtschaftsnetz netz, String a, String b) {
  final meine = netz.eltern(a);
  final ihre = netz.eltern(b);
  final gemeinsam = meine.intersection(ihre).length;
  if (gemeinsam != 1) return false;
  return meine.length > 1 || ihre.length > 1;
}

Grad _angeheiratet(Verwandtschaftsnetz netz, String ich, String andere) {
  if (netz.partner(ich).contains(andere)) return const Grad(Gradart.partner);

  // Schwager/Schwägerin – von beiden Seiten aus dieselbe Bezeichnung.
  for (final p in netz.partner(ich)) {
    if (netz.geschwister(p).contains(andere)) return const Grad(Gradart.schwager);
  }
  for (final g in netz.geschwister(ich)) {
    if (netz.partner(g).contains(andere)) return const Grad(Gradart.schwager);
  }

  for (final p in netz.partner(ich)) {
    if (netz.eltern(p).contains(andere)) {
      return const Grad(Gradart.schwiegerelternteil);
    }
  }
  for (final k in netz.kinder(ich)) {
    if (netz.partner(k).contains(andere)) return const Grad(Gradart.schwiegerkind);
  }

  // Stiefverwandtschaft. Die Prüfung „nicht schon blutsverwandt" ist oben
  // erledigt: Hierher kommt nur, wer keinen gemeinsamen Vorfahren hat.
  for (final e in netz.eltern(ich)) {
    if (netz.partner(e).contains(andere)) return const Grad(Gradart.stiefelternteil);
    for (final stief in netz.partner(e)) {
      if (netz.kinder(stief).contains(andere)) {
        return const Grad(Gradart.stiefgeschwister);
      }
    }
  }
  for (final p in netz.partner(ich)) {
    if (netz.kinder(p).contains(andere)) return const Grad(Gradart.stiefkind);
  }

  // Irgendwo über eine Partnerschaft verbunden, aber ohne eigene
  // Bezeichnung – „angeheiratet" ist dafür die ehrliche Auskunft.
  if (_ueberPartnerErreichbar(netz, ich, andere)) {
    return const Grad(Gradart.angeheiratet);
  }
  return const Grad(Gradart.keine);
}

/// Ob sich [andere] von [ich] aus über Eltern-, Kind- und Partnerkanten
/// überhaupt erreichen lässt.
bool _ueberPartnerErreichbar(Verwandtschaftsnetz netz, String ich, String andere) {
  final gesehen = <String>{ich};
  var rand = <String>{ich};
  for (var tiefe = 0; tiefe < _maxTiefe && rand.isNotEmpty; tiefe++) {
    final naechste = <String>{};
    for (final person in rand) {
      for (final nachbar in [
        ...netz.eltern(person),
        ...netz.kinder(person),
        ...netz.partner(person),
      ]) {
        if (nachbar == andere) return true;
        if (gesehen.add(nachbar)) naechste.add(nachbar);
      }
    }
    rand = naechste;
  }
  return false;
}

/// Der Weg zu jemandem, für den es kein eigenes Wort gibt.
///
/// „Die Eltern meines Schwagers" heissen auf Deutsch nicht anders als
/// „angeheiratet" – dieselbe Auskunft, die auch der entfernte Vetter der
/// zweiten Frau des Onkels bekäme. Genau das war der Anlass: Im Baum
/// stand bei einer Person, die man beim Namen kennt, ein Wort, das nichts
/// sagt.
///
/// Statt eines Wortes wird deshalb der Weg beschrieben: über wen die
/// Verbindung läuft, und wie die Gesuchte zu **dieser** Person steht.
@immutable
class Umweg {
  /// Über wen der Weg läuft – jemand, für den es ein Wort gibt.
  final String ueber;

  /// Wie die Zwischenperson zu mir steht („Schwager").
  final Grad ueberGrad;

  /// Wie die gesuchte Person zur Zwischenperson steht („Mutter").
  final Grad schritt;

  const Umweg(this.ueber, this.ueberGrad, this.schritt);

  @override
  bool operator ==(Object other) =>
      other is Umweg &&
      other.ueber == ueber &&
      other.ueberGrad == ueberGrad &&
      other.schritt == schritt;

  @override
  int get hashCode => Object.hash(ueber, ueberGrad, schritt);

  @override
  String toString() => 'Umweg($ueber ${ueberGrad.art.name}/${schritt.art.name})';
}

/// Nur diese Schritte taugen für den zweiten Teil des Satzes.
///
/// Eine **einzelne** Kante, sonst wird aus der Auskunft eine Kette: „Der
/// Grossvater des Bruders des Schwagers" erklärt weniger als
/// „angeheiratet", weil man ihn beim Lesen zurückverfolgen muss.
bool _einSchritt(Grad grad) => switch (grad.art) {
      Gradart.vorfahre => grad.aufwaerts == 1,
      Gradart.nachkomme => grad.abwaerts == 1,
      Gradart.geschwister || Gradart.partner => true,
      _ => false,
    };

/// Ob es für diesen Grad ein Wort gibt, das für sich steht.
bool _hatEigenesWort(Grad grad) =>
    grad.art != Gradart.angeheiratet &&
    grad.art != Gradart.keine &&
    grad.art != Gradart.selbst;

/// Beschreibt [andere] über eine Zwischenperson – oder `null`, wenn es
/// dafür keinen Anlass gibt oder auch das nicht trägt.
///
/// **Kein Umweg, wo ein Wort steht.** Der Schwager heisst Schwager, nicht
/// „Mann von Schwester Anna". Diese Prüfung steht hier und nicht beim
/// Aufrufer: Sonst könnte eine zweite Aufrufstelle irgendwann ein gutes
/// Wort durch einen umständlichen Satz ersetzen, ohne dass es jemandem
/// auffällt.
///
/// Gesucht wird bei den unmittelbaren Angehörigen von [andere] – Eltern,
/// Kinder, Partner, Geschwister. Wer davon selbst einen Namen hat
/// („Schwager"), trägt den Satz.
///
/// [reihenfolge] entscheidet bei Gleichstand und muss dieselbe sein, die
/// der Baum ohnehin führt. Ohne sie hiesse dieselbe Person bei jedem
/// Aufbau anders, sobald zwei Wege gleich gut sind – und das fiele als
/// Flackern auf, nicht als Fehler.
Umweg? umwegZu(
  Verwandtschaftsnetz netz,
  String ich,
  String andere, {
  int Function(String)? reihenfolge,
}) {
  if (ich == andere) return null;
  if (_hatEigenesWort(bestimmeGrad(netz, ich, andere))) return null;

  final nachbarn = <String>{
    ...netz.eltern(andere),
    ...netz.kinder(andere),
    ...netz.partner(andere),
    ...netz.geschwister(andere),
  }..remove(andere);

  Umweg? beste;
  int? besterRang;
  int? besterPlatz;
  for (final ueber in nachbarn) {
    if (ueber == ich) continue;
    final ueberGrad = bestimmeGrad(netz, ich, ueber);
    if (!_hatEigenesWort(ueberGrad)) continue;
    final schritt = bestimmeGrad(netz, ueber, andere);
    if (!_einSchritt(schritt)) continue;

    final rang = naeheRang(ueberGrad);
    final platz = reihenfolge?.call(ueber) ?? 0;
    if (besterRang == null ||
        rang < besterRang ||
        (rang == besterRang && platz < besterPlatz!)) {
      beste = Umweg(ueber, ueberGrad, schritt);
      besterRang = rang;
      besterPlatz = platz;
    }
  }
  return beste;
}

/// Alle Personen, zu denen von [ich] aus eine Verwandtschaft besteht, samt
/// Grad – für die Verwandtenliste.
///
/// Ohne die Ausgangsperson selbst und ohne die Fälle ohne Verbindung; wer
/// gar nicht verwandt ist, gehört nicht in eine Verwandtenliste.
Map<String, Grad> alleGrade(Verwandtschaftsnetz netz, String ich, Iterable<String> personen) {
  final ergebnis = <String, Grad>{};
  for (final andere in personen) {
    if (andere == ich) continue;
    final grad = bestimmeGrad(netz, ich, andere);
    if (grad.art == Gradart.keine) continue;
    ergebnis[andere] = grad;
  }
  return ergebnis;
}

/// Sortierschlüssel für die Verwandtenliste: erst die nächsten
/// Angehörigen, dann die entfernteren, Angeheiratetes zuletzt.
///
/// Als eigene Funktion, weil „nah" nicht dasselbe ist wie „wenige Kanten":
/// Ein Partner steht null Blutsstufen entfernt und gehört trotzdem an den
/// Anfang, ein Urgroßvater drei Stufen und ein Cousin vier – aber der
/// Urgroßvater ist der nähere Angehörige.
int naeheRang(Grad grad) => switch (grad.art) {
      Gradart.selbst => 0,
      Gradart.partner => 1,
      Gradart.vorfahre => 10 + grad.aufwaerts,
      Gradart.nachkomme => 20 + grad.abwaerts,
      Gradart.geschwister => 5,
      Gradart.geschwisterkind => 30 + grad.abwaerts,
      Gradart.vorfahrengeschwister => 40 + grad.aufwaerts,
      Gradart.cousin => 50 + grad.cousinGrad * 2 + grad.entfernung,
      Gradart.schwiegerelternteil => 60,
      Gradart.schwiegerkind => 61,
      Gradart.schwager => 62,
      Gradart.stiefelternteil => 63,
      Gradart.stiefkind => 64,
      Gradart.stiefgeschwister => 65,
      Gradart.angeheiratet => 70,
      Gradart.keine => 99,
    };
