import 'dart:isolate';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../db/database.dart';
import 'embedding_codec.dart';
import 'face_clustering_service.dart';
import 'face_engine_service.dart';
import 'face_suggestions.dart';

/// Gesichter ohne Namen und die Gesichter einer Aufnahme – für Browser
/// (über den Server) und Telefon dieselbe Rechnung wie am Rechner
/// (people_screen.dart): dieselbe allgemeine Schwelle, je Person ihre
/// gelernte, und ein Vorschlag nur, wenn der Mittelpunkt einer Gruppe
/// diese Schwelle erreicht.

/// Ähnliche Gesichter ohne Namen, mit dem Vorschlag, wer es sein könnte.
typedef Gesichtsgruppe = ({
  List<FaceData> gesichter,
  PersonData? vorschlag,
  double? aehnlichkeit,
});

typedef GesichterOhneNamen = ({
  /// Nach Grösse, die grösste zuerst.
  List<Gesichtsgruppe> gruppen,

  /// Die allgemeine Schwelle – wer eine Entscheidung über einen Vorschlag
  /// festhält (GesichtsEntscheidungenMerken), schickt sie mit.
  double schwelle,

  /// Wie viele der angesehenen Gesichter keinem anderen ähneln.
  int einzeln,

  /// Wie viele angesehen wurden – höchstens [gesichterOhneNamenHoechstens].
  int angesehen,

  /// Wie viele es insgesamt gibt.
  int gesamt,
});

/// Wie viele unbenannte Gesichter auf einmal gruppiert werden: die
/// jüngsten. Verglichen wird jedes mit jedem; bei 2000 ist das auf dem
/// Telefon und dem Heimserver eine Sache von Sekundenbruchteilen, bei
/// zehntausenden wären es Minuten. Wer benennt, arbeitet sich vor – die
/// nächsten rücken nach.
const gesichterOhneNamenHoechstens = 2000;

Future<GesichterOhneNamen> gesichterOhneNamen(
  AppDatabase db, {
  int hoechstens = gesichterOhneNamenHoechstens,
}) async {
  final zeilen =
      await (db.select(db.faces).join([
              innerJoin(db.assets, db.assets.id.equalsExp(db.faces.assetId)),
            ])
            ..where(
              db.faces.personId.isNull() &
                  db.faces.isIgnored.equals(false) &
                  db.faces.embedding.isNotNull() &
                  db.assets.isTrashed.equals(false) &
                  db.assets.isLocked.equals(false),
            )
            ..orderBy([OrderingTerm.desc(db.assets.fileCreatedAt)])
            ..limit(hoechstens))
          .get();
  final gesichter = [for (final z in zeilen) z.readTable(db.faces)];
  final gesamt = await db.unassignedFacesCount();
  final vektoren = {
    for (final f in gesichter) f.id: floatsFromEmbeddingBlob(f.embedding!),
  };
  final schwelle = await db.faceSimilarityThresholdWert();
  final gruppenIds = vektoren.length < 2
      ? const <List<String>>[]
      : await Isolate.run(
          () => clusterFaces(FaceClusterInput(vektoren, schwelle)),
        );

  // Der Mittelpunkt jeder benannten Person, in einer Abfrage für alle.
  final personen = {for (final p in await db.select(db.people).get()) p.id: p};
  final jePerson = <String, List<Float32List>>{};
  for (final f in await (db.select(
    db.faces,
  )..where((t) => t.personId.isNotNull() & t.embedding.isNotNull())).get()) {
    jePerson
        .putIfAbsent(f.personId!, () => [])
        .add(floatsFromEmbeddingBlob(f.embedding!));
  }
  final kerne = {
    for (final e in jePerson.entries)
      if (personen.containsKey(e.key)) e.key: meanNormalizedEmbedding(e.value),
  };

  final nachId = {for (final f in gesichter) f.id: f};
  final gruppen = <Gesichtsgruppe>[];
  var inGruppen = 0;
  for (final ids in gruppenIds) {
    final mitte = meanNormalizedEmbedding([
      for (final id in ids) vektoren[id]!,
    ]);
    String? bester;
    var beste = 0.0;
    for (final k in kerne.entries) {
      final a = FaceEngineService.cosineSimilarity(mitte, k.value);
      if (a > beste) {
        beste = a;
        bester = k.key;
      }
    }
    // Die persönliche Schwelle der ähnlichsten Person – darin steckt das
    // Gelernte (siehe people_screen.dart).
    final person = bester == null ? null : personen[bester];
    final trifft =
        person != null && beste >= (person.similarityThreshold ?? schwelle);
    gruppen.add((
      gesichter: [for (final id in ids) nachId[id]!],
      vorschlag: trifft ? person : null,
      aehnlichkeit: trifft ? beste : null,
    ));
    inGruppen += ids.length;
  }
  gruppen.sort((a, b) => b.gesichter.length.compareTo(a.gesichter.length));
  return (
    gruppen: gruppen,
    schwelle: schwelle,
    einzeln: gesichter.length - inGruppen,
    angesehen: gesichter.length,
    gesamt: gesamt,
  );
}

