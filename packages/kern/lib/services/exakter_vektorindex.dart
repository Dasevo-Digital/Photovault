import 'dart:math' as math;
import 'dart:typed_data';
import 'clip_service.dart';

/// Kugelbaum mit konservativer Skalarprodukt-Schranke. Es werden nur
/// Teilbäume übersprungen, die keinen Top-K-Treffer enthalten können.
/// Der Eingabevorrat ist unveränderlich; bei neuem Modell/Stand wird eine
/// neue Instanz gebaut. Es gibt bewusst keinen persistierten Fremdindex.
class ExakterVektorindex {
  static bool passtInsBudget(Map<String, Float32List> vorrat) {
    final d = vorrat.values.firstOrNull?.length ?? 0;
    return vorrat.length >= 2000 &&
        d > 0 &&
        d <= 4096 &&
        vorrat.length * d * (4 + 16 / 24) <= 128 * 1024 * 1024;
  }

  ExakterVektorindex(this.vorrat) {
    final werte = vorrat.values;
    dimension = werte.firstOrNull?.length ?? 0;
    final bytes =
        vorrat.length *
        dimension *
        (4 + 16 / 24); // Vektorschnappschuss, Zentren und Boxen.
    if (vorrat.length < 2000 ||
        dimension == 0 ||
        dimension > 4096 ||
        bytes > 128 * 1024 * 1024 ||
        werte.any((v) => v.length != dimension || v.any((n) => !n.isFinite))) {
      return;
    }
    final eintraege = [for (final e in vorrat.entries) e];
    _reihenfolge = {
      for (var i = 0; i < eintraege.length; i++) eintraege[i].key: i,
    };
    _wurzel = _baue(eintraege, 0);
  }
  final Map<String, Float32List> vorrat;
  Map<String, Float32List>? _quelle;
  void bindeQuelle(Map<String, Float32List> quelle) {
    if (quelle.length != vorrat.length ||
        quelle.entries.any((e) {
          final v = vorrat[e.key];
          if (v == null || v.length != e.value.length) return true;
          for (var i = 0; i < v.length; i++) {
            if (v[i] != e.value[i] && !(v[i].isNaN && e.value[i].isNaN)) {
              return true;
            }
          }
          return false;
        })) {
      throw ArgumentError('pv_index_quelle');
    }
    _quelle = quelle;
  }

  bool passtZu(Map<String, Float32List> quelle) =>
      identical(_quelle ?? vorrat, quelle);
  late final int dimension;
  Map<String, int> _reihenfolge = {};
  _Knoten? _wurzel;
  int letzteGepruefteVektoren = 0;
  bool letzterRueckfall = false;

  _Knoten _baue(List<MapEntry<String, Float32List>> e, int tiefe) {
    final mitte = Float64List(dimension);
    for (final v in e) {
      for (var j = 0; j < dimension; j++) {
        mitte[j] += v.value[j] / e.length;
      }
    }
    final unten = Float32List(dimension)
      ..fillRange(0, dimension, double.infinity);
    final oben = Float32List(dimension)
      ..fillRange(0, dimension, double.negativeInfinity);
    var radius = 0.0;
    for (final v in e) {
      var sum = 0.0;
      for (var j = 0; j < dimension; j++) {
        unten[j] = math.min(unten[j], v.value[j]);
        oben[j] = math.max(oben[j], v.value[j]);
        final diff = v.value[j] - mitte[j];
        sum += diff * diff;
      }
      radius = math.max(radius, math.sqrt(sum));
    }
    // Deutlich größer als Rundungsfehler auch für nicht normierte Vektoren.
    radius += 1e-10 * (1 + radius) * dimension;
    if (e.length <= 48 || tiefe >= 24) {
      return _Knoten(mitte, radius, unten, oben, e, null, null);
    }
    var achse = 0, spanne = -1.0;
    for (var j = 0; j < dimension; j++) {
      var min = double.infinity, max = double.negativeInfinity;
      for (var i = 0; i < e.length; i += math.max(1, e.length ~/ 32)) {
        min = math.min(min, e[i].value[j]);
        max = math.max(max, e[i].value[j]);
      }
      if (max - min > spanne) {
        spanne = max - min;
        achse = j;
      }
    }
    e.sort((a, b) => a.value[achse].compareTo(b.value[achse]));
    final halb = e.length ~/ 2;
    return _Knoten(
      mitte,
      radius,
      unten,
      oben,
      null,
      _baue(e.sublist(0, halb), tiefe + 1),
      _baue(e.sublist(halb), tiefe + 1),
    );
  }

