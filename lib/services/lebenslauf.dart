/// Die Ereignisse im Leben einer Person – und wie sie mit Geburt und Tod
/// zu einem Lebenslauf zusammenfinden.
///
/// Ausgelagert, weil zwei Quellen zusammenlaufen: Geburt und Tod stehen
/// als Spalten an der Person, alles andere in einer eigenen Tabelle. Beide
/// in eine Reihenfolge zu bringen, ohne die eine zur anderen zu machen,
/// ist der Inhalt dieser Datei.
library;

/// Welche Art von Ereignis.
///
/// Bewusst eine kurze, feste Liste statt freier Eingabe: Eine Art, die nur
/// einmal vorkommt, lässt sich weder sortieren noch bebildern. Was nicht
/// passt, kommt unter [sonstiges] mit eigener Notiz.
enum Ereignisart { hochzeit, umzug, beruf, ausbildung, sonstiges }

String ereignisartZuText(Ereignisart a) => a.name;

Ereignisart ereignisartAusText(String text) => Ereignisart.values.firstWhere(
      (a) => a.name == text,
      // Ein unbekannter Wert – etwa aus einer neueren Fassung – wird zu
      // „sonstiges“ statt zu einem Absturz. Der Eintrag bleibt lesbar.
      orElse: () => Ereignisart.sonstiges,
    );

/// Eine Zeile im Lebenslauf.
class Lebenszeile {
  /// Die Kennung des Ereignisses – `null` bei Geburt und Tod, die keine
  /// eigene Zeile in der Tabelle haben und sich deshalb auch nicht
  /// einzeln löschen lassen.
  final String? ereignisId;

  /// `null` bei Geburt und Tod.
  final Ereignisart? art;

  /// Ob es sich um Geburt bzw. Tod handelt.
  final bool istGeburt;
  final bool istTod;

  final DateTime? datum;
  final String? ort;
  final String? notiz;

  const Lebenszeile({
    this.ereignisId,
    this.art,
    this.istGeburt = false,
    this.istTod = false,
    this.datum,
    this.ort,
    this.notiz,
  });
}

/// Eingabe für [lebenslauf] – ohne Datenbankklassen, damit sich die
/// Reihenfolge ohne Datenbank prüfen lässt.
typedef EreignisEingabe = ({
  String id,
  Ereignisart art,
  DateTime? datum,
  String? ort,
  String? notiz,
});

/// Bringt Geburt, Tod und die übrigen Ereignisse in eine Reihenfolge.
///
/// Sortiert nach Datum, das Frühere zuerst. Einträge **ohne** Datum
/// wandern ans Ende und nicht an den Anfang: Ein Ereignis, von dem man
/// nur weiß, dass es war, gehört nicht vor die Geburt.
///
/// Geburt und Tod stehen an ihrer chronologischen Stelle und nicht fest
/// am Rand – wer einen Umzug nach dem Tod einträgt (Umbettung, Nachlass),
/// soll das auch so sehen.
List<Lebenszeile> lebenslauf({
  required DateTime? geburt,
  required DateTime? tod,
  required List<EreignisEingabe> ereignisse,
}) {
  final zeilen = <Lebenszeile>[
    if (geburt != null) Lebenszeile(istGeburt: true, datum: geburt),
    if (tod != null) Lebenszeile(istTod: true, datum: tod),
    for (final e in ereignisse)
      Lebenszeile(
        ereignisId: e.id,
        art: e.art,
        datum: e.datum,
        ort: e.ort,
        notiz: e.notiz,
      ),
  ];
  zeilen.sort((a, b) {
    if (a.datum == null && b.datum == null) return 0;
    if (a.datum == null) return 1;
    if (b.datum == null) return -1;
    return a.datum!.compareTo(b.datum!);
  });
  return zeilen;
}
