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
  final vectors = List<Float32List>.generate(
    n,
    (i) => embeddings[ids[i]]!,
    growable: false,
  );

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
  final simd = _simdVektoren(vectors);
  final kandidaten = _kandidatenJeIndex(vectors);
  // Jeder Kandidat steht so oft in der Liste, wie Projektionen ihn
  // vorschlagen. Ein Merker je Index ersetzt das Set, das früher die
  // Wiederholungen aussortierte: 3,6 Millionen Hash-Einträge kosteten an
  // der Bibliothek ein Viertel der ganzen Suche.
  final zuletzt = Int32List(n)..fillRange(0, n, -1);
  for (var i = 0; i < n; i++) {
    final vi = simd[i];
    for (var k = kandidaten.start[i]; k < kandidaten.start[i + 1]; k++) {
      final j = kandidaten.ziel[k];
      if (zuletzt[j] == i) continue;
      zuletzt[j] = i;
      if (!_mindestensAehnlich(
        vi,
        simd[j],
        vectors[i],
        vectors[j],
        params.threshold,
      )) {
        continue;
      }
      // Die Prüfung erst NACH dem Kosinus: Der Vergleich ist billiger als
      // das Zusammensetzen eines Schlüssels, und ausgenommene Paare sind
      // die grosse Ausnahme.
      if (ausnahmen.isNotEmpty &&
          ausnahmen.contains(duplikatPaarSchluessel(ids[i], ids[j]))) {
        continue;
      }
      union(i, j);
    }
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
  final vectors = List<Float32List>.generate(
    n,
    (i) => embeddings[ids[i]]!,
    growable: false,
  );
  final timestamps = List<DateTime?>.generate(
    n,
    (i) => params.fileCreatedAt[ids[i]],
    growable: false,
  );

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
  final simd = _simdVektoren(vectors);
  for (final packed in zeitnachbarPaare(timestamps, params.maxGap)) {
    final i = packed ~/ n;
    final j = packed % n;
    if (_mindestensAehnlich(
      simd[i],
      simd[j],
      vectors[i],
      vectors[j],
      params.threshold,
    )) {
      union(i, j);
    }
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
      if (zeitstempel[i] != null) i,
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
/// `int` gepackt (`kleinerIndex * n + größerIndex`).
///
/// Öffentlich, weil die Grösse des Ergebnisses das eigentliche Mass der
/// Vorfilterung ist: Genau so viele Paare werden anschliessend wirklich
/// verglichen, gegenüber `n·(n-1)/2` beim Alle-gegen-alle-Durchlauf. Das
/// lässt sich prüfen, ohne eine Uhr zu befragen – und eine Uhr auf einer
/// ausgelasteten Maschine hat genau diesen Test unzuverlässig gemacht.
/// Die Suche selbst nimmt [_kandidatenJeIndex] und braucht dieses Set nicht.
Set<int> candidateIndexPairs(List<Float32List> vectors) {
  final n = vectors.length;
  if (n < 2) return {};
  final k = _kandidatenJeIndex(vectors);
  return {
    for (var i = 0; i < n; i++)
      for (var x = k.start[i]; x < k.start[i + 1]; x++) i * n + k.ziel[x],
  };
}

/// Die Kandidaten aus [candidateIndexPairs], nach dem kleineren Index
/// geordnet: `ziel[start[i] .. start[i + 1]]` sind die grösseren Indizes,
/// mit denen `i` verglichen wird – mit Wiederholungen, wenn mehrere
/// Projektionen dasselbe Paar vorschlagen.
///
/// Zwei Durchgänge über dieselben Sortierungen (erst zählen, dann
/// eintragen) statt eines Sets: keine Hashes, nur zwei Ganzzahl-Felder.
({Int32List start, Int32List ziel}) _kandidatenJeIndex(
  List<Float32List> vectors,
) {
  final n = vectors.length;
  final start = Int32List(n + 1);
  if (n < 2) return (start: start, ziel: Int32List(0));
  final dim = vectors.first.length;

  final ordnungen = <Int32List>[];
  for (var p = 0; p < _projectionCount; p++) {
    final direction = _randomDirection(dim, _projectionSeed(p));
    final projValues = Float64List(n);
    for (var i = 0; i < n; i++) {
      projValues[i] = _cosineSimilarity(vectors[i], direction);
    }
    final order = List<int>.generate(n, (i) => i)
      ..sort((a, b) => projValues[a].compareTo(projValues[b]));
    ordnungen.add(Int32List.fromList(order));
  }

  for (final order in ordnungen) {
    for (var i = 0; i < n; i++) {
      final end = math.min(i + _slidingWindow, n);
      for (var j = i + 1; j < end; j++) {
        start[math.min(order[i], order[j]) + 1]++;
      }
    }
  }
  for (var i = 0; i < n; i++) {
    start[i + 1] += start[i];
  }
  final ziel = Int32List(start[n]);
  final frei = Int32List.fromList(start.sublist(0, n));
  for (final order in ordnungen) {
    for (var i = 0; i < n; i++) {
      final end = math.min(i + _slidingWindow, n);
      for (var j = i + 1; j < end; j++) {
        final a = order[i], b = order[j];
        if (a < b) {
          ziel[frei[a]++] = b;
        } else {
          ziel[frei[b]++] = a;
        }
      }
    }
  }
  return (start: start, ziel: ziel);
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
double cosineSimilarity(Float32List a, Float32List b) =>
    _cosineSimilarity(a, b);

double _cosineSimilarity(Float32List a, Float32List b) {
  var dot = 0.0;
  final len = math.min(a.length, b.length);
  for (var i = 0; i < len; i++) {
    dot += a[i] * b[i];
  }
  return dot; // Embeddings sind bereits L2-normalisiert
}

/// Die Vektoren als [Float32x4List] für das Skalarprodukt in
/// [_mindestensAehnlich] – als Ansicht auf denselben Speicher, wenn er
/// passend ausgerichtet ist (bei den Einbettungen aus der Datenbank
/// immer), sonst als Kopie, mit Nullen auf ein Vielfaches von vier
/// aufgefüllt.
List<Float32x4List> _simdVektoren(List<Float32List> vectors) => [
  for (final v in vectors)
    if (v.offsetInBytes % 16 == 0 && v.length % 4 == 0)
      Float32x4List.view(v.buffer, v.offsetInBytes, v.length ~/ 4)
    else
      Float32x4List.view(
        (Float32List((v.length + 3) & ~3)..setAll(0, v)).buffer,
      ),
];

/// Ob [a] und [b] mindestens [schwelle] ähnlich sind – mit derselben
/// Antwort wie [_cosineSimilarity], aber rund dreimal so schnell.
///
/// Gerechnet wird vier Werte auf einmal in einfacher Genauigkeit. Deren
/// Fehler bleibt bei normierten Vektoren mit 512 Werten weit unter
/// [_simdSpielraum]; nur was so nah an der Schwelle liegt, rechnet
/// [_cosineSimilarity] in doppelter Genauigkeit nach. So entscheidet die
/// schnelle Rechnung kein Paar anders als die genaue – an der Bibliothek
/// geprüft: dieselben 527 Gruppen, 0,45 statt 1,5 Sekunden.
bool _mindestensAehnlich(
  Float32x4List a,
  Float32x4List b,
  Float32List aGenau,
  Float32List bGenau,
  double schwelle,
) {
  final n = math.min(a.length, b.length);
  var s0 = Float32x4.zero(), s1 = Float32x4.zero();
  var i = 0;
  for (; i + 1 < n; i += 2) {
    s0 += a[i] * b[i];
    s1 += a[i + 1] * b[i + 1];
  }
  if (i < n) s0 += a[i] * b[i];
  final s = s0 + s1;
  final schnell = s.x + s.y + s.z + s.w;
  if (schnell < schwelle - _simdSpielraum) return false;
  if (schnell >= schwelle + _simdSpielraum) return true;
  return _cosineSimilarity(aGenau, bGenau) >= schwelle;
}

/// Wie weit die Rechnung in einfacher Genauigkeit höchstens danebenliegt
/// – reichlich bemessen: Der Fehler einer Summe aus 512 Produkten normierter
/// Werte liegt in der Grössenordnung 10⁻⁶.
const _simdSpielraum = 1e-4;
