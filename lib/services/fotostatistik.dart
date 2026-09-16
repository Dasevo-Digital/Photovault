/// Was die Bibliothek über die Menschen auf ihren Bildern weiß.
///
/// **Warum es diese Datei gibt.** Die Familienstatistik rechnete
/// Sterbealter, Heiratsalter und Alter je Generation aus – Zahlen aus
/// einem Ahnenforschungsprogramm. An einer echten Bibliothek gemessen:
/// 31 Personen, 8 im Stammbaum, 8 mit Geburtsdatum, **null mit
/// Sterbedatum**, ein einziges Lebensereignis. Drei von fünf Kacheln
/// waren damit leer, und die Auskunft lautete „keine Angabe".
///
/// Dieselbe Bibliothek kennt über 1700 erkannte Gesichter aus zwölf
/// Jahren. Wer wie oft auftaucht, seit wann, mit wem zusammen und in
/// welchem Alter – das steht da, und niemand muss es eintragen. Ein
/// Fotoverwalter soll die Fragen beantworten, für die er die Daten hat.
///
/// Rein und ohne Datenbankklassen, wie `lebenslauf.dart` und
/// `familienstatistik.dart`.
library;

import 'familienstatistik.dart' show alterInJahren;

/// Eine Person auf einer Aufnahme.
typedef Fotoauftritt = ({String personId, String assetId, DateTime zeit});

/// Was die Bilder über eine Person hergeben.
class Personenbilanz {
  final String personId;
  final int aufnahmen;

  /// Die früheste und die späteste Aufnahme, auf der sie zu sehen ist.
  final DateTime erste;
  final DateTime letzte;

  /// Wie viele verschiedene Kalenderjahre. Etwas anderes als die Spanne:
  /// Zwei Bilder aus 2014 und 2026 sind zwölf Jahre Abstand, aber zwei
  /// Jahre Anwesenheit.
  final int jahre;

  /// Das Alter auf der ersten und der letzten Aufnahme – `null` ohne
  /// Geburtsdatum.
  final int? alterErste;
  final int? alterLetzte;

  const Personenbilanz({
    required this.personId,
    required this.aufnahmen,
    required this.erste,
    required this.letzte,
    required this.jahre,
    required this.alterErste,
    required this.alterLetzte,
  });
}

/// Zwei Personen und wie oft sie zusammen auf einem Bild sind.
typedef Gemeinsam = ({String a, String b, int aufnahmen});

/// Das Ergebnis.
class Fotostatistik {
  /// Nach Zahl der Aufnahmen, die häufigste zuerst.
  final List<Personenbilanz> personen;

  /// Die häufigsten Paare.
  final List<Gemeinsam> paare;

  /// Aufnahmen je Kalenderjahr – über alle betrachteten Personen.
  final Map<int, int> jeJahr;

  /// Verschiedene Aufnahmen insgesamt. **Nicht die Summe der
  /// Personenzahlen**: Ein Familienfoto mit vier Gesichtern ist ein Bild
  /// und nicht vier.
  final int aufnahmen;

  /// Wie viele der betrachteten Personen auf keinem einzigen Bild sind.
  ///
  /// Gehört genannt: Eine Bestenliste, aus der jemand fehlt, sieht aus
  /// wie eine vollständige.
  final int ohneBild;

  const Fotostatistik({
    required this.personen,
    required this.paare,
    required this.jeJahr,
    required this.aufnahmen,
    required this.ohneBild,
  });

  bool get istLeer => aufnahmen == 0;
}

/// Wertet die Auftritte aus.
///
/// [betrachtet] ist die Menge der Personen, um die es geht – in der
/// Oberfläche die Familie um die Person in der Mitte. Auftritte anderer
/// werden übergangen, auch beim Zählen der Paare: „Wer ist oft mit wem
/// im Bild" soll die Familie beschreiben und nicht jeden Gast.
///
/// [geburt] darf Lücken haben. Wo ein Datum fehlt, bleibt das Alter
/// `null` statt geraten.
Fotostatistik fotostatistik({
  required Iterable<Fotoauftritt> auftritte,
  required Set<String> betrachtet,
  Map<String, DateTime?> geburt = const {},
  int hoechstensPaare = 8,
}) {
  final jePerson = <String, List<Fotoauftritt>>{};
  final jeAufnahme = <String, Set<String>>{};
  final jeJahr = <int, int>{};
  final aufnahmen = <String>{};

  for (final a in auftritte) {
    if (!betrachtet.contains(a.personId)) continue;
    jePerson.putIfAbsent(a.personId, () => []).add(a);
    jeAufnahme.putIfAbsent(a.assetId, () => <String>{}).add(a.personId);
    if (aufnahmen.add(a.assetId)) {
      jeJahr[a.zeit.year] = (jeJahr[a.zeit.year] ?? 0) + 1;
    }
  }

  final bilanzen = <Personenbilanz>[];
  for (final e in jePerson.entries) {
    final zeiten = [for (final a in e.value) a.zeit]..sort();
    final g = geburt[e.key];
    bilanzen.add(Personenbilanz(
      personId: e.key,
      // Verschiedene Aufnahmen, nicht Gesichter: Ein Bild, auf dem
      // dieselbe Person zweimal erkannt wurde, ist trotzdem ein Bild.
      aufnahmen: {for (final a in e.value) a.assetId}.length,
      erste: zeiten.first,
      letzte: zeiten.last,
      jahre: {for (final z in zeiten) z.year}.length,
      alterErste: alterInJahren(g, zeiten.first),
      alterLetzte: alterInJahren(g, zeiten.last),
    ));
  }
  bilanzen.sort((a, b) {
    final z = b.aufnahmen.compareTo(a.aufnahmen);
    return z != 0 ? z : a.personId.compareTo(b.personId);
  });

  // Paare. Der Schlüssel ist das sortierte Paar – „A mit B" und „B mit
  // A" sind dieselbe Auskunft, und zwei Zeilen dafür wären eine
  // Verdopplung, die nach mehr aussieht.
  final paarzahl = <({String a, String b}), int>{};
  for (final leute in jeAufnahme.values) {
    if (leute.length < 2) continue;
    final sortiert = leute.toList()..sort();
    for (var i = 0; i < sortiert.length; i++) {
      for (var j = i + 1; j < sortiert.length; j++) {
        final k = (a: sortiert[i], b: sortiert[j]);
        paarzahl[k] = (paarzahl[k] ?? 0) + 1;
      }
    }
  }
  final paare = <Gemeinsam>[
    for (final e in paarzahl.entries)
      (a: e.key.a, b: e.key.b, aufnahmen: e.value),
  ]..sort((x, y) {
      final z = y.aufnahmen.compareTo(x.aufnahmen);
      if (z != 0) return z;
      final za = x.a.compareTo(y.a);
      return za != 0 ? za : x.b.compareTo(y.b);
    });

  return Fotostatistik(
    personen: bilanzen,
    paare: paare.take(hoechstensPaare).toList(),
    jeJahr: jeJahr,
    aufnahmen: aufnahmen.length,
    ohneBild: betrachtet.length - jePerson.length,
  );
}
