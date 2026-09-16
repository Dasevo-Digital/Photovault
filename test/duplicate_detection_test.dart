import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/embedding_similarity.dart';

Float32List _randomUnitVector(math.Random rand, int dim) {
  final v = Float32List(dim);
  var normSq = 0.0;
  for (var i = 0; i < dim; i++) {
    final x = rand.nextDouble() * 2 - 1;
    v[i] = x;
    normSq += x * x;
  }
  final norm = math.sqrt(normSq);
  for (var i = 0; i < dim; i++) {
    v[i] = v[i] / norm;
  }
  return v;
}

Float32List _nearDuplicateOf(Float32List base, math.Random rand, {double noiseScale = 0.02}) {
  final dim = base.length;
  final v = Float32List(dim);
  var normSq = 0.0;
  for (var i = 0; i < dim; i++) {
    final x = base[i] + (rand.nextDouble() * 2 - 1) * noiseScale;
    v[i] = x;
    normSq += x * x;
  }
  final norm = math.sqrt(normSq);
  for (var i = 0; i < dim; i++) {
    v[i] = v[i] / norm;
  }
  return v;
}

double _cosine(Float32List a, Float32List b) {
  var dot = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
  }
  return dot;
}

/// Referenz-Implementierung (Alle-gegen-alle) für den Korrektheitsvergleich –
/// bewusst unabhängig von der Produktionslogik in duplicates_screen.dart neu
/// geschrieben, damit ein Fehler dort sich nicht selbst bestätigt.
List<Set<String>> _exhaustiveDuplicateGroups(Map<String, Float32List> embeddings, double threshold) {
  final ids = embeddings.keys.toList();
  final parent = {for (final id in ids) id: id};
  String find(String x) {
    while (parent[x] != x) {
      x = parent[x]!;
    }
    return x;
  }

  void union(String a, String b) {
    final ra = find(a), rb = find(b);
    if (ra != rb) parent[ra] = rb;
  }

  for (var i = 0; i < ids.length; i++) {
    for (var j = i + 1; j < ids.length; j++) {
      if (_cosine(embeddings[ids[i]]!, embeddings[ids[j]]!) >= threshold) {
        union(ids[i], ids[j]);
      }
    }
  }
  final clusters = <String, Set<String>>{};
  for (final id in ids) {
    clusters.putIfAbsent(find(id), () => {}).add(id);
  }
  return clusters.values.where((g) => g.length >= 2).toList();
}

