import 'dart:math' as math;
import 'dart:typed_data';

/// Eingabe für [findDuplicateGroups] – gebündelt in einer Klasse, da
/// [compute] genau ein Argument an die Isolate-Funktion übergibt.
class DuplicateSearchParams {
  final Map<String, Float32List> embeddings;
  final double threshold;

  /// Paare, die der Nutzer nicht mehr sehen will – Schlüssel aus
  /// [duplikatPaarSchluessel]. Ein Paar darin wird nicht zusammengefasst.
  ///
  /// Es bleibt bei einem Vorbehalt, den man kennen sollte: Sind A und B
  /// ausgenommen, aber beide einem dritten Foto C ähnlich, landen sie über
  /// C trotzdem in einer Gruppe. Das ist keine Nachlässigkeit, sondern die
  /// Natur der Gruppenbildung – C hält sie zusammen, und eine Gruppe
  /// aufzubrechen, weil eines der Paare darin ausgenommen ist, wäre die
  /// falschere Antwort.
  final Set<String> ausnahmen;

  const DuplicateSearchParams(
    this.embeddings,
    this.threshold, {
    this.ausnahmen = const {},
  });
}

/// Der Schlüssel eines Foto-Paares, unabhängig von der Reihenfolge.
///
/// Dieselbe Funktion für die Datenbank und für den Isolate-Lauf – zwei
/// Fassungen desselben Formats wären genau die Art Fehler, die sich als
/// „die Ausnahme wirkt nicht" zeigt und nirgends auffällt.
String duplikatPaarSchluessel(String a, String b) =>
    a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';

/// Eingabe für [findBurstGroups] – siehe [DuplicateSearchParams].
class BurstSearchParams {
  final Map<String, Float32List> embeddings;
  final Map<String, DateTime> fileCreatedAt;
  final double threshold;
  final Duration maxGap;
  const BurstSearchParams(
    this.embeddings,
    this.fileCreatedAt, {
    this.threshold = 0.92,
    this.maxGap = const Duration(seconds: 30),
  });
}

/// Anzahl unabhängiger Zufalls-Projektionen für die Vorfilterung (siehe
/// [candidateIndexPairs]).
///
/// **Vorher standen hier 2 Projektionen mit einem Fenster von 200, und
/// das war die schlechteste Wahl auf der ganzen Kurve.** Bei gleichem
/// Aufwand ist es weit besser, oft zu projizieren und jeweils nur wenige
/// Nachbarn anzusehen: Zwei Sortierungen sind zwei Chancen, und ein
/// breites Fenster in einer schlechten Sortierung hilft nicht. An der
/// gewachsenen Bibliothek gemessen (7475 Einbettungen, Schwelle 0,98) –
/// gezählt werden **Gruppen**, wie der Nutzer sie sieht, nicht Paare:
///
/// ```
/// Wahrheit (alle gegen alle, 9,2 s)   42 Gruppen, 97 Fotos
///
///  2 x 200 (vorher)  2.857.158 Paare  21 Gruppen (50 %)  1182 ms
/// 16 x  25           2.725.401 Paare  37 Gruppen (88 %)  1243 ms
/// 32 x  16           3.358.697 Paare  41 Gruppen (98 %)  1557 ms
/// 16 x  50           5.282.401 Paare  41 Gruppen (98 %)  2379 ms
/// ```
///
/// Die alte Einstellung übersah also die **Hälfte aller Duplikatgruppen**
/// – der Kommentar an dieser Stelle nannte die Chance, ein Paar zu
/// verpassen, „in der Praxis vernachlässigbar". Sie war es nicht.
const _projectionCount = 32;

/// Feste statt echter Zufalls-Seeds: dieselben Projektionsrichtungen bei
/// jedem Lauf, sonst wäre nicht reproduzierbar, welche Gruppen bei
/// identischen Daten gefunden werden.
int _projectionSeed(int p) => 0x5EED0001 + p;

/// Wie viele Nachbarn in der sortierten Projektions-Reihenfolge jeweils
/// verglichen werden – begrenzt die Vorfilterung auf O(n · Fenster) statt
/// O(n²). Siehe [_projectionCount] für die Messung, aus der die 16 kommt.
const _slidingWindow = 16;

/// Wie viele Nachbarn eine Aufnahme in der Zeitsortierung höchstens
/// bekommt (siehe [zeitnachbarPaare]).
///
/// **Wogegen das schützt.** Eine Kamera mit ungestellter Uhr schreibt in
/// jede Datei dieselbe Zeit. In dieser Bibliothek tragen 948 Aufnahmen
/// denselben Zeitstempel; ohne Deckel wären das allein 449.000 Paare, und
/// bei einer Bibliothek mit zehntausend solcher Dateien liefe die Suche
/// minutenlang. Eine echte Serie hat ein paar Dutzend Bilder – 500 ist
/// grosszügig. Gemessen kostet der Deckel 6 von 518 Serien.
const zeitnachbarnDeckel = 500;

