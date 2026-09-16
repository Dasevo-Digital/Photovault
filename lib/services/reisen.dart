/// Reisen erkennen, statt sie eintragen zu lassen.
///
/// Der Punkt, an dem diese App ein Reisetagebuch nicht nachbauen, sondern
/// überholen kann. Andere Programme stellen ein leeres Formular hin und
/// warten, dass jemand seine Reise abtippt — Ort, Datum, Fotos anhängen.
/// **Photo Vault ist die Fotosammlung.** Aufnahmezeit und Koordinate
/// stehen längst in der Datenbank; eine Reise ist im Kern nichts anderes
/// als eine Häufung von Aufnahmen in Zeit und Raum, weit genug von zu
/// Hause weg.
///
/// Also nicht „trag deine Reise ein", sondern: „Zwischen dem 3. und
/// 12. Juni liegen 340 Aufnahmen aus Südtirol — war das eine Reise?" Aus
/// einer Tagebuchpflicht wird eine Bestätigung.
///
/// Reine Funktionen, ohne Datenbankklassen. Ob eine Häufung eine Reise
/// ist, lässt sich nur nachrechnen — am fertigen Vorschlag sieht man
/// nicht, warum er entstanden ist.
library;

import 'reverse_geocoder.dart';

/// Was für eine Art Reise das war.
///
/// **Warum eine Reise eine Art braucht.** In dieser Bibliothek stehen
/// nebeneinander: ein zweimonatiger Auslandseinsatz, eine Gedenkfahrt,
/// eine Firmenveranstaltung und ein Verwandtenbesuch. „Reise" trifft
/// keines davon richtig, und wer die Liste ansieht, sieht vier Zeilen
/// derselben Sorte.
///
/// Fünf Arten und nicht fünfzehn: Jede hier ist eine, die in einer
/// echten Bibliothek vorkam. Eine Aufzählung, die alles vorsieht,
/// verlangt bei jedem Eintrag eine Entscheidung, die niemand treffen
/// will.
enum Reiseart {
  reise,
  unternehmung,
  geschaeftlich,
  besuch,
  sonstiges;

  /// Wie die Art in der Datenbank steht – der Name und nicht der Index,
  /// aus demselben Grund wie bei `Aktivitaetsart`: Wer später eine Art
  /// dazwischenschiebt, verschöbe sonst alle gespeicherten Zeilen.
  String get kennung => name;

  static Reiseart aus(String s) => Reiseart.values.firstWhere(
        (a) => a.name == s,
        orElse: () => Reiseart.reise,
      );
}

/// Die Vorgabe für eine neue oder eine bestehende Reise ohne Angabe.
const Reiseart reiseartVorgabe = Reiseart.reise;

/// Eine Aufnahme, wie die Erkennung sie braucht.
typedef Reiseaufnahme = ({
  String id,
  DateTime zeit,
  double breite,
  double laenge,
  String? land,
  String? region,
  String? stadt,
});

/// Kantenlänge der Zellen, in denen nach dem Wohnort gesucht wird – rund
/// 25 km. Fein genug, um Nachbarstädte zu trennen, grob genug, dass
/// derselbe Wohnort nicht auf vier Zellen zerfällt.
const double zuhauseRaster = 0.25;

/// Ab dieser Entfernung vom Wohnort zählt eine Aufnahme als „unterwegs".
///
/// Hundert Kilometer sind der Abstand, ab dem man nicht mehr eben
/// hinfährt. Darunter beginnt der Ausflug, und ein Ausflug ist keine
/// Reise – sonst hiesse jeder Sonntag im Nachbarort so.
const double reiseMindestabstandKm = 100;

/// Eine Lücke von mehr als so vielen Tagen trennt zwei Reisen.
///
/// Zwei Tage und nicht einer: Wer unterwegs einen Tag nicht
/// fotografiert – Regen, Fahrtag, ein Museum ohne Erlaubnis –, soll
/// deswegen nicht zwei Reisen bekommen.
const int reiseLueckeTage = 2;

/// So viele Aufnahmen muss eine Häufung mindestens haben.
const int reiseMindestfotos = 5;

/// Ein Vorschlag – **keine Reise.** Erst die Bestätigung macht eine
/// daraus.
class Reisevorschlag {
  /// Die Aufnahmen, chronologisch.
  final List<String> aufnahmeIds;

  final DateTime von;
  final DateTime bis;

  /// Der vorgeschlagene Name, aus den besuchten Orten gebildet.
  final String name;

  /// Die besuchten Orte, häufigste zuerst.
  final List<String> orte;

  /// Die berührten Länder, häufigste zuerst.
  final List<String> laender;

