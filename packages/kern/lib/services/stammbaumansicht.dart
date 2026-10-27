import '../db/database.dart';
import 'lebensbaumansicht.dart' show Lebensbaumperson, schildpersonen;
import 'stammbaum.dart';
import 'zierbaum.dart';

/// Der Stammbaum um eine Person, wie Browser (über den Server) und Telefon
/// ihn zeigen: dasselbe Geflecht wie am Rechner ([geflechtUm]) – Haushalte
/// je Generationsband und die Elternhäuser jeder Person – und dieselbe
/// Anordnung ([zierbaumplan]).
///
/// **Dieselben Masse wie am Rechner** ([Zierbaummasse], [Schildmasse]):
/// Browser und Telefon malen den Zierbaum wie der Rechner – Schild mit
/// Porträt darüber, Stamm, Äste und Ranken (#234). Vorher hatten sie eigene,
/// höhere Karten und einen schlichten Strichbaum.
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

  /// Wo jedes Schild steht und wohin die Äste laufen, in den Massen des
  /// Rechners.
  Zierbaumplan? plan,

  /// Was auf den Schildern steht: Lebensdaten und Verwandtschaft zur
  /// Mitte, bei Angeheirateten über wen – wie am Rechner.
  Map<String, Lebensbaumperson> schilder,

  /// Der Name unten am Stamm – der häufigste Nachname im Bild, `null`,
  /// wenn keiner zweimal vorkommt (siehe [haeufigsterNachname]).
  String? familienname,

  /// Wie weit der Baum reicht – das Verlangte oder, ohne Angabe, was am
  /// Rechner zuletzt eingestellt war.
  Stammbaumumfang umfang,
});

/// Ohne [fokus] die zuletzt am Rechner gewählte Person, sonst die erste
/// mit Verwandtschaft. Für [oben], [unten] und [kreis] gilt dasselbe:
/// ohne Angabe, was am Rechner zuletzt eingestellt war (siehe
/// [stammbaumumfangAus]).
Future<Stammbaumansicht> stammbaumansicht(
  AppDatabase db, {
  String? fokus,
  int? oben,
  int? unten,
  String? kreis,
}) async {
  final gemerkt = await db.stammbaumUmfang();
  final umfang = stammbaumumfangAus(
    oben: oben ?? gemerkt.oben,
    unten: unten ?? gemerkt.unten,
    kreis: kreis ?? gemerkt.kreis,
  );
  final personen = db.nachAlterSortiert(await db.select(db.people).get());
  if (personen.isEmpty) {
    return (
      fokus: null,
      personen: const <PersonData>[],
      verwandt: const <String>{},
      geflecht: null,
      plan: null,
      schilder: const <String, Lebensbaumperson>{},
      familienname: null,
      umfang: umfang,
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
  final reihenfolge = [for (final p in personen) p.id];
  final nachId = {for (final p in personen) p.id: p};
  final rang = {for (var i = 0; i < reihenfolge.length; i++) reihenfolge[i]: i};
  final geflecht = geflechtUm(
    netz,
    f,
    reihenfolge,
    oben: umfang.oben,
    unten: umfang.unten,
    kreis: umfang.kreis,
  );
  return (
    fokus: f,
    personen: personen,
    verwandt: verwandt,
    geflecht: geflecht,
    plan: zierbaumplan(geflecht),
    schilder: schildpersonen(
      netz,
      f,
      geflecht.personen,
      nachId,
      (id) => rang[id] ?? 1 << 30,
    ),
    familienname: haeufigsterNachname([
      for (final id in geflecht.personen) nachId[id]!.name,
    ]),
    umfang: umfang,
  );
}
