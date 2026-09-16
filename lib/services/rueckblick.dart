/// **Was der Rückblick heute zeigt — und warum nicht immer dasselbe.**
///
/// Der Abschnitt „Erinnerungen" stellte genau eine Frage: Was ist heute
/// vor Jahren entstanden? An der echten Bibliothek trifft die an **261
/// von 365** Tagen etwas, und an 107 davon sind es höchstens drei
/// Aufnahmen. An den übrigen 104 Tagen verschwand der Abschnitt wortlos
/// — am 12. September 2026 war das so, und nichts sagte, warum.
///
/// Die Antwort ist nicht, den Tag aufzuweichen. Sie ist, die
/// **nächstgrössere Frage** zu stellen, wenn die kleinere leer bleibt:
/// „im September vor 13 Jahren" ist genauso wahr und behauptet nichts
/// über den Tag. Was hier steht, ist diese Wahl — rein und ohne
/// Datenbankklassen, damit sie prüfbar bleibt.
library;

/// Welche Frage der Rückblick gerade beantwortet.
enum Rueckblickart {
  /// „Heute vor X Jahren" – der genaue Kalendertag.
  tag,

  /// „Im September vor X Jahren" – der Rückfall, wenn der Tag nichts hat.
  monat,

  /// Weder noch. Auch das ist eine Auskunft und kein Zufall.
  keiner,
}

/// Das Ergebnis: die Frage und die Bilder dazu, nach „vor wie vielen
/// Jahren" gebündelt und mit dem jüngsten Jahrgang zuerst.
typedef Rueckblick<T> = ({Rueckblickart art, List<({int jahreHer, List<T> dinge})> gruppen});

/// Bündelt [dinge] nach dem Abstand ihres Aufnahmejahres zu [heute].
///
/// Die Reihenfolge innerhalb einer Gruppe bleibt, wie sie hereinkam –
/// die Abfragen liefern bereits nach Aufnahmedatum sortiert, und eine
/// zweite Sortierung hier würde das nur verwischen.
List<({int jahreHer, List<T> dinge})> nachJahrenGebuendelt<T>(
  Iterable<T> dinge,
  DateTime Function(T) wann,
  DateTime heute,
) {
  final gruppen = <int, List<T>>{};
  for (final d in dinge) {
    final jahre = heute.year - wann(d).year;
    if (jahre <= 0) continue;
    gruppen.putIfAbsent(jahre, () => []).add(d);
  }
  final schluessel = gruppen.keys.toList()..sort();
  return [
    for (final j in schluessel) (jahreHer: j, dinge: gruppen[j]!),
  ];
}

/// Wählt zwischen Tag und Monat.
///
/// **Der Tag gewinnt, sobald er etwas hat** – er ist die stärkere
/// Aussage. Nur wenn er leer bleibt, tritt der Monat an seine Stelle;
/// beides zugleich zu zeigen hiesse, dieselben Bilder zweimal zu
/// bringen und den Unterschied zwischen „an genau diesem Tag" und „in
/// diesem Monat" einzuebnen.
Rueckblick<T> waehleRueckblick<T>({
  required List<T> amTag,
  required List<T> imMonat,
  required DateTime Function(T) wann,
  required DateTime heute,
}) {
  final tag = nachJahrenGebuendelt(amTag, wann, heute);
  if (tag.isNotEmpty) return (art: Rueckblickart.tag, gruppen: tag);
  final monat = nachJahrenGebuendelt(imMonat, wann, heute);
  if (monat.isNotEmpty) return (art: Rueckblickart.monat, gruppen: monat);
  return (art: Rueckblickart.keiner, gruppen: const []);
}