  const Reisevorschlag({
    required this.aufnahmeIds,
    required this.von,
    required this.bis,
    required this.name,
    required this.orte,
    required this.laender,
  });

  /// Wie viele Nächte dazwischen liegen – gerechnet über Kalendertage,
  /// nicht über 24-Stunden-Abschnitte. Wer am Freitagabend losfährt und
  /// am Samstagmorgen zurückkommt, war eine Nacht weg.
  int get naechte =>
      DateTime(bis.year, bis.month, bis.day)
          .difference(DateTime(von.year, von.month, von.day))
          .inDays;

  int get anzahl => aufnahmeIds.length;

  /// Womit sich dieser Vorschlag wiedererkennen lässt, wenn er abgelehnt
  /// wurde.
  ///
  /// Die **erste Aufnahme** und nicht der Zeitraum: Kommen später Bilder
  /// desselben Urlaubs aus einer zweiten Kamera dazu, verschiebt sich das
  /// Ende – der Vorschlag ist aber derselbe und soll abgelehnt bleiben.
  String get schluessel => aufnahmeIds.first;
}

/// Wo jemand zu Hause ist, aus den Aufnahmen selbst geschlossen.
///
/// **Nicht der Schwerpunkt aller Aufnahmen.** Ein Mittelwert über
/// Hamburg, Rom und Tokio liegt in Sibirien. Statt dessen: das Raster
/// mit den meisten **verschiedenen Tagen**.
///
/// Verschiedene Tage und nicht die Zahl der Aufnahmen – das ist der
/// eigentliche Kniff. Eine einzige Hochzeit bringt sechshundert Bilder an
/// einem Ort, an dem man nie war; ein Zuhause bringt drei Bilder an
/// vierhundert Tagen. Gezählt werden muss also, wie oft man dort war,
/// nicht wie oft man ausgelöst hat.
({double breite, double laenge})? zuhause(Iterable<Reiseaufnahme> aufnahmen) {
  final tageJeZelle = <String, Set<int>>{};
  final punkteJeZelle = <String, List<Reiseaufnahme>>{};
  for (final a in aufnahmen) {
    final zelle = '${(a.breite / zuhauseRaster).floor()}'
        '|${(a.laenge / zuhauseRaster).floor()}';
    tageJeZelle
        .putIfAbsent(zelle, () => <int>{})
        .add(DateTime(a.zeit.year, a.zeit.month, a.zeit.day)
            .millisecondsSinceEpoch ~/ 86400000);
    punkteJeZelle.putIfAbsent(zelle, () => []).add(a);
  }
  if (tageJeZelle.isEmpty) return null;

  // Bei Gleichstand die Zelle mit den meisten Aufnahmen, danach die
  // alphabetisch erste – sonst hinge der Wohnort an der Reihenfolge, in
  // der die Datenbank ihre Zeilen liefert.
  final beste = tageJeZelle.keys.toList()
    ..sort((a, b) {
      final t = tageJeZelle[b]!.length.compareTo(tageJeZelle[a]!.length);
      if (t != 0) return t;
      final n = punkteJeZelle[b]!.length.compareTo(punkteJeZelle[a]!.length);
      return n != 0 ? n : a.compareTo(b);
    });

  // Innerhalb der Zelle der Mittelwert – die Zelle ist 25 km breit, ihre
  // Ecke wäre als Wohnort um bis zu 35 km daneben.
  final punkte = punkteJeZelle[beste.first]!;
  return (
    breite: punkte.map((p) => p.breite).reduce((a, b) => a + b) / punkte.length,
    laenge: punkte.map((p) => p.laenge).reduce((a, b) => a + b) / punkte.length,
  );
}

/// Zählt Werte und gibt sie häufigste-zuerst zurück.
List<String> _haeufigste(Iterable<String?> werte) {
  final gezaehlt = <String, int>{};
  for (final w in werte) {
    if (w == null || w.trim().isEmpty) continue;
    gezaehlt[w] = (gezaehlt[w] ?? 0) + 1;
  }
  final liste = gezaehlt.keys.toList()
    ..sort((a, b) {
      final z = gezaehlt[b]!.compareTo(gezaehlt[a]!);
      return z != 0 ? z : a.compareTo(b);
    });
  return liste;
}

