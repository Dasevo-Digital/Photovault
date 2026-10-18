import '../db/database.dart';
import 'stammbaum.dart';

/// Der Stammbaum um eine Person, wie Browser (über den Server) und Telefon
/// ihn zeigen: dasselbe Geflecht wie am Rechner ([geflechtUm]) – Haushalte
/// je Generationsband und die Elternhäuser jeder Person.
typedef Stammbaumansicht = ({
  /// `null`, wenn es noch keine Person gibt.
  String? fokus,

  /// Alle Personen, nach Alter.
  List<PersonData> personen,

  /// Wer überhaupt Verwandtschaft eingetragen hat.
  Set<String> verwandt,
  Stammbaumgeflecht? geflecht,
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
  return (
    fokus: f,
    personen: personen,
    verwandt: verwandt,
    geflecht: geflechtUm(netz, f, [for (final p in personen) p.id]),
  );
}