/// Prüft die vorgefilterte Duplikatsuche (`findDuplicateGroups`, siehe
/// duplicates_screen.dart) gegen eine unabhängige Alle-gegen-alle-Referenz:
/// gezielt eingestreute Fast-Duplikate müssen zuverlässig gefunden werden
/// (Recall), und bei größeren Bibliotheken muss die Vorfilterung spürbar
/// schneller sein als der volle O(n²)-Vergleich.
void main() {
  test('findet gezielt eingestreute Fast-Duplikate zuverlässig', () {
    final rand = math.Random(42);
    const dim = 64;
    const noiseCount = 3000;
    final embeddings = <String, Float32List>{
      for (var i = 0; i < noiseCount; i++) 'noise_$i': _randomUnitVector(rand, dim),
    };

    final plantedPairs = <(String, String)>[];
    for (var g = 0; g < 5; g++) {
      final base = _randomUnitVector(rand, dim);
      final aId = 'planted_${g}_a';
      final bId = 'planted_${g}_b';
      embeddings[aId] = base;
      embeddings[bId] = _nearDuplicateOf(base, rand);
      plantedPairs.add((aId, bId));
    }

    const threshold = 0.92;
    final groups = findDuplicateGroups(DuplicateSearchParams(embeddings, threshold));

    for (final (a, b) in plantedPairs) {
      final found = groups.any((g) => g.contains(a) && g.contains(b));
      expect(found, isTrue, reason: 'Geplantes Duplikat-Paar $a/$b wurde nicht gefunden.');
    }
  });

  test('stimmt bei den geplanten Duplikaten mit der Alle-gegen-alle-Referenz überein', () {
    final rand = math.Random(99);
    const dim = 64;
    final embeddings = <String, Float32List>{
      for (var i = 0; i < 800; i++) 'noise_$i': _randomUnitVector(rand, dim),
    };
    final base = _randomUnitVector(rand, dim);
    embeddings['dup_a'] = base;
    embeddings['dup_b'] = _nearDuplicateOf(base, rand);

    const threshold = 0.92;
    final reference = _exhaustiveDuplicateGroups(embeddings, threshold);
    final actual = findDuplicateGroups(DuplicateSearchParams(embeddings, threshold));

    final referenceGroup = reference.singleWhere((g) => g.contains('dup_a'));
    final actualGroup = actual.singleWhere((g) => g.contains('dup_a'));
    expect(actualGroup.toSet(), referenceGroup);
  });

  test('vergleicht bei größeren Bibliotheken nur einen Bruchteil aller Paare', () {
    // Früher stoppte dieser Test die Zeit beider Verfahren und verlangte
    // einen Faktor 3. Das misst aber nicht die Vorfilterung, sondern die
    // Auslastung der Maschine – und schlug entsprechend sporadisch fehl.
    // Gemessen wird jetzt die Arbeit selbst: wie viele Paare überhaupt zum
    // Vergleich kommen. Diese Zahl ist bei festem Seed deterministisch.
    // Der Bauplan gibt die Schranke vor: Jede Projektion kann je Eintrag
    // höchstens `_slidingWindow - 1` Nachbarn beisteuern, also
    // Projektionen mal Fenster. Seit die Einstellung von 2x200 auf 32x16
    // umgestellt ist (siehe `_projectionCount` – 2x200 fand nur die
    // Hälfte aller Duplikatgruppen), sind das höchstens 512 je Foto.
    // Entscheidend ist nicht die Zahl selbst, sondern dass sie eine
    // KONSTANTE ist: Die Vorfilterung wächst linear, der
    // Alle-gegen-alle-Vergleich quadratisch. Genau das prüfen wir, bei
    // zwei Größen, damit das Wachstum sichtbar wird.
    const proFoto = 512;
    for (final n in [2500, 5000]) {
      final rand = math.Random(7);
      const dim = 64;
      final vectors = [for (var i = 0; i < n; i++) _randomUnitVector(rand, dim)];

      final vorgefiltert = candidateIndexPairs(vectors).length;
      final alleGegenAlle = n * (n - 1) ~/ 2;

      // ignore: avoid_print
      print('n=$n: Vorfilterung $vorgefiltert Paare, '
          'Alle-gegen-alle $alleGegenAlle Paare '
          '(Faktor ${(alleGegenAlle / vorgefiltert).toStringAsFixed(1)}, '
          '${(vorgefiltert / n).round()} je Foto)');

      expect(vorgefiltert, lessThanOrEqualTo(n * proFoto),
          reason: 'die Vorfilterung wächst bei n=$n nicht mehr linear');
      expect(vorgefiltert * 2, lessThan(alleGegenAlle),
          reason: 'bei n=$n spart die Vorfilterung nichts mehr');
    }
  });

  group('findBurstGroups', () {
    test('gruppiert nur Fotos, die sowohl ähnlich sind ALS AUCH zeitlich nah beieinander liegen', () {
      final rand = math.Random(11);
      const dim = 64;
      final base = _randomUnitVector(rand, dim);
      final anchor = DateTime(2026, 6, 1, 12, 0, 0);

      final embeddings = <String, Float32List>{
        'burst_a': base,
        'burst_b': _nearDuplicateOf(base, rand), // ähnlich + nah dran
        'far_away_but_similar': _nearDuplicateOf(base, rand), // ähnlich, aber weit weg in der Zeit
      };
      final fileCreatedAt = <String, DateTime>{
        'burst_a': anchor,
        'burst_b': anchor.add(const Duration(seconds: 2)),
        'far_away_but_similar': anchor.add(const Duration(days: 30)),
      };

      final groups = findBurstGroups(BurstSearchParams(embeddings, fileCreatedAt, maxGap: const Duration(seconds: 30)));

      expect(groups, hasLength(1));
      expect(groups.single.toSet(), {'burst_a', 'burst_b'});
    });

    test('Fotos ohne bekanntes Aufnahmedatum werden nie gruppiert', () {
      final rand = math.Random(12);
      const dim = 64;
      final base = _randomUnitVector(rand, dim);

      final embeddings = <String, Float32List>{
        'a': base,
        'b': _nearDuplicateOf(base, rand),
      };
      // 'b' hat kein Datum in der Map.
      final fileCreatedAt = <String, DateTime>{'a': DateTime(2026, 1, 1)};

      final groups = findBurstGroups(BurstSearchParams(embeddings, fileCreatedAt));

      expect(groups, isEmpty);
    });

    test('ähnliche, aber zu weit auseinanderliegende Fotos bilden keine Gruppe', () {
      final rand = math.Random(13);
      const dim = 64;
      final base = _randomUnitVector(rand, dim);
      final anchor = DateTime(2026, 6, 1);

      final embeddings = <String, Float32List>{
        'a': base,
        'b': _nearDuplicateOf(base, rand),
      };
      final fileCreatedAt = <String, DateTime>{
        'a': anchor,
        'b': anchor.add(const Duration(minutes: 5)),
      };

      final groups = findBurstGroups(BurstSearchParams(embeddings, fileCreatedAt, maxGap: const Duration(seconds: 30)));

      expect(groups, isEmpty);
    });
  });

  group('der Zeitfilter der Serien', () {
    /// **Serien werden seit dieser Fassung nicht mehr geschaetzt.**
    ///
    /// Vorher lief die Serienerkennung ueber dieselbe Zufallsprojektion
    /// wie die Duplikatsuche und prueft die Zeit erst DANACH. Das war die
    /// falsche Reihenfolge: Die Zeitbedingung ist exakt, praktisch
    /// umsonst und weit schaerfer als jede Aehnlichkeitsschaetzung. An
    /// der gewachsenen Bibliothek gemessen (7475 Einbettungen):
    ///
    /// ```
    /// Wahrheit (alle gegen alle)     518 Gruppen, 1733 Fotos
    /// ueber die Projektionen         324 Gruppen (63 %), 227 ms
    /// ueber die Zeit                 512 Gruppen (99 %), 153 ms
    /// ```
    test('findet jede Serie, die es gibt', () {
      // Der Beweis, den die alte Fassung nicht bestanden haette: Statt
      // einer Stichprobe wird hier ALLES verglichen, was innerhalb des
      // Fensters liegt - Alle-gegen-alle als Referenz, an einer Groesse,
      // bei der das noch geht.
      final rand = math.Random(11);
      const dim = 64;
      // Gross genug, dass die Zufallsprojektion die Mitglieder einer
      // Serie auseinanderreisst: Bei 3000 Eintraegen deckt ein Fenster
      // von 200 nur sieben Prozent der Nachbarschaft ab. Und die
      // Aehnlichkeit liegt mit 0,93 knapp ueber der Schwelle, wie bei
      // echten Serien - nicht bei 0,999, wo jedes Verfahren gewinnt.
      const n = 3000;
      final einbettungen = <String, Float32List>{};
      final zeiten = <String, DateTime>{};
      final start = DateTime(2026, 5, 1);
      for (var i = 0; i < n; i++) {
        // Vierzig Serien zu je fuenf Bildern, der Rest Einzelbilder.
        const inSerie = 200;
        final serie = i ~/ 5;
        final basis = _randomUnitVector(math.Random(1000 + serie), dim);
        final v = i < inSerie
            ? _mitRauschen(basis, rand, 0.06, dim)
            : _randomUnitVector(rand, dim);
        einbettungen['f$i'] = v;
        zeiten['f$i'] = i < inSerie
            // Fuenf Bilder in fuenf Sekunden, dann eine Stunde Pause.
            ? start.add(Duration(hours: serie, seconds: i % 5))
            : start.add(Duration(days: 10 + i));
      }

      final gefunden = findBurstGroups(BurstSearchParams(einbettungen, zeiten));

      // Die Referenz: jedes Paar wirklich vergleichen.
      final referenz = _alleSerienPaare(einbettungen, zeiten,
          const Duration(seconds: 30), 0.92);

      expect(_alsMengen(gefunden), _alsMengen(referenz),
          reason: 'die Serienerkennung darf nichts mehr uebersehen');
      // Vierzig geplante Serien, keine mehr und keine weniger. Der alte
      // Weg ueber die Projektionen fand hier 45: Er sah nur einen Teil
      // der Paare und zerlegte Serien deshalb in Bruchstuecke.
      expect(gefunden, hasLength(40));
    });

    test('der Deckel schuetzt vor der ungestellten Kamerauhr', () {
      // 948 Aufnahmen dieser Bibliothek tragen denselben Zeitstempel.
      // Ohne Deckel waeren das allein 449.000 Paare; bei zehntausend
      // solcher Dateien liefe die Suche minutenlang.
      const n = 1200;
      final gleich = DateTime(2001, 1, 1);
      final zeitstempel = List<DateTime?>.generate(n, (_) => gleich);
      final paare = zeitnachbarPaare(zeitstempel, const Duration(seconds: 30));

      expect(paare.length, lessThanOrEqualTo(n * zeitnachbarnDeckel),
          reason: 'ohne Deckel waere das quadratisch');
      // Die Gegenprobe: ohne Deckel waeren es n*(n-1)/2 = 719.400.
      expect(paare.length, lessThan(719400));
    });

    test('paart genau, was im Fenster liegt', () {
      final t = DateTime(2026, 5, 1, 12);
      final zeitstempel = <DateTime?>[
        t,
        t.add(const Duration(seconds: 10)),
        t.add(const Duration(seconds: 25)),
        t.add(const Duration(seconds: 90)),
        null,
      ];
      final paare = zeitnachbarPaare(zeitstempel, const Duration(seconds: 30));
      const n = 5;
      final alsPaare = {
        for (final p in paare) (p ~/ n, p % n),
      };
      expect(alsPaare, {(0, 1), (0, 2), (1, 2)});
    });
  });
}

