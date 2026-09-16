import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/face_clustering_service.dart';

/// Erzeugt einen L2-normalisierten synthetischen Embedding-Vektor: eine
/// Basisrichtung leicht verrauscht, damit "dieselbe Person" (kleines
/// Rauschen) und "andere Person" (großer Winkel-Unterschied) realistisch
/// simuliert werden, ohne echte SFace-Inferenz zu brauchen.
Float32List _vector(List<double> base, {double noise = 0.0, int seed = 0}) {
  final v = Float32List.fromList(base);
  if (noise != 0) {
    var state = seed;
    for (var i = 0; i < v.length; i++) {
      state = (state * 1103515245 + 12345) & 0x7fffffff;
      final r = (state / 0x7fffffff - 0.5) * 2 * noise;
      v[i] += r;
    }
  }
  var normSq = 0.0;
  for (final x in v) {
    normSq += x * x;
  }
  final norm = math.sqrt(normSq);
  for (var i = 0; i < v.length; i++) {
    v[i] /= norm;
  }
  return v;
}

void main() {
  group('clusterFaces', () {
    test('gruppiert Gesichter mit sehr ähnlichem Embedding zu einem Cluster', () {
      const base = [1.0, 0.0, 0.0, 0.0];
      final input = FaceClusterInput({
        'a': _vector(base, noise: 0.01, seed: 1),
        'b': _vector(base, noise: 0.01, seed: 2),
        'c': _vector(base, noise: 0.01, seed: 3),
      }, 0.9);

      final clusters = clusterFaces(input);

      expect(clusters, hasLength(1));
      expect(clusters.single, unorderedEquals(['a', 'b', 'c']));
    });

    test('hält deutlich unterschiedliche Gesichter in getrennten Clustern', () {
      final input = FaceClusterInput({
        'a1': _vector([1.0, 0.0, 0.0, 0.0], noise: 0.01, seed: 1),
        'a2': _vector([1.0, 0.0, 0.0, 0.0], noise: 0.01, seed: 2),
        'b1': _vector([0.0, 1.0, 0.0, 0.0], noise: 0.01, seed: 3),
        'b2': _vector([0.0, 1.0, 0.0, 0.0], noise: 0.01, seed: 4),
      }, 0.9);

      final clusters = clusterFaces(input);

      expect(clusters, hasLength(2));
      // List/Set.== sind referenzbasiert, nicht inhaltsbasiert – deshalb
      // über kanonische, sortierte Strings statt Sammlungs-Gleichheit
      // vergleichen.
      final signatures = clusters.map((c) => (List.of(c)..sort()).join(',')).toSet();
      expect(signatures, contains('a1,a2'));
      expect(signatures, contains('b1,b2'));
    });

    test('schließt Einzelgesichter ohne ähnliches Gegenstück aus (Singletons)', () {
      final input = FaceClusterInput({
        'a1': _vector([1.0, 0.0, 0.0, 0.0], noise: 0.01, seed: 1),
        'a2': _vector([1.0, 0.0, 0.0, 0.0], noise: 0.01, seed: 2),
        'lonely': _vector([0.0, 0.0, 1.0, 0.0]),
      }, 0.9);

      final clusters = clusterFaces(input);

      expect(clusters, hasLength(1));
      expect(clusters.single, unorderedEquals(['a1', 'a2']));
    });

    test('respektiert die Schwellenwert-Grenze', () {
      // Kosinus-Ähnlichkeit der beiden Vektoren liegt klar unter 0.99,
      // aber über einem lockeren Schwellenwert von 0.5.
      final input = FaceClusterInput({
        'a': Float32List.fromList([1.0, 0.0]),
        'b': Float32List.fromList([0.8, 0.6]), // bereits normiert (0.8²+0.6²=1)
      }, 0.99);
      expect(clusterFaces(input), isEmpty);

      final looser = FaceClusterInput({
        'a': Float32List.fromList([1.0, 0.0]),
        'b': Float32List.fromList([0.8, 0.6]),
      }, 0.5);
      expect(looser.threshold, 0.5);
      expect(clusterFaces(looser), hasLength(1));
    });

    test('leere Eingabe liefert leere Cluster-Liste', () {
      expect(clusterFaces(const FaceClusterInput({}, 0.5)), isEmpty);
    });
  });

  group('meanNormalizedEmbedding', () {
    test('liefert einen Einheitsvektor', () {
      final mean = meanNormalizedEmbedding([
        Float32List.fromList([1.0, 0.0]),
        Float32List.fromList([0.0, 1.0]),
      ]);
      var normSq = 0.0;
      for (final v in mean) {
        normSq += v * v;
      }
      expect(normSq, closeTo(1.0, 1e-6));
    });

    test('Mittelwert identischer Vektoren ist derselbe Vektor', () {
      final v = Float32List.fromList([0.6, 0.8]);
      final mean = meanNormalizedEmbedding([v, v, v]);
      expect(mean[0], closeTo(0.6, 1e-6));
      expect(mean[1], closeTo(0.8, 1e-6));
    });
  });
}