/// Ein Gesicht auf einer Aufnahme und wer es ist – `null`, wenn noch
/// niemand.
typedef GesichtAufAufnahme = ({FaceData gesicht, PersonData? person});

/// Die Gesichter einer Aufnahme, von links nach rechts.
Future<List<GesichtAufAufnahme>> gesichterDerAufnahme(
  AppDatabase db,
  String assetId,
) async {
  final gesichter = [...await db.facesForAsset(assetId)]
    ..sort((a, b) => a.boxX.compareTo(b.boxX));
  final ids = {for (final f in gesichter) ?f.personId};
  final personen = ids.isEmpty
      ? const <String, PersonData>{}
      : {
          for (final p in await (db.select(
            db.people,
          )..where((t) => t.id.isIn(ids))).get())
            p.id: p,
        };
  return [
    for (final f in gesichter)
      (gesicht: f, person: f.personId == null ? null : personen[f.personId]),
  ];
}

/// Weitere Fotos einer Person: unbenannte Gesichter, die ihr ähnlich genug
/// sind – wie „Vorschläge suchen“ am Rechner (person_detail_screen.dart),
/// zusammen mit dem, was die Wiedererkennung schon für sie vorgemerkt hat
/// (vorschlaege_screen.dart).
typedef WeitereFotosDaten = ({
  /// Absteigend nach Ähnlichkeit, das Sicherste zuerst.
  List<({FaceData gesicht, double aehnlichkeit})> vorschlaege,

  /// Die Schwelle dieser Person – ihre gelernte, sonst die allgemeine.
  double schwelle,

  /// Die allgemeine, für GesichtsEntscheidungenMerken.
  double allgemein,
});

