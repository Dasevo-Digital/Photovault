/// **Familientage:** Geburtstage, Todestage und Hochzeitstage aus dem
/// Stammbaum, heute und in den nächsten Tagen.
///
/// Der Rückblick fragt die Fotos, was heute vor Jahren war. Der
/// Stammbaum weiss etwas, das kein Foto weiss: wann jemand Geburtstag hat,
/// seit wann jemand fehlt, wie lange zwei verheiratet sind. Erst beides
/// zusammen ergibt „Oma wäre heute 100 geworden" – mit ihren Bildern
/// darunter.
///
/// Rein und ohne Datenbankklassen, damit sich jede Regel prüfen lässt:
/// der 29. Februar, der Jahreswechsel im Vorausblick, das Paar, das
/// seine Hochzeit zweimal eingetragen hat.
library;

/// Welcher Tag es ist.
enum Familientagart { geburtstag, todestag, hochzeitstag }

/// Eine Person, so weit sie hier gebraucht wird.
typedef Familienmitglied = ({
  String id,
  DateTime? geburtsdatum,
  DateTime? sterbedatum,
});

/// Ein eingetragenes Hochzeitsdatum und wer geheiratet hat.
typedef Hochzeit = ({DateTime datum, String personId, String? partnerId});

/// Ein Familientag.
class Familientag {
  final Familientagart art;

  /// Bei einer Hochzeit beide, sonst eine Person.
  final List<String> personen;

  /// Zum wievielten Mal sich der Tag jährt – das Alter, die Jahre seit
  /// dem Tod oder der Ehe.
  final int jahre;

  /// 0 heute, 1 morgen und so weiter.
  final int inTagen;

  /// Ob die Person gestorben ist. Ein Geburtstag heisst dann „wäre …
  /// geworden".
  final bool verstorben;

  const Familientag({
    required this.art,
    required this.personen,
    required this.jahre,
    required this.inTagen,
    this.verstorben = false,
  });

  /// Ein runder Tag: ein Vielfaches von zehn, bei Hochzeiten auch die
  /// Silberhochzeit. Runde Tage stehen vorn.
  bool get rund =>
      jahre % 10 == 0 || (art == Familientagart.hochzeitstag && jahre == 25);

  @override
  String toString() => 'Familientag($art, $personen, $jahre, in $inTagen)';
}

/// Wie weit der Abschnitt vorausschaut.
const familientageVorausblick = 7;

/// Sucht die Familientage von [heute] bis [vorausblick] Tage danach.
///
/// Sortiert nach Abstand, am selben Tag runde zuerst, dann Geburtstage
/// der Lebenden vor Gedenktagen. Ein Ereignis, das erst im kommenden
/// Jahr sein erstes Jubiläum hat – geboren vor drei Tagen –, zählt
/// nicht: Ein Säugling hat heute keinen Geburtstag.
List<Familientag> familientage({
  required Iterable<Familienmitglied> personen,
  required Iterable<Hochzeit> hochzeiten,
  required DateTime heute,
  int vorausblick = familientageVorausblick,
}) {
  final tag = DateTime(heute.year, heute.month, heute.day);
  final ergebnis = <Familientag>[];

  /// Der nächste Jahrestag von [datum] ab [tag], oder `null`, wenn er
  /// ausserhalb des Vorausblicks liegt oder noch kein voller Jahrestag ist.
  ({int jahre, int inTagen})? jahrestag(DateTime datum) {
    for (var jahr = tag.year; jahr <= tag.year + 1; jahr++) {
      final am = _jahrestagIm(datum, jahr);
      final abstand = am.difference(tag).inDays;
      if (abstand < 0) continue;
      if (abstand > vorausblick) return null;
      final jahre = jahr - datum.year;
      if (jahre <= 0) return null;
      return (jahre: jahre, inTagen: abstand);
    }
    return null;
  }

  for (final p in personen) {
    final geburt = p.geburtsdatum;
    final tod = p.sterbedatum;
    if (geburt != null) {
      final j = jahrestag(geburt);
      if (j != null) {
        ergebnis.add(
          Familientag(
            art: Familientagart.geburtstag,
            personen: [p.id],
            jahre: j.jahre,
            inTagen: j.inTagen,
            verstorben: tod != null,
          ),
        );
      }
    }
    if (tod != null) {
      final j = jahrestag(tod);
      if (j != null) {
        ergebnis.add(
          Familientag(
            art: Familientagart.todestag,
            personen: [p.id],
            jahre: j.jahre,
            inTagen: j.inTagen,
            verstorben: true,
          ),
        );
      }
    }
  }

  // Dieselbe Hochzeit steht oft bei beiden Partnern. Einmal zählen.
  final gesehen = <String>{};
  for (final h in hochzeiten) {
    final paar = [h.personId, ?h.partnerId]..sort();
    final schluessel =
        '${paar.join('+')}@${h.datum.year}-${h.datum.month}-${h.datum.day}';
    if (!gesehen.add(schluessel)) continue;
    final j = jahrestag(h.datum);
    if (j == null) continue;
    ergebnis.add(
      Familientag(
        art: Familientagart.hochzeitstag,
        personen: [h.personId, ?h.partnerId],
        jahre: j.jahre,
        inTagen: j.inTagen,
      ),
    );
  }

  // **Gedenktage verjähren – bis auf die runden.** Wer 1850 geboren ist,
  // „wäre heute 176 geworden"; das sagt niemandem etwas und stünde jedes
  // Jahr wieder da. Über hundert Jahre bleibt nur, was rund ist.
  ergebnis.removeWhere(
    (f) =>
        (f.verstorben || f.art == Familientagart.todestag) &&
        f.jahre > 100 &&
        !f.rund,
  );

  int rang(Familientag f) => switch (f.art) {
    Familientagart.geburtstag => f.verstorben ? 2 : 0,
    Familientagart.hochzeitstag => 1,
    Familientagart.todestag => 3,
  };
  ergebnis.sort((a, b) {
    final abstand = a.inTagen.compareTo(b.inTagen);
    if (abstand != 0) return abstand;
    if (a.rund != b.rund) return a.rund ? -1 : 1;
    return rang(a).compareTo(rang(b));
  });
  return ergebnis;
}

/// Der Jahrestag von [datum] im Jahr [jahr]. Wer am 29. Februar geboren
/// ist, feiert in Gemeinjahren am 28. – der Tag, der noch im Februar
/// liegt.
DateTime _jahrestagIm(DateTime datum, int jahr) {
  if (datum.month == 2 && datum.day == 29 && !_schaltjahr(jahr)) {
    return DateTime(jahr, 2, 28);
  }
  return DateTime(jahr, datum.month, datum.day);
}

bool _schaltjahr(int jahr) =>
    (jahr % 4 == 0 && jahr % 100 != 0) || jahr % 400 == 0;
