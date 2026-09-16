import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'face_engine_service.dart';

/// Eingabe für [clusterFaces] – als eigene Klasse statt loser Parameter,
/// damit sich der Aufruf sauber an `compute()` übergeben lässt (top-level
/// Funktion + ein einzelnes Argument, isolate-fähig).
class FaceClusterInput {
  final Map<String, Float32List> embeddingsByFaceId;
  final double threshold;

  /// Rückkanal für den Fortschritt (0..1). `null` heisst „niemand hört zu";
  /// die Funktion läuft dann genau wie zuvor.
  ///
  /// Der Anteil zählt **verglichene Paare**, nicht abgearbeitete Zeilen der
  /// äusseren Schleife. Der Unterschied ist erheblich: Die innere Schleife
  /// wird mit jedem Durchlauf kürzer, ein Balken nach Zeilen stünde nach
  /// der Hälfte der Zeit schon bei 71 % und danach scheinbar still.
  final SendPort? fortschritt;

  const FaceClusterInput(this.embeddingsByFaceId, this.threshold, {this.fortschritt});
}

/// Gruppiert unzugeordnete Gesichter anhand ihrer SFace-Embeddings zu
/// Vorschlags-Clustern (mind. 2 Gesichter – einzelne Gesichter ohne
/// ähnliches Gegenstück bleiben im normalen "Unbenannte Gesichter"-Raster).
///
/// Exaktes (nicht LSH-vorgefiltertes) Alle-gegen-alle-Clustering über
/// Union-Find, bewusst OHNE die Zufallsprojektions-Vorfilterung aus
/// duplicates_screen.dart: exaktes statt approximiertes Clustering ist für
/// identitätssensitive Gruppierung die richtige Wahl, und bei der
/// *typischen* Nutzung (regelmäßig zwischendurch triagieren, dadurch
/// hunderte bis niedrige Tausende unzugeordnete Gesichter) ist O(n²)
/// schnell genug – hochgerechnet aus dem Duplikatsuche-Benchmark
/// (`test/duplicate_detection_test.dart`, n=5000/dim=64: 501ms exhaustive)
/// auf die tatsächliche SFace-Embedding-Dimension (128, nicht 64) liegt
/// n=5000 eher bei ~1s. Bei sehr großen, noch nie triagierten Bibliotheken
/// (mehrere Zehntausend unzugeordnete Gesichter) kann ein Lauf dagegen
/// spürbar länger dauern (grob quadratisch, siehe Warnschwelle beim Aufruf
/// in people_screen.dart) – bewusst kein Deckel hier in der reinen
/// Algorithmus-Funktion, damit nie ein Teil der Gesichter stillschweigend
/// ignoriert wird.
List<List<String>> clusterFaces(FaceClusterInput input) {
  final ids = input.embeddingsByFaceId.keys.toList(growable: false);
  final n = ids.length;
  final vectors = List<Float32List>.generate(n, (i) => input.embeddingsByFaceId[ids[i]]!, growable: false);

  final parent = List<int>.generate(n, (i) => i, growable: false);
  int find(int x) {
    while (parent[x] != x) {
      x = parent[x];
    }
    return x;
  }

  void union(int a, int b) {
    final ra = find(a), rb = find(b);
    if (ra != rb) parent[ra] = rb;
  }

  final paareGesamt = n * (n - 1) / 2;
  var paareErledigt = 0.0;
  var zuletztGemeldet = 0.0;

  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      if (FaceEngineService.cosineSimilarity(vectors[i], vectors[j]) >= input.threshold) {
        union(i, j);
      }
    }
    if (input.fortschritt != null && paareGesamt > 0) {
      paareErledigt += n - 1 - i;
      final anteil = paareErledigt / paareGesamt;
      // Nur bei jedem halben Prozent melden. Eine Meldung je Zeile wären
      // bei 30.000 Gesichtern 30.000 Nachrichten über den Port – mehr
      // Aufwand für das Zustellen als für das Rechnen.
      if (anteil - zuletztGemeldet >= 0.005 || anteil >= 1.0) {
        zuletztGemeldet = anteil;
        input.fortschritt!.send(anteil);
      }
    }
  }

  final clusters = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    clusters.putIfAbsent(find(i), () => []).add(i);
  }
  return clusters.values
      .where((g) => g.length >= 2) // Singletons bleiben im normalen Raster
      .map((g) => g.map((i) => ids[i]).toList())
      .toList()
    ..sort((a, b) => b.length.compareTo(a.length));
}