Future<WeitereFotosDaten?> weitereFotosVon(
  AppDatabase db,
  String personId,
) async {
  final person = await (db.select(
    db.people,
  )..where((t) => t.id.equals(personId))).getSingleOrNull();
  if (person == null) return null;
  final allgemein = await db.faceSimilarityThresholdWert();
  final schwelle = person.similarityThreshold ?? allgemein;
  final bekannt = [
    for (final f in await db.facesForPerson(personId))
      if (f.embedding != null) floatsFromEmbeddingBlob(f.embedding!),
  ];
  final offen = await db.allUnassignedFaces();
  final kandidaten = {
    for (final f in offen)
      if (f.embedding != null) f.id: floatsFromEmbeddingBlob(f.embedding!),
  };
  final gerechnet = bekannt.isEmpty || kandidaten.isEmpty
      ? const <Gesichtsvorschlag>[]
      : await _vorschlaegeImIsolat(
          VorschlagsEingabe(
            bekannt: bekannt,
            kandidaten: kandidaten,
            schwelle: schwelle,
          ),
        );
  // Was die Wiedererkennung vorgemerkt hat, kommt dazu – mit dem
  // höheren der beiden Werte, falls beide dasselbe Gesicht nennen.
  final nachId = {for (final f in offen) f.id: f};
  final werte = <String, double>{
    for (final v in gerechnet) v.faceId: v.aehnlichkeit,
  };
  for (final v in await db.vorschlaegeFuerPerson(personId)) {
    nachId[v.gesicht.id] ??= v.gesicht;
    final da = werte[v.gesicht.id];
    if (da == null || v.aehnlichkeit > da) werte[v.gesicht.id] = v.aehnlichkeit;
  }
  final liste = [
    for (final e in werte.entries)
      if (nachId[e.key] case final f?) (gesicht: f, aehnlichkeit: e.value),
  ]..sort((a, b) => b.aehnlichkeit.compareTo(a.aehnlichkeit));
  return (
    vorschlaege: liste.length > 60 ? liste.sublist(0, 60) : liste,
    schwelle: schwelle,
    allgemein: allgemein,
  );
}

/// Auf oberster Ebene: Ein Abschluss innerhalb von [weitereFotosVon]
/// nähme dessen ganzen Kontext mit ins Isolat (siehe teilbilder.dart).
Future<List<Gesichtsvorschlag>> _vorschlaegeImIsolat(VorschlagsEingabe e) =>
    Isolate.run(() => vorschlaegeFuerPerson(e));

/// Hält fest, wie über Vorschläge für eine Person entschieden wurde:
/// zugeordnet, was angenommen ist, den Vorschlag weg von dem, was nicht
/// stimmt, und beides als Rückmeldung für ihre Schwelle – wie
/// PersonSuggestionsScreen am Rechner.
List<Befehl<Object?>> vorschlaegeEntschieden({
  required String personId,
  required List<({String faceId, double aehnlichkeit})> vorschlaege,
  required Set<String> angenommen,
  required double allgemein,
}) => [
  if (vorschlaege.any((v) => angenommen.contains(v.faceId)))
    GesichterZuordnen([
      for (final v in vorschlaege)
        if (angenommen.contains(v.faceId)) v.faceId,
    ], personId),
  if (vorschlaege.any((v) => !angenommen.contains(v.faceId)))
    VorschlaegeVerwerfen([
      for (final v in vorschlaege)
        if (!angenommen.contains(v.faceId)) v.faceId,
    ]),
  if (vorschlaege.isNotEmpty)
    GesichtsEntscheidungenMerken(personId, [
      for (final v in vorschlaege)
        (
          faceId: v.faceId,
          accepted: angenommen.contains(v.faceId),
          similarity: v.aehnlichkeit,
        ),
    ], allgemeineSchwelle: allgemein),
];

/// Die Rückmeldung, wenn eine Gruppe mit Vorschlag benannt wurde: ein
/// Eintrag für die ganze Gruppe, nicht je Gesicht – die Ähnlichkeit wurde
/// zwischen ihrem Mittelpunkt und der Person gemessen (siehe
/// face_cluster_review_screen.dart). Beiseitelegen ist keine Aussage über
/// die Schwelle und hält nichts fest.
GesichtsEntscheidungenMerken? gruppeEntschieden({
  required Gesichtsgruppe gruppe,
  required List<String> zugeordnet,
  required String personId,
  required double allgemein,
}) {
  final vorschlag = gruppe.vorschlag;
  final aehnlichkeit = gruppe.aehnlichkeit;
  if (vorschlag == null || aehnlichkeit == null || zugeordnet.isEmpty) {
    return null;
  }
  return GesichtsEntscheidungenMerken(vorschlag.id, [
    (
      faceId: zugeordnet.first,
      accepted: personId == vorschlag.id,
      similarity: aehnlichkeit,
    ),
  ], allgemeineSchwelle: allgemein);
}
