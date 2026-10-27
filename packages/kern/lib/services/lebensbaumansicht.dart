import '../db/database.dart';
import 'lebensbaum.dart';
import 'lebensbaum_bild.dart';
import 'lebensbaum_vorlage.dart';
import 'stammbaum.dart';
import 'verwandtschaftsgrad.dart';
import 'zierbaum.dart';

/// Wie der Lebensbaum gezeichnet wird – die Wahl über dem Bild.
typedef Lebensbaumoptionen = ({
  Lebensbaumrichtung richtung,
  Lebensbaumstil stil,
  int generationen,
  int oben,
  int unten,
  Verwandtenkreis kreis,
});

/// Eine Person auf dem Lebensbaum: Name, Lebensdaten, Porträt und die
/// Verwandtschaft zur Person am Stamm – bei Angeheirateten über wen.
typedef Lebensbaumperson = ({
  PersonData person,
  String? lebensspanne,
  Grad? grad,

  /// Bei Angeheirateten: der Schritt von [ueber] zur Person, und wie
  /// [ueber] mit der Person am Stamm verwandt ist.
  ({PersonData ueber, Grad schritt, Grad ueberGrad})? umweg,
});

/// Der Lebensbaum um eine Person – dieselbe Anordnung wie am Rechner, für
/// den Browser (über den Server) und das Telefon.
typedef Lebensbaumansicht = ({
  /// `null`, wenn es noch keine Person gibt.
  String? fokus,
  Lebensbaumoptionen optionen,
  List<PersonData> alle,
  Set<String> verwandt,
  Lebensbaumbild? bild,
  Map<String, Lebensbaumperson> personen,
  String? nachname,
});

T _wahl<T extends Enum>(List<T> werte, String? text, T vorgabe) {
  for (final w in werte) {
    if (w.name == text) return w;
  }
  return vorgabe;
}

/// Ohne Angaben gilt, was am Rechner zuletzt gewählt war, sonst die
/// Vorgaben des Rechners.
Future<Lebensbaumansicht> lebensbaumansicht(
  AppDatabase db, {
  String? fokus,
  String? richtung,
  String? stil,
  String? kreis,
  int? generationen,
  int? oben,
  int? unten,
}) async {
  final personen = db.nachAlterSortiert(await db.select(db.people).get());
  final gemerkt = await db.lebensbaumZuletzt();
  final optionen = (
    richtung: _wahl(
      Lebensbaumrichtung.values,
      richtung ?? gemerkt.richtung,
      Lebensbaumrichtung.vorfahren,
    ),
    stil: _wahl(
      Lebensbaumstil.values,
      stil ?? gemerkt.stil,
      Lebensbaumstil.pergament,
    ),
    generationen: (generationen ?? gemerkt.generationen ?? 4).clamp(
      lebensbaumMinGenerationen + 1,
      lebensbaumMaxGenerationen,
    ),
    oben: (oben ?? gemerkt.familieOben ?? geflechtGenerationen).clamp(
      1,
      geflechtGenerationen,
    ),
    unten: (unten ?? gemerkt.familieUnten ?? geflechtGenerationen).clamp(
      0,
      geflechtGenerationen,
    ),
    kreis: _wahl(
      Verwandtenkreis.values,
      kreis ?? gemerkt.familieKreis,
      Verwandtenkreis.alle,
    ),
  );
  if (personen.isEmpty) {
    return (
      fokus: null,
      optionen: optionen,
      alle: const <PersonData>[],
      verwandt: const <String>{},
      bild: null,
      personen: const <String, Lebensbaumperson>{},
      nachname: null,
    );
  }
  final netz = Verwandtschaftsnetz([
    for (final z in await db.alleBeziehungen())
      if (artAusText(z.art) case final art?) kante(z.personId, z.andereId, art),
  ]);
  final nachId = {for (final p in personen) p.id: p};
  final verwandt = {
    for (final p in personen)
      if (netz.eltern(p.id).isNotEmpty ||
          netz.kinder(p.id).isNotEmpty ||
          netz.partner(p.id).isNotEmpty)
        p.id,
  };
  var f = fokus;
  if (f == null || !nachId.containsKey(f)) {
    f = (await db.stammbaumZuletzt()).person;
  }
  if (f == null || !nachId.containsKey(f)) {
    f = personen
        .firstWhere(
          (p) => verwandt.contains(p.id),
          orElse: () => personen.first,
        )
        .id;
  }
  final reihenfolge = [for (final p in personen) p.id];
  final rang = {for (var i = 0; i < reihenfolge.length; i++) reihenfolge[i]: i};
  int ordnung(String id) => rang[id] ?? 1 << 30;

  final Lebensbaumbild bild;
  if (optionen.richtung == Lebensbaumrichtung.familie) {
    final geflecht = geflechtUm(
      netz,
      f,
      reihenfolge,
      oben: optionen.oben,
      unten: optionen.unten,
      kreis: optionen.kreis,
    );
    bild = familienbild(
      zierbaumplan(geflecht),
      grosseLebensbaumvorlage(optionen.stil),
      verschwiegen: geflecht.verschwiegen,
    );
  } else {
    final plan = lebensbaumplan(
      netz,
      f,
      ordnung,
      richtung: optionen.richtung,
      generationen: optionen.generationen,
    );
    final (:vorlage, :belegung) = passendeVorlage(plan, optionen.stil);
    bild = bildAusBelegung(vorlage, belegung);
  }
  final imBild = bild.personen.toSet();
  return (
    fokus: f,
    optionen: optionen,
    alle: personen,
    verwandt: verwandt,
    bild: bild,
    personen: schildpersonen(netz, f, imBild, nachId, ordnung),
    nachname: haeufigsterNachname([for (final id in imBild) nachId[id]!.name]),
  );
}

/// Lebensdaten und Verwandtschaft zur Mitte für jede Person in [imBild].
///
/// Für den Lebensbaum und den Stammbaum dieselbe Rechnung, damit beide
/// dieselben Bezeichnungen tragen – wie am Rechner, wo der Zierbaum sie
/// ebenso aus [alleGrade] und [umwegZu] nimmt. [ordnung] entscheidet
/// zwischen zwei gleich guten Umwegen, damit eine Person nicht bei jedem
/// Aufbau anders heisst.
Map<String, Lebensbaumperson> schildpersonen(
  Verwandtschaftsnetz netz,
  String fokus,
  Set<String> imBild,
  Map<String, PersonData> nachId,
  int Function(String) ordnung,
) {
  final grade = alleGrade(netz, fokus, imBild);
  return {
    for (final id in imBild)
      if (nachId[id] case final person?)
        id: () {
          final gr = grade[id];
          final umweg = gr?.art == Gradart.angeheiratet
              ? umwegZu(netz, fokus, id, reihenfolge: ordnung)
              : null;
          final zwischen = umweg == null ? null : nachId[umweg.ueber];
          return (
            person: person,
            lebensspanne: lebensspanne(person.geburtsdatum, person.sterbedatum),
            grad: gr,
            umweg: umweg == null || zwischen == null
                ? null
                : (
                    ueber: zwischen,
                    schritt: umweg.schritt,
                    ueberGrad: umweg.ueberGrad,
                  ),
          );
        }(),
  };
}
