import 'dart:isolate';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../db/database.dart';
import 'embedding_codec.dart';
import 'face_clustering_service.dart';
import 'face_engine_service.dart';

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