/// Baut den vorgeschlagenen Namen.
///
/// Ein Ort, wenn die Reise an einem Ort blieb; sonst das Land; sonst zwei
/// Orte mit Bindestrich. Der Name ist ein **Vorschlag** und wird beim
/// Bestätigen überschrieben – deshalb darf er einfach sein.
String reisename(List<String> orte, List<String> laender, String ohneOrt) {
  if (laender.length > 1) return laender.take(3).join(' – ');
  if (orte.isEmpty) return laender.isEmpty ? ohneOrt : laender.first;
  if (orte.length == 1) return orte.first;
  // Zwei Orte reichen: „Rom – Florenz – Siena – Pisa – …" ist kein Name
  // mehr, sondern eine Aufzählung.
  return '${orte.first} – ${orte[1]}';
}

/// Sucht in [aufnahmen] nach Reisen.
///
/// [ohneOrt] ist der Name für eine Reise, deren Orte die Umkehr-
/// Geokodierung nicht kennt – hereingegeben, damit dieser Dienst ohne
/// Übersetzungsapparat auskommt.
///
/// [bekannteIds] sind Aufnahmen, die bereits zu einer bestätigten Reise
/// gehören; sie werden übersprungen. [verworfen] sind die Schlüssel
/// abgelehnter Vorschläge.
///
/// [unverortet] sind Aufnahmen **ohne** Koordinate. Sie taugen nicht zum
/// Erkennen, gehören aber dazu: An der echten Bibliothek gemessen trugen
/// von einer zehntägigen Reise nur zwei Tage überhaupt GPS-Daten – und
/// im Zeitfenster dieser zwei Tage lagen 28 weitere Aufnahmen ohne
/// Koordinate. Wer zu Beginn und am Ende des Fensters nachweislich weit
/// weg war, war es auch dazwischen; diese Bilder wegzulassen hiesse,
/// eine Reise zu zeigen, in der Fotos fehlen.
///
/// Nur **innerhalb** des erkannten Fensters und nicht darüber hinaus:
/// Davor und danach wäre es geraten.
List<Reisevorschlag> erkenneReisen(
  List<Reiseaufnahme> aufnahmen, {
  required String ohneOrt,
  List<({String id, DateTime zeit})> unverortet = const [],
  Set<String> bekannteIds = const {},
  Set<String> verworfen = const {},
  ({double breite, double laenge})? wohnort,
  double mindestabstandKm = reiseMindestabstandKm,
  int lueckeTage = reiseLueckeTage,
  int mindestfotos = reiseMindestfotos,
}) {
  final heim = wohnort ?? zuhause(aufnahmen);
  if (heim == null) return const [];

  final unterwegs = [
    for (final a in aufnahmen)
      if (!bekannteIds.contains(a.id) &&
          ReverseGeocoder.haversineKm(
                  a.breite, a.laenge, heim.breite, heim.laenge) >=
              mindestabstandKm)
        a,
  ]..sort((a, b) => a.zeit.compareTo(b.zeit));

  final ergebnis = <Reisevorschlag>[];
  var lauf = <Reiseaufnahme>[];

  void abschliessen() {
    if (lauf.length < mindestfotos) {
      lauf = [];
      return;
    }
    final von = lauf.first.zeit;
    final bis = lauf.last.zeit;
    // Mindestens eine Nacht. Ein Tagesausflug ist keine Reise – und wer
    // ihn als solche führen will, kann ihn von Hand anlegen.
    final naechte = DateTime(bis.year, bis.month, bis.day)
        .difference(DateTime(von.year, von.month, von.day))
        .inDays;
    if (naechte < 1) {
      lauf = [];
      return;
    }
    final dazu = [
      for (final u in unverortet)
        if (!bekannteIds.contains(u.id) &&
            !u.zeit.isBefore(von) &&
            !u.zeit.isAfter(bis))
          u,
    ];
    final alle = <({String id, DateTime zeit})>[
      for (final a in lauf) (id: a.id, zeit: a.zeit),
      ...dazu,
    ]..sort((a, b) => a.zeit.compareTo(b.zeit));

    final orte = _haeufigste(lauf.map((a) => a.stadt));
    final laender = _haeufigste(lauf.map((a) => a.land));
    final vorschlag = Reisevorschlag(
      aufnahmeIds: [for (final a in alle) a.id],
      von: von,
      bis: bis,
      name: reisename(orte, laender, ohneOrt),
      orte: orte,
      laender: laender,
    );
    if (!verworfen.contains(vorschlag.schluessel)) ergebnis.add(vorschlag);
    lauf = [];
  }

  for (final a in unterwegs) {
    if (lauf.isNotEmpty &&
        a.zeit.difference(lauf.last.zeit).inDays > lueckeTage) {
      abschliessen();
    }
    lauf.add(a);
  }
  abschliessen();

  // Die jüngste Reise zuerst – wie überall sonst in dieser App.
  ergebnis.sort((a, b) => b.von.compareTo(a.von));
  return ergebnis;
}