/// Gruppiert Foto-IDs anhand paarweiser Kosinus-Ähnlichkeit ihrer
/// CLIP-Embeddings (Union-Find über eine vorgefilterte Kandidatenliste, siehe
/// [candidateIndexPairs]). Bewusst als TOP-LEVEL-Funktion ausgelagert (statt
/// eine Methode auf einem State), damit sie über [compute] in einem eigenen
/// Isolate laufen kann.
///
/// Ein reiner Alle-gegen-alle-Vergleich ist O(n²) – bei 100.000 Fotos wären
/// das ~5 Milliarden Kosinus-Vergleiche (praktisch nie fertig). Die
/// Vorfilterung über zufällige Projektionen (eine Form von Locality-Sensitive
/// Hashing) reduziert das auf O(n · Projektionen · Fenster), auf Kosten
/// einer (bei diesen Parametern in der Praxis vernachlässigbaren, aber nicht
/// mathematisch ausgeschlossenen) Chance, ein Paar zu übersehen, dessen
/// Embeddings in KEINER der Projektionen nah beieinander landen.
List<List<String>> findDuplicateGroups(DuplicateSearchParams params) {
  final embeddings = params.embeddings;
  final ids = embeddings.keys.toList(growable: false);
  final n = ids.length;
  final vectors = List<Float32List>.generate(n, (i) => embeddings[ids[i]]!, growable: false);

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

  final ausnahmen = params.ausnahmen;
  for (final packed in candidateIndexPairs(vectors)) {
    final i = packed ~/ n;
    final j = packed % n;
    // Die Prüfung erst NACH dem Kosinus: Der Vergleich ist billiger als das
    // Zusammensetzen eines Schlüssels, und ausgenommene Paare sind die
    // grosse Ausnahme.
    if (_cosineSimilarity(vectors[i], vectors[j]) < params.threshold) continue;
    if (ausnahmen.isNotEmpty &&
        ausnahmen.contains(duplikatPaarSchluessel(ids[i], ids[j]))) {
      continue;
    }
    union(i, j);
  }

  return _resolveClusters(parent, n, ids);
}

/// Wie [findDuplicateGroups], verlangt beim Zusammenfassen zusätzlich, dass
/// die beiden Fotos zeitlich höchstens [BurstSearchParams.maxGap]
/// auseinanderliegen ("Serie"/Burst statt inhaltlich ähnlicher, aber
/// zeitlich unabhängiger Aufnahmen) – Fotos ohne bekanntes Aufnahmedatum
/// werden nie gruppiert (sicherer Default statt einer geratenen Zeit).
List<List<String>> findBurstGroups(BurstSearchParams params) {
  final embeddings = params.embeddings;
  final ids = embeddings.keys.toList(growable: false);
  final n = ids.length;
  final vectors = List<Float32List>.generate(n, (i) => embeddings[ids[i]]!, growable: false);
  final timestamps = List<DateTime?>.generate(n, (i) => params.fileCreatedAt[ids[i]], growable: false);

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

  // **Hier ist die Zeit der Vorfilter, nicht die Zufallsprojektion.**
  // Eine Serie verlangt ohnehin, dass zwei Aufnahmen höchstens
  // [BurstSearchParams.maxGap] auseinanderliegen. Diese Bedingung ist
  // exakt, sie ist nach dem Sortieren praktisch umsonst zu prüfen, und
  // sie ist weit schärfer als jede Ähnlichkeitsschätzung – Fotos, die
  // dreissig Sekunden auseinanderliegen, sind ein winziger Teil der
  // Bibliothek. Die Projektionen dagegen wissen nichts von der Zeit und
  // verwarfen deshalb Serien, die sie hätten finden müssen.
  //
  // An der gewachsenen Bibliothek gemessen (7475 Einbettungen):
  //
  //   Wahrheit (alle gegen alle)     518 Gruppen, 1733 Fotos
  //   vorher, über die Projektionen  324 Gruppen (63 %), 227 ms
  //   über die Zeit, mit Deckel      512 Gruppen (99 %), 153 ms
  //
  // Besser und schneller zugleich, weil dieselbe Bedingung vorher
  // NACH dem teuren Vergleich stand statt davor.
  for (final packed in zeitnachbarPaare(timestamps, params.maxGap)) {
    final i = packed ~/ n;
    final j = packed % n;
    if (_cosineSimilarity(vectors[i], vectors[j]) >= params.threshold) union(i, j);
  }

  return _resolveClusters(parent, n, ids);
}

