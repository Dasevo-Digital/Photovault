import 'dart:math' as math;

/// Bounding Box eines erkannten Gesichts, normalisiert 0..1 relativ zur
/// Bildgröße (Ursprung oben links).
///
/// [landmarks] sind, falls von YuNet geliefert, 5 Punkte (rechtes Auge,
/// linkes Auge, Nasenspitze, rechter und linker Mundwinkel – in exakt der
/// Reihenfolge, die auch SFace/OpenCVs Referenz-Alignment erwartet) als
/// flache Liste `[x0,y0,x1,y1,...,x4,y4]`, ebenfalls normalisiert 0..1.
/// `null`, wenn keine Landmarks vorliegen (z.B. bei manuell eingezeichneten
/// Gesichtern) – dann greift beim Einbetten der einfache Bounding-Box-Crop
/// als Fallback.
class DetectedFace {
  final double x, y, width, height;
  final double score;
  final List<double>? landmarks;
  DetectedFace(this.x, this.y, this.width, this.height, this.score, {this.landmarks});
}

/// Reine, deterministische Nachverarbeitung für YuNets Rohausgaben –
/// bewusst aus [FaceEngineService] herausgezogen, damit sie ohne echte
/// ONNX-Runtime-Inferenz unit-testbar ist (siehe
/// test/face_postprocess_test.dart). Deckt genau den Teil ab, der als
/// "Best-Effort-Nachbau ... ohne Zugriff auf eine echte ONNX-Runtime-
/// Umgebung nachimplementiert" dokumentiert war – die Box-Decodierung
/// (Anchor-Zelle -> Bounding Box) und Non-Maximum-Suppression lassen sich
/// unabhängig von Modellgewichten anhand von Geometrie prüfen.
class FacePostprocess {
  /// Decodiert eine einzelne YuNet-Anchor-Zelle in eine normalisierte
  /// (0..1) Bounding Box. [dx]/[dy]/[dw]/[dh] sind die rohen
  /// Netzwerk-Ausgaben für diese Zelle, [row]/[col] die Position im Grid,
  /// [stride] die Feature-Map-Stride-Stufe (8/16/32) und [inputSize] die
  /// quadratische Eingabegröße des Netzes (640).
  static DetectedFace decodeBox({
    required int row,
    required int col,
    required int stride,
    required double dx,
    required double dy,
    required double dw,
    required double dh,
    required int inputSize,
    required double score,
    List<double>? landmarks,
  }) {
    final cx = (col + dx) * stride;
    final cy = (row + dy) * stride;
    final w = math.exp(dw) * stride;
    final h = math.exp(dh) * stride;
    final x1 = cx - w / 2;
    final y1 = cy - h / 2;

    return DetectedFace(
      (x1 / inputSize).clamp(0.0, 1.0),
      (y1 / inputSize).clamp(0.0, 1.0),
      (w / inputSize).clamp(0.0, 1.0),
      (h / inputSize).clamp(0.0, 1.0),
      score,
      landmarks: landmarks,
    );
  }

  /// Decodiert die 5 Landmark-Punkte einer YuNet-Anchor-Zelle, analog zu
  /// [decodeBox]: dieselbe Zellen-relative Offset-Kodierung wie die
  /// Box-Mitte, aber ohne den `exp(...)`-Term (Punkte statt einer Größe).
  /// [kps] sind die 10 rohen Netzwerk-Ausgaben dieser Zelle (5 Punkte x/y).
  static List<double> decodeLandmarks({
    required int row,
    required int col,
    required int stride,
    required List<double> kps,
    required int inputSize,
  }) {
    final result = List<double>.filled(10, 0.0);
    for (var i = 0; i < 5; i++) {
      final px = (col + kps[i * 2]) * stride;
      final py = (row + kps[i * 2 + 1]) * stride;
      result[i * 2] = (px / inputSize).clamp(0.0, 1.0);
      result[i * 2 + 1] = (py / inputSize).clamp(0.0, 1.0);
    }
    return result;
  }

  /// Kombinierter Klassifikations-/Objektheits-Score einer Anchor-Zelle
  /// (geometrisches Mittel), wie von YuNet verwendet.
  static double combinedScore(double classScore, double objectnessScore) =>
      math.sqrt(classScore.clamp(0, 1) * objectnessScore.clamp(0, 1));

  static double iou(DetectedFace a, DetectedFace b) {
    final ax2 = a.x + a.width, ay2 = a.y + a.height;
    final bx2 = b.x + b.width, by2 = b.y + b.height;
    final interX1 = math.max(a.x, b.x);
    final interY1 = math.max(a.y, b.y);
    final interX2 = math.min(ax2, bx2);
    final interY2 = math.min(ay2, by2);
    final interArea = math.max(0.0, interX2 - interX1) * math.max(0.0, interY2 - interY1);
    final unionArea = a.width * a.height + b.width * b.height - interArea;
    return unionArea <= 0 ? 0 : interArea / unionArea;
  }

  /// Greedy Non-Maximum-Suppression: behält je Gruppe stark überlappender
  /// Boxen ([iouThreshold]) nur die mit dem höchsten Score.
  static List<DetectedFace> nonMaxSuppression(
    List<DetectedFace> boxes, {
    required double iouThreshold,
  }) {
    final sorted = List<DetectedFace>.from(boxes)..sort((a, b) => b.score.compareTo(a.score));
    final kept = <DetectedFace>[];
    for (final candidate in sorted) {
      var overlaps = false;
      for (final k in kept) {
        if (iou(candidate, k) > iouThreshold) {
          overlaps = true;
          break;
        }
      }
      if (!overlaps) kept.add(candidate);
    }
    return kept;
  }
}
