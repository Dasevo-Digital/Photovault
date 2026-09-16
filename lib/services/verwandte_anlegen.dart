/// Verwandte eintragen, die nicht unmittelbar an einer Person hängen –
/// Neffe, Onkel, Cousine, Schwiegermutter, Urenkelin.
///
/// Gespeichert werden weiterhin **nur** Eltern, Kinder und Partner (siehe
/// [Verwandtschaft]). Alles andere ist ausgerechnet, und das soll so
/// bleiben: Eine eigene Kantenart „Neffe" wäre eine zweite Wahrheit neben
/// den Elternkanten, und beide könnten auseinanderlaufen.
///
/// Was hier steht, ist deshalb keine Erweiterung des Modells, sondern eine
/// Abkürzung durch die Oberfläche: Wer einen Neffen eintragen will, müsste
/// sonst zum Bruder rücken, dort ein Kind eintragen und wieder
/// zurückrücken. Diese Datei rechnet aus, an wem die neue Person hängen
/// muss, damit die Bezeichnung hinterher stimmt.
///
/// Die Probe darauf ist nicht das Bild, sondern die Gegenrechnung: Trägt
/// man über [wegeFuer] einen Neffen ein, muss [bestimmeGrad] für ihn
/// [Gradart.geschwisterkind] liefern. Jeder Grad hier hat drüben sein
/// Gegenstück – das ist kein Zufall, sondern der Grund, warum die Liste
/// genau so aussieht.
library;

import 'stammbaum.dart';

/// Was die neue Person für die Person wird, an der sie hängt.
enum Ankerrolle {
  /// Sie wird Elternteil des Ankers – so entsteht ein Großelternteil.
  elternteil,

  /// Sie wird Kind des Ankers – so entsteht ein Neffe.
  kind,

  /// Sie wird Partner des Ankers – so entsteht ein Schwiegerkind.
  partner,
}

/// Ein Verwandtschaftsgrad, der sich über Zwischenpersonen eintragen lässt.
///
/// Die unmittelbaren drei – Elternteil, Kind, Partner – stehen bewusst
/// nicht hier: Sie brauchen keine Zwischenperson und haben in der
/// Werkzeugleiste ihre eigenen Knöpfe, samt der Wahl zwischen leiblich,
/// Adoptiv und Pflege.
enum Zusatzgrad {
  grosselternteil,
  urgrosselternteil,
  enkelkind,
  urenkelkind,
  geschwisterkind,
  halbgeschwisterkind,
  onkelTante,
  neffeNichte,
  cousin,
  schwiegerelternteil,
  schwiegerkind,
  schwager,
  stiefelternteil,
  stiefkind,
}

/// Wonach eine fehlende Voraussetzung verlangt.
///
/// Als Aufzählung und nicht als fertiger Satz: Welche Sprache gesprochen
/// wird, weiß erst die Oberfläche (dasselbe Vorgehen wie bei
/// [Beziehungsfehler]).
enum Fehlt {
  /// Es ist noch kein Elternteil eingetragen.
  elternteil,

  /// Es sind noch keine Großeltern eingetragen.
  grosselternteil,

  /// Es ist noch kein Kind eingetragen.
  kind,

  /// Es ist noch kein Enkelkind eingetragen.
  enkelkind,

  /// Es ist noch kein Geschwisterkind eingetragen.
  geschwister,

  /// Es ist noch kein Onkel bzw. keine Tante eingetragen.
  onkelTante,

  /// Es ist noch kein Partner eingetragen.
  partner,

  /// Weder ein Geschwisterkind noch ein Partner – für den Schwager
  /// genügt eines von beidem.
  geschwisterOderPartner,
}

