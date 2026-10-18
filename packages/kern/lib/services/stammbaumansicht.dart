import '../db/database.dart';
import 'stammbaum.dart';
import 'zierbaum.dart';

/// Die Masse von Browser und Telefon: Schild 118 × 140, darüber und
/// darunter Platz für die Pfeile auf weitere Verwandte.
const stammbaumMasse = Zierbaummasse(
  schildBreite: 118,
  schildHoehe: 140,
  partnerLuecke: 10,
  haushaltLuecke: 36,
  bandLuecke: 60,
  rand: 24,
  randUnten: 24,
);

/// Der Stammbaum um eine Person, wie Browser (über den Server) und Telefon
/// ihn zeigen: dasselbe Geflecht wie am Rechner ([geflechtUm]) – Haushalte
/// je Generationsband und die Elternhäuser jeder Person – und dieselbe
/// Anordnung ([zierbaumplan]).
///
/// **Die Anordnung kommt mit.** Vorher setzten Browser und Telefon die
/// Haushalte eines Bandes einfach in der Reihenfolge des Geflechts von
/// links nach rechts. Die folgt aber nicht den Elternhäusern: Unter
/// „Bruder + Partnerin“ und „Schwester + Schwager“ stand das Kind der
/// Schwester ganz links – genau unter dem Bruder –, und sein Ast lief auf
/// derselben Höhe wie die der Kinder des Bruders. Im Bild war es dessen
/// Sohn. Der Rechner rechnet die Plätze aus den Elternhäusern; jetzt tun
/// es alle drei.
typedef Stammbaumansicht = ({
  /// `null`, wenn es noch keine Person gibt.
  String? fokus,

  /// Alle Personen, nach Alter.
  List<PersonData> personen,

  /// Wer überhaupt Verwandtschaft eingetragen hat.
  Set<String> verwandt,
  Stammbaumgeflecht? geflecht,

  /// Wo jedes Schild steht und wohin die Äste laufen, in [stammbaumMasse].
  Zierbaumplan? plan,
});

/// Ohne [fokus] die zuletzt am Rechner gewählte Person, sonst die erste
/// mit Verwandtschaft.
Future<Stammbaumansicht> stammbaumansicht(
  AppDatabase db, {
  String? fokus,
}) async {
  final personen = db.nachAlterSortiert(await db.select(db.people).get());
  if (personen.isEmpty) {
    return (
      fokus: null,
      personen: const <PersonData>[],
      verwandt: const <String>{},
      geflecht: null,
      plan: null,
    );
  }
  final netz = Verwandtschaftsnetz([
    for (final z in await db.alleBeziehungen())
      if (artAusText(z.art) case final art?) kante(z.personId, z.andereId, art),
  ]);
  final ids = {for (final p in personen) p.id};
  final verwandt = {
    for (final p in personen)
      if (netz.eltern(p.id).isNotEmpty ||
          netz.kinder(p.id).isNotEmpty ||
          netz.partner(p.id).isNotEmpty)
        p.id,
  };
  var f = fokus;
  if (f == null || !ids.contains(f)) f = (await db.stammbaumZuletzt()).person;
  if (f == null || !ids.contains(f)) {
    f = personen
        .firstWhere(
          (p) => verwandt.contains(p.id),
          orElse: () => personen.first,
        )
        .id;
  }
  final geflecht = geflechtUm(netz, f, [for (final p in personen) p.id]);
  return (
    fokus: f,
    personen: personen,
    verwandt: verwandt,
    geflecht: geflecht,
    plan: zierbaumplan(geflecht, masse: stammbaumMasse),
  );
}