  List<MapEntry<String, double>> suche(
    Float32List query, {
    required bool Function(String) erlaubt,
    int topK = 200,
  }) {
    letzteGepruefteVektoren = 0;
    letzterRueckfall = false;
    if (topK <= 0) return [];
    if (_wurzel == null ||
        query.length != dimension ||
        query.any((v) => !v.isFinite)) {
      letzterRueckfall = true;
      letzteGepruefteVektoren = vorrat.length;
      return ClipService.rankBySimilarity(query, {
        for (final e in vorrat.entries)
          if (erlaubt(e.key)) e.key: e.value,
      }, topK: topK);
    }
    final heap = <({String key, double score, int order})>[];
    bool schlechter(int a, int b) =>
        heap[a].score < heap[b].score ||
        heap[a].score == heap[b].score && heap[a].order > heap[b].order;
    void tausche(int a, int b) {
      final v = heap[a];
      heap[a] = heap[b];
      heap[b] = v;
    }

    void einfuegen(String key, double score) {
      final v = (key: key, score: score, order: _reihenfolge[key]!);
      if (heap.length < topK) {
        heap.add(v);
        var i = heap.length - 1;
        while (i > 0) {
          final p = (i - 1) ~/ 2;
          if (!schlechter(i, p)) break;
          tausche(i, p);
          i = p;
        }
      } else {
        if (score < heap.first.score ||
            score == heap.first.score && v.order > heap.first.order) {
          return;
        }
        heap[0] = v;
        var i = 0;
        while (i * 2 + 1 < heap.length) {
          var c = i * 2 + 1;
          if (c + 1 < heap.length && schlechter(c + 1, c)) c++;
          if (!schlechter(c, i)) break;
          tausche(c, i);
          i = c;
        }
      }
    }

    var norm = 0.0;
    for (final q in query) {
      norm += q * q;
    }
    norm = math.sqrt(norm);
    double schranke(_Knoten k) {
      var dot = 0.0;
      for (var j = 0; j < dimension; j++) {
        dot += query[j] * k.mitte[j];
      }
      var box = 0.0;
      for (var j = 0; j < dimension; j++) {
        box += query[j] * (query[j] >= 0 ? k.oben[j] : k.unten[j]);
      }
      return math.min(box, dot + norm * k.radius) +
          1e-8 * (1 + box.abs() + dot.abs() + norm * k.radius) * dimension;
    }

    void besuche(_Knoten k, double oben) {
      if (heap.length == topK && oben < heap.first.score) return;
      if (k.blatt case final e?) {
        for (final v in e) {
          if (!erlaubt(v.key)) continue;
          letzteGepruefteVektoren++;
          var dot = 0.0;
          for (var j = 0; j < dimension; j++) {
            dot += query[j] * v.value[j];
          }
          einfuegen(v.key, dot);
        }
      } else {
        final links = k.links!,
            rechts = k.rechts!,
            l = schranke(links),
            r = schranke(rechts);
        if (l >= r) {
          besuche(links, l);
          besuche(rechts, r);
        } else {
          besuche(rechts, r);
          besuche(links, l);
        }
      }
    }

    besuche(_wurzel!, schranke(_wurzel!));
    heap.sort((a, b) {
      final n = b.score.compareTo(a.score);
      return n != 0 ? n : a.order.compareTo(b.order);
    });
    return [for (final v in heap) MapEntry(v.key, v.score)];
  }
}

class _Knoten {
  const _Knoten(
    this.mitte,
    this.radius,
    this.unten,
    this.oben,
    this.blatt,
    this.links,
    this.rechts,
  );
  final Float64List mitte;
  final double radius;
  final Float32List unten, oben;
  final List<MapEntry<String, Float32List>>? blatt;
  final _Knoten? links, rechts;
}

ExakterVektorindex erstelleVektorindex(Map<String, Float32List> vorrat) =>
    ExakterVektorindex(vorrat);