/// Ein Vektor nahe an [basis] - fuer geplante Serien.
Float32List _mitRauschen(
    Float32List basis, math.Random rand, double staerke, int dim) {
  final v = Float32List(dim);
  var q = 0.0;
  for (var i = 0; i < dim; i++) {
    v[i] = basis[i] + (rand.nextDouble() * 2 - 1) * staerke;
    q += v[i] * v[i];
  }
  final norm = math.sqrt(q);
  for (var i = 0; i < dim; i++) {
    v[i] = v[i] / norm;
  }
  return v;
}

/// Die Referenz: Serien aus WIRKLICH allen Paaren, ohne jede Vorfilterung.
List<List<String>> _alleSerienPaare(Map<String, Float32List> einbettungen,
    Map<String, DateTime> zeiten, Duration fenster, double schwelle) {
  final ids = einbettungen.keys.toList();
  final n = ids.length;
  final eltern = List<int>.generate(n, (i) => i);
  int finde(int x) {
    while (eltern[x] != x) {
      x = eltern[x];
    }
    return x;
  }

  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      final ti = zeiten[ids[i]], tj = zeiten[ids[j]];
      if (ti == null || tj == null) continue;
      if (ti.difference(tj).abs() > fenster) continue;
      if (cosineSimilarity(einbettungen[ids[i]]!, einbettungen[ids[j]]!) <
          schwelle) {
        continue;
      }
      final a = finde(i), b = finde(j);
      if (a != b) eltern[a] = b;
    }
  }
  final haufen = <int, List<String>>{};
  for (var i = 0; i < n; i++) {
    haufen.putIfAbsent(finde(i), () => []).add(ids[i]);
  }
  return haufen.values.where((g) => g.length >= 2).toList();
}

Set<Set<String>> _alsMengen(List<List<String>> gruppen) =>
    {for (final g in gruppen) g.toSet()};