/// Ein Weg, die neue Person einzuhängen.
///
/// [bezugsperson] ist die Person, über die der Nutzer den neuen Verwandten
/// benennt („der Bruder von wem?"). [anker] sind die Personen, an denen
/// tatsächlich Kanten entstehen – beim Onkel sind das nicht der Elternteil
/// selbst, sondern dessen Eltern.
typedef Einhaengeweg = ({
  String bezugsperson,
  List<String> anker,
  Ankerrolle rolle,
});

/// Alle Großeltern – die Eltern der Eltern.
Set<String> grosseltern(Verwandtschaftsnetz netz, String id) => {
      for (final e in netz.eltern(id)) ...netz.eltern(e),
    };

/// Alle Enkel – die Kinder der Kinder.
Set<String> enkel(Verwandtschaftsnetz netz, String id) => {
      for (final k in netz.kinder(id)) ...netz.kinder(k),
    };

/// Onkel und Tanten – die Geschwister der Eltern.
Set<String> onkelUndTanten(Verwandtschaftsnetz netz, String id) => {
      for (final e in netz.eltern(id)) ...netz.geschwister(e),
    };

/// Die Wege, auf denen sich [grad] für [fokus] eintragen lässt.
///
/// Leer bedeutet: Die Voraussetzung fehlt – [fehlendeVoraussetzung] sagt
/// welche. Genau ein Weg bedeutet: Es gibt nichts zu fragen. Mehrere
/// bedeuten: Die Oberfläche muss wählen lassen, an welcher Bezugsperson
/// die neue hängen soll.
///
/// Die Reihenfolge folgt [reihenfolge], damit die Auswahl nicht bei jedem
/// Aufruf anders steht.
List<Einhaengeweg> wegeFuer(
  Verwandtschaftsnetz netz,
  String fokus,
  Zusatzgrad grad, {
  int Function(String id)? reihenfolge,
}) {
  List<String> sortiert(Iterable<String> ids) {
    final liste = ids.toList();
    if (reihenfolge != null) {
      liste.sort((a, b) => reihenfolge(a).compareTo(reihenfolge(b)));
    } else {
      liste.sort();
    }
    return liste;
  }

  /// Der häufigste Fall: je Bezugsperson ein Weg, und die Bezugsperson ist
  /// zugleich der einzige Anker.
  List<Einhaengeweg> jeEinzeln(Iterable<String> kandidaten, Ankerrolle rolle) => [
        for (final id in sortiert(kandidaten))
          (bezugsperson: id, anker: [id], rolle: rolle),
      ];

  switch (grad) {
    case Zusatzgrad.grosselternteil:
      return jeEinzeln(netz.eltern(fokus), Ankerrolle.elternteil);

    case Zusatzgrad.urgrosselternteil:
      return jeEinzeln(grosseltern(netz, fokus), Ankerrolle.elternteil);

    case Zusatzgrad.enkelkind:
      return jeEinzeln(netz.kinder(fokus), Ankerrolle.kind);

    case Zusatzgrad.urenkelkind:
      return jeEinzeln(enkel(netz, fokus), Ankerrolle.kind);

    case Zusatzgrad.geschwisterkind:
      // Ein einziger Weg mit ALLEN Eltern als Anker. Mit nur einem wäre
      // es ein Halbgeschwisterkind – eine andere Aussage, die deshalb
      // ihren eigenen Eintrag hat.
      final eltern = sortiert(netz.eltern(fokus));
      if (eltern.isEmpty) return const [];
      return [(bezugsperson: fokus, anker: eltern, rolle: Ankerrolle.kind)];

    case Zusatzgrad.halbgeschwisterkind:
      return jeEinzeln(netz.eltern(fokus), Ankerrolle.kind);

    case Zusatzgrad.onkelTante:
      // Ein Onkel ist ein Geschwister eines Elternteils, also ein
      // weiteres Kind der Großeltern. Gefragt wird nach dem Elternteil
      // („der Bruder von wem?"), gehängt wird an dessen Eltern.
      return [
        for (final e in sortiert(netz.eltern(fokus)))
          if (netz.eltern(e).isNotEmpty)
            (
              bezugsperson: e,
              anker: sortiert(netz.eltern(e)),
              rolle: Ankerrolle.kind
            ),
      ];

    case Zusatzgrad.neffeNichte:
      return jeEinzeln(netz.geschwister(fokus), Ankerrolle.kind);

    case Zusatzgrad.cousin:
      return jeEinzeln(onkelUndTanten(netz, fokus), Ankerrolle.kind);

    case Zusatzgrad.schwiegerelternteil:
      return jeEinzeln(netz.partner(fokus), Ankerrolle.elternteil);

    case Zusatzgrad.schwiegerkind:
      return jeEinzeln(netz.kinder(fokus), Ankerrolle.partner);

    case Zusatzgrad.schwager:
      // Zwei Lesarten, beide richtig: der Partner eines Geschwisters und
      // das Geschwister eines Partners. Welche gemeint ist, entscheidet
      // sich mit der Bezugsperson – deshalb stehen beide in einer Liste.
      return [
        for (final g in sortiert(netz.geschwister(fokus)))
          (bezugsperson: g, anker: [g], rolle: Ankerrolle.partner),
        for (final p in sortiert(netz.partner(fokus)))
          if (netz.eltern(p).isNotEmpty)
            (
              bezugsperson: p,
              anker: sortiert(netz.eltern(p)),
              rolle: Ankerrolle.kind
            ),
      ];

    case Zusatzgrad.stiefelternteil:
      return jeEinzeln(netz.eltern(fokus), Ankerrolle.partner);

    case Zusatzgrad.stiefkind:
      return jeEinzeln(netz.partner(fokus), Ankerrolle.kind);
  }
}