/// Alle Indexpaare, deren Zeitstempel höchstens [maxGap] auseinanderliegen.
///
/// Aufnahmen ohne Datum kommen nicht vor – ein geratener Zeitpunkt wäre
/// die schlechtere Antwort als gar keine Serie. Gepackt wie in
/// [candidateIndexPairs] (`kleinerIndex * n + grössererIndex`).
///
/// Je Aufnahme höchstens [zeitnachbarnDeckel] Nachbarn, siehe dort.
List<int> zeitnachbarPaare(List<DateTime?> zeitstempel, Duration maxGap) {
  final n = zeitstempel.length;
  final datiert = [
    for (var i = 0; i < n; i++)
      if (zeitstempel[i] != null) i
  ]..sort((a, b) => zeitstempel[a]!.compareTo(zeitstempel[b]!));

  final paare = <int>[];
  for (var a = 0; a < datiert.length; a++) {
    final ia = datiert[a];
    final ta = zeitstempel[ia]!;
    var nachbarn = 0;
    for (var b = a + 1; b < datiert.length; b++) {
      final ib = datiert[b];
      // Sortiert, also ist die Differenz nie negativ und der erste
      // Ausreisser beendet das Fenster.
      if (zeitstempel[ib]!.difference(ta) > maxGap) break;
      if (++nachbarn > zeitnachbarnDeckel) break;
      paare.add(ia < ib ? ia * n + ib : ib * n + ia);
    }
  }
  return paare;
}

List<List<String>> _resolveClusters(List<int> parent, int n, List<String> ids) {
  int find(int x) {
    while (parent[x] != x) {
      x = parent[x];
    }
    return x;
  }

  final clusters = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    clusters.putIfAbsent(find(i), () => []).add(i);
  }
  return clusters.values
      .where((g) => g.length >= 2)
      .map((g) => g.map((i) => ids[i]).toList())
      .toList()
    ..sort((a, b) => b.length.compareTo(a.length));
}

/// Sortiert die Embeddings [_projectionCount]-mal nach ihrer Projektion auf
/// eine feste Zufallsrichtung und bildet aus jeweils benachbarten Einträgen
/// (innerhalb von [_slidingWindow]) Kandidaten-Indexpaare – siehe
/// [findDuplicateGroups] für die Begründung. Jedes Paar wird als einzelner
/// `int` gepackt (`kleinerIndex * n + größerIndex`) statt als Tupel, damit
/// das deduplizierende `Set` reine Integer- statt String-Hashes nutzt.
///
/// Öffentlich, weil die Grösse des Ergebnisses das eigentliche Mass der
/// Vorfilterung ist: Genau so viele Paare werden anschliessend wirklich
/// verglichen, gegenüber `n·(n-1)/2` beim Alle-gegen-alle-Durchlauf. Das
/// lässt sich prüfen, ohne eine Uhr zu befragen – und eine Uhr auf einer
/// ausgelasteten Maschine hat genau diesen Test unzuverlässig gemacht.
Set<int> candidateIndexPairs(List<Float32List> vectors) {
  final n = vectors.length;
  if (n < 2) return {};
  final dim = vectors.first.length;

  final pairs = <int>{};
  for (var p = 0; p < _projectionCount; p++) {
    final direction = _randomDirection(dim, _projectionSeed(p));
    final projValues = Float64List(n);
    for (var i = 0; i < n; i++) {
      projValues[i] = _cosineSimilarity(vectors[i], direction);
    }
    final order = List<int>.generate(n, (i) => i)
      ..sort((a, b) => projValues[a].compareTo(projValues[b]));

    for (var i = 0; i < n; i++) {
      final end = math.min(i + _slidingWindow, n);
      for (var j = i + 1; j < end; j++) {
        final a = order[i], b = order[j];
        final lo = math.min(a, b), hi = math.max(a, b);
        pairs.add(lo * n + hi);
      }
    }
  }
  return pairs;
}

/// Deterministische "Zufalls"-Richtung (fester Seed, siehe [_projectionSeeds])
/// derselben Dimension wie die CLIP-Embeddings, für [candidateIndexPairs].
Float32List _randomDirection(int dim, int seed) {
  final rand = math.Random(seed);
  final v = Float32List(dim);
  var normSq = 0.0;
  for (var i = 0; i < dim; i++) {
    final x = rand.nextDouble() * 2 - 1;
    v[i] = x;
    normSq += x * x;
  }
  final norm = math.sqrt(normSq);
  if (norm > 0) {
    for (var i = 0; i < dim; i++) {
      v[i] = v[i] / norm;
    }
  }
  return v;
}

/// Öffentlich, weil auch SecondLibraryScanService dieselbe Kosinus-
/// Ähnlichkeit für einzelne Paare braucht (nicht nur die Gruppenbildung
/// hier) – z.B. um einer gefundenen externen Übereinstimmung einen
/// konkreten Ähnlichkeitswert für die Anzeige mitzugeben.
double cosineSimilarity(Float32List a, Float32List b) => _cosineSimilarity(a, b);

double _cosineSimilarity(Float32List a, Float32List b) {
  var dot = 0.0;
  final len = math.min(a.length, b.length);
  for (var i = 0; i < len; i++) {
    dot += a[i] * b[i];
  }
  return dot; // Embeddings sind bereits L2-normalisiert
}