/// Mittelwert mehrerer bereits L2-normalisierter Embeddings, danach ERNEUT
/// auf Einheitslänge normiert – der Mittelwert normierter Vektoren ist
/// selbst nicht normiert, ohne diesen Schritt wären Kosinus-Vergleiche
/// gegen den Centroid verfälscht. Für den "ähnlich zu bestehender Person"-
/// Vorschlag beim Gesichts-Clustering (Centroid einer Person bzw. eines
/// neuen Clusters).
Float32List meanNormalizedEmbedding(Iterable<Float32List> vectors) {
  final list = vectors.toList(growable: false);
  final dim = list.first.length;
  final sum = Float32List(dim);
  for (final v in list) {
    for (var i = 0; i < dim; i++) {
      sum[i] += v[i];
    }
  }
  var normSq = 0.0;
  for (var i = 0; i < dim; i++) {
    sum[i] /= list.length;
    normSq += sum[i] * sum[i];
  }
  final norm = math.sqrt(normSq);
  if (norm == 0) return sum;
  for (var i = 0; i < dim; i++) {
    sum[i] /= norm;
  }
  return sum;
}

// ---------------------------------------------------------------------------
// Ein Lauf mit Fortschritt und Abbruch
// ---------------------------------------------------------------------------

/// Der Lauf ist zu Ende gegangen, ohne ein Ergebnis zu liefern.
///
/// [meldung] ist die technische Ursache aus dem Isolat und `null`, wenn es
/// gar keine gab – das Isolat also einfach weg war. Bewusst kein fertiger
/// Satz: Welcher Text daraus wird, entscheidet die Oberfläche, die weiss,
/// in welcher Sprache sie gerade spricht.
class FaceClusterFehler implements Exception {
  final String? meldung;
  const FaceClusterFehler([this.meldung]);

  @override
  String toString() => 'FaceClusterFehler(${meldung ?? ''})';
}

/// Auftrag an das Isolat – ein einzelnes Argument, weil [Isolate.spawn] nur
/// eines übergibt.
class _ClusterAuftrag {
  final Map<String, Float32List> embeddings;
  final double threshold;
  final SendPort antwort;
  const _ClusterAuftrag(this.embeddings, this.threshold, this.antwort);
}

void _clusterImIsolat(_ClusterAuftrag auftrag) {
  final clusters = clusterFaces(FaceClusterInput(
    auftrag.embeddings,
    auftrag.threshold,
    fortschritt: auftrag.antwort,
  ));
  auftrag.antwort.send(clusters);
}

/// Ein laufender Gruppierungs-Durchgang: liefert [ergebnis], meldet
/// unterwegs den Fortschritt und lässt sich abbrechen.
///
/// Warum nicht `compute()` wie bisher: Dessen Isolat ist nach dem Start
/// nicht mehr erreichbar – weder für eine Rückmeldung noch für einen
/// Abbruch. Bei einer frisch gescannten grossen Bibliothek läuft der
/// Vergleich aber minutenlang, und beides ist genau dann nötig.
class FaceClusterLauf {
  FaceClusterLauf._(this._isolat, this._port, this._fertig);

  final Isolate _isolat;
  final ReceivePort _port;
  final Completer<List<List<String>>?> _fertig;

  /// Die gefundenen Gruppen – oder `null`, wenn abgebrochen wurde.
  Future<List<List<String>>?> get ergebnis => _fertig.future;

  var _abgebrochen = false;

  void abbrechen() {
    if (_fertig.isCompleted) return;
    _abgebrochen = true;
    _isolat.kill(priority: Isolate.immediate);
    _port.close();
    _fertig.complete(null);
  }
}

/// Startet einen Gruppierungslauf in einem eigenen Isolat.
///
/// [beiFortschritt] wird mit einem Anteil von 0..1 aufgerufen, etwa alle
/// halbe Prozent.
Future<FaceClusterLauf> starteFaceClustering(
  Map<String, Float32List> embeddings,
  double threshold, {
  required void Function(double anteil) beiFortschritt,
}) async {
  final port = ReceivePort();
  final fertig = Completer<List<List<String>>?>();
  late final FaceClusterLauf lauf;

  final isolat = await Isolate.spawn(
    _clusterImIsolat,
    _ClusterAuftrag(embeddings, threshold, port.sendPort),
    // Beides an denselben Port: Ohne sie bliebe der Dialog bei einem Fehler
    // oder einem abgestürzten Isolat für immer stehen, weil schlicht nie
    // eine Nachricht käme.
    onError: port.sendPort,
    onExit: port.sendPort,
  );

  port.listen((nachricht) {
    if (nachricht is double) {
      beiFortschritt(nachricht);
      return;
    }
    if (nachricht is List<List<String>>) {
      if (!fertig.isCompleted) fertig.complete(nachricht);
      port.close();
      return;
    }
    // Bleibt: `null` von onExit oder [Fehler, Stack] von onError. Beides
    // heisst „zu Ende, ohne Ergebnis". Nach einem Abbruch ist genau das
    // erwartet und schon beantwortet.
    if (!fertig.isCompleted && !lauf._abgebrochen) {
      fertig.completeError(FaceClusterFehler(
          nachricht is List && nachricht.isNotEmpty ? '${nachricht.first}' : null));
    }
    port.close();
  });

  lauf = FaceClusterLauf._(isolat, port, fertig);
  return lauf;
}