/// Was fehlt, wenn [wegeFuer] leer bleibt.
///
/// Eigene Funktion statt eines zweiten Rückgabewerts: Der Normalfall ist,
/// dass es Wege gibt, und der soll nicht jedes Mal einen ungenutzten
/// Grund mitschleppen.
Fehlt fehlendeVoraussetzung(Zusatzgrad grad) => switch (grad) {
      Zusatzgrad.grosselternteil ||
      Zusatzgrad.geschwisterkind ||
      Zusatzgrad.halbgeschwisterkind ||
      Zusatzgrad.stiefelternteil =>
        Fehlt.elternteil,
      // Urgroßeltern und Onkel brauchen beide eine Generation MEHR als
      // nur die Eltern: die Eltern der Eltern.
      Zusatzgrad.urgrosselternteil || Zusatzgrad.onkelTante => Fehlt.grosselternteil,
      Zusatzgrad.enkelkind || Zusatzgrad.schwiegerkind => Fehlt.kind,
      Zusatzgrad.urenkelkind => Fehlt.enkelkind,
      Zusatzgrad.neffeNichte => Fehlt.geschwister,
      Zusatzgrad.cousin => Fehlt.onkelTante,
      Zusatzgrad.schwiegerelternteil || Zusatzgrad.stiefkind => Fehlt.partner,
      Zusatzgrad.schwager => Fehlt.geschwisterOderPartner,
    };

/// Die Kanten, die ein [Einhaengeweg] für die neue Person [neueId] erzeugt.
///
/// Eine Liste, weil ein Geschwisterkind an mehreren Eltern gleichzeitig
/// hängt.
List<Kante> kantenFuer(Einhaengeweg weg, String neueId) => [
      for (final anker in weg.anker)
        switch (weg.rolle) {
          // Die neue Person ist Elternteil des Ankers: Die Kante gehört
          // dem Anker und zeigt auf die neue Person.
          Ankerrolle.elternteil => kante(anker, neueId, Verwandtschaft.elternteil),
          Ankerrolle.kind => kante(neueId, anker, Verwandtschaft.elternteil),
          Ankerrolle.partner => partnerKanteFuer(neueId, anker),
        },
    ];
