import 'dart:math' as math;

/// Eine festgehaltene Entscheidung des Nutzers über einen
/// Wiedererkennungs-Vorschlag – die Rohdaten, aus denen [leiteSchwelleAb]
/// eine persönliche Schwelle gewinnt.
///
/// [aehnlichkeit] ist der Wert **zum Entscheidungszeitpunkt**. Ohne ihn
/// liesse sich später nichts ableiten: Dass ein Gesicht zu einer Person
/// gehört, sagt nichts darüber aus, ab welcher Ähnlichkeit die Erkennung
/// hätte zugreifen dürfen.
class GesichtsRueckmeldung {
  final bool bestaetigt;
  final double aehnlichkeit;

  const GesichtsRueckmeldung({required this.bestaetigt, required this.aehnlichkeit});
}

/// Ab wie vielen Entscheidungen überhaupt von der allgemeinen Schwelle
/// abgewichen wird. Zwei Klicks sind kein Muster – und eine Schwelle, die
/// nach dem ersten Fehlgriff verspringt, wäre für den Nutzer nicht
/// nachvollziehbar.
const mindestEntscheidungen = 3;

/// Wie weit die persönliche Schwelle höchstens von der allgemeinen
/// abweichen darf.
///
/// Der Deckel ist kein Feinschliff, sondern Schadensbegrenzung: Ein
/// einzelner Fehlklick auf einem sehr ähnlichen Gesicht könnte die Schwelle
/// sonst so weit hochziehen, dass diese Person nie wieder vorgeschlagen
/// wird – und niemand käme darauf, dass ein alter Klick daran schuld ist.
const maximaleAbweichung = 0.15;

/// Leitet aus den Entscheidungen zu einer Person ihre Wiedererkennungs-
/// Schwelle ab.
///
/// Das Verfahren ist bewusst schlicht und erklärbar, denn es wird dem
/// Nutzer im Personen-Bildschirm im Klartext angezeigt:
///
///  * Liegt die niedrigste bestätigte Ähnlichkeit **über** der höchsten
///    abgelehnten, trennen die beiden Gruppen sauber. Dann liegt die
///    Schwelle genau dazwischen.
///  * Überschneiden sie sich, widersprechen die Belege einander – etwa bei
///    Geschwistern, die sich sehr ähnlich sehen. Dann bleibt es bei der
///    allgemeinen Schwelle. Aus widersprüchlichen Daten eine Zahl zu
///    erfinden wäre schlechter als nichts zu tun.
///
/// [allgemein] ist die global eingestellte Schwelle; sie ist zugleich
/// Ausgangspunkt und Bezug für den Deckel.
double leiteSchwelleAb(List<GesichtsRueckmeldung> rueckmeldungen, double allgemein) {
  if (rueckmeldungen.length < mindestEntscheidungen) return allgemein;

  double? niedrigsteBestaetigt;
  double? hoechsteAbgelehnt;
  for (final r in rueckmeldungen) {
    if (r.bestaetigt) {
      niedrigsteBestaetigt = niedrigsteBestaetigt == null
          ? r.aehnlichkeit
          : math.min(niedrigsteBestaetigt, r.aehnlichkeit);
    } else {
      hoechsteAbgelehnt = hoechsteAbgelehnt == null
          ? r.aehnlichkeit
          : math.max(hoechsteAbgelehnt, r.aehnlichkeit);
    }
  }

  // Nur Bestätigungen: Die Schwelle darf bis knapp unter die schwächste
  // davon sinken, damit vergleichbare Gesichter künftig mitkommen. Nur
  // Ablehnungen: entsprechend über die stärkste steigen.
  final double roh;
  if (niedrigsteBestaetigt != null && hoechsteAbgelehnt != null) {
    if (niedrigsteBestaetigt <= hoechsteAbgelehnt) return allgemein;
    roh = (niedrigsteBestaetigt + hoechsteAbgelehnt) / 2;
  } else if (niedrigsteBestaetigt != null) {
    roh = math.min(allgemein, niedrigsteBestaetigt - 0.01);
  } else {
    roh = math.max(allgemein, hoechsteAbgelehnt! + 0.01);
  }

  return roh.clamp(allgemein - maximaleAbweichung, allgemein + maximaleAbweichung);
}

/// Ob [rueckmeldungen] überhaupt zu einer Abweichung führen.
///
/// Getrennt von [leiteSchwelleAb], weil die Oberfläche den Unterschied
/// benennen können muss: "noch zu wenige Entscheidungen" ist etwas anderes
/// als "die Entscheidungen widersprechen sich", und beides etwas anderes
/// als "angepasst".
SchwellenHerkunft herkunft(List<GesichtsRueckmeldung> rueckmeldungen, double allgemein) {
  if (rueckmeldungen.length < mindestEntscheidungen) return SchwellenHerkunft.zuWenigDaten;
  final abgeleitet = leiteSchwelleAb(rueckmeldungen, allgemein);
  if (abgeleitet == allgemein) {
    // Kann zwei Gründe haben; unterschieden wird über die Überschneidung.
    final bestaetigt = rueckmeldungen.where((r) => r.bestaetigt);
    final abgelehnt = rueckmeldungen.where((r) => !r.bestaetigt);
    if (bestaetigt.isNotEmpty && abgelehnt.isNotEmpty) {
      final niedrigste = bestaetigt.map((r) => r.aehnlichkeit).reduce(math.min);
      final hoechste = abgelehnt.map((r) => r.aehnlichkeit).reduce(math.max);
      if (niedrigste <= hoechste) return SchwellenHerkunft.widerspruch;
    }
    return SchwellenHerkunft.wieAllgemein;
  }
  return SchwellenHerkunft.angepasst;
}

enum SchwellenHerkunft {
  /// Weniger als [mindestEntscheidungen] Rückmeldungen.
  zuWenigDaten,

  /// Bestätigungen und Ablehnungen überschneiden sich.
  widerspruch,

  /// Ableitung ergab rechnerisch genau die allgemeine Schwelle.
  wieAllgemein,

  /// Es gilt ein eigener Wert.
  angepasst,
}
