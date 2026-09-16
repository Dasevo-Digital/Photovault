import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

import 'face_postprocess.dart';
import 'modellthreads.dart';

export 'face_postprocess.dart' show DetectedFace;

const int _yunetInputSize = 640; // entspricht der im ONNX-Graph fest hinterlegten Größe
const List<int> _yunetStrides = [8, 16, 32];
const int _sfaceInputSize = 112;

/// Vollständig lokale, quelloffene Gesichtserkennung + -wiedererkennung –
/// analog zu digiKams Ansatz, eigene CV-Modelle statt Betriebssystem-APIs
/// zu nutzen. Beide Modelle stammen aus OpenCV Zoo (Apache-2.0):
///
///   - YuNet (Detektion): https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet
///   - SFace (Embedding): https://github.com/opencv/opencv_zoo/tree/main/models/face_recognition_sface
///
/// WICHTIG (Transparenz): Der Postprocessing-Code für YuNet (Decodierung
/// der drei Feature-Map-Ebenen + Non-Maximum-Suppression, ausgelagert nach
/// [FacePostprocess]) ist ein Nachbau des öffentlich dokumentierten
/// Algorithmus aus OpenCVs eigenem C++/Python-Code. Die reine Geometrie
/// (Box-Decodierung, IoU, NMS) ist inzwischen unit-getestet (siehe
/// test/face_postprocess_test.dart) – **nicht** abgedeckt ist damit, ob die
/// tatsächlichen ONNX-Rohwerte des YuNet-Modells korrekt interpretiert
/// werden (Eingabenamen/-Layout der drei Feature-Map-Ebenen); das lässt
/// sich nur mit einer echten ONNX-Runtime-Umgebung und echten Testfotos
/// überprüfen (Bounding Boxes im Foto-Detailansicht-Overlay gegen bekannte
/// Gesichtszahl/-position abgleichen).
///
/// Für die SFace-Einbettung wird, sofern YuNet für ein Gesicht die 5
/// Landmark-Punkte liefert (Augen, Nase, Mundwinkel), eine
/// Ähnlichkeitstransformation (Rotation + gleichmäßige Skalierung +
/// Verschiebung) auf das SFace-Referenz-Layout angewendet ([alignFace]) –
/// genau die Vorverarbeitung, die OpenCVs eigene Referenzimplementierung
/// (`FaceRecognizerSF::alignCrop`) nutzt. Ohne Landmarks (z.B. bei manuell
/// eingezeichneten Gesichtern) fällt der Code auf einen einfachen
/// Bounding-Box-Crop zurück, was die Wiedererkennungsgenauigkeit in diesem
/// Fall reduziert.
class FaceEngineService {
  FaceEngineService._(this._detector, this._recognizer);

  final OrtSession _detector;
  final OrtSession? _recognizer;

  static bool isDetectionAvailable(String modelsDir) =>
      File('$modelsDir/face_detection_yunet.onnx').existsSync();

  static bool isRecognitionAvailable(String modelsDir) =>
      File('$modelsDir/face_recognition_sface.onnx').existsSync();

  static Future<FaceEngineService?> load(String modelsDir) async {
    if (!isDetectionAvailable(modelsDir)) return null;
    final ort = OnnxRuntime();
    final detector = await ort.createSession('$modelsDir/face_detection_yunet.onnx',
        options: modelloptionen());
    OrtSession? recognizer;
    if (isRecognitionAvailable(modelsDir)) {
      recognizer = await ort.createSession('$modelsDir/face_recognition_sface.onnx',
          options: modelloptionen());
    }
    return FaceEngineService._(detector, recognizer);
  }

  bool get canEmbed => _recognizer != null;

  /// Erkennt Gesichter in einem bereits dekodierten Bild. Das Bild wird
  /// dafür (ohne Seitenverhältnis beizubehalten) auf 640x640 skaliert –
  /// normalisierte Koordinaten bleiben dadurch unabhängig von der
  /// Original-Auflösung korrekt.
  ///
  /// Nimmt bewusst ein bereits dekodiertes [img.Image] statt einer [File]
  /// entgegen: Aufrufer wie [LibraryState] brauchen dasselbe dekodierte Bild
  /// zusätzlich für Gesichts-Crops und die CLIP-Einbettung – das (teure)
  /// Dekodieren einer großen JPEG/HEIC-Vorschau mehrfach zu wiederholen wäre
  /// verschwendete Rechenzeit.
  Future<List<DetectedFace>> detectFaces(img.Image decoded, {double scoreThreshold = 0.7}) async {
    final resized = img.copyResize(decoded, width: _yunetInputSize, height: _yunetInputSize);

    // YuNet (Teil der OpenCV-DNN-Familie) erwartet BGR-Kanalreihenfolge, kein RGB.
    final chw = Float32List(3 * _yunetInputSize * _yunetInputSize);
    var idx = 0;
    for (var c = 0; c < 3; c++) {
      for (var y = 0; y < _yunetInputSize; y++) {
        for (var x = 0; x < _yunetInputSize; x++) {
          final pixel = resized.getPixel(x, y);
          final value = c == 0 ? pixel.b : (c == 1 ? pixel.g : pixel.r);
          chw[idx++] = value.toDouble();
        }
      }
    }

    final inputTensor = await OrtValue.fromList(chw, [1, 3, _yunetInputSize, _yunetInputSize]);
    // Freigeben gehört ins finally, nicht dahinter: Wirft run() oder das
    // Auspacken der Ausgabezweige, bliebe der Eingabetensor als nativer
    // Speicher liegen, den der Dart-Sammler nie zurückholt. Dieser Pfad
    // läuft beim Import über jedes Foto (Prüfrunde 12).
    Map<String, OrtValue>? outputs;
    try {
      outputs = await _detector.run({_detector.inputNames.first: inputTensor});

      final candidates = <DetectedFace>[];
      for (final stride in _yunetStrides) {
        final gridSize = _yunetInputSize ~/ stride;
        final cls = await _asDoubleList(outputs['cls_$stride']);
        final obj = await _asDoubleList(outputs['obj_$stride']);
        final bbox = await _asDoubleList(outputs['bbox_$stride']);
        // Landmarks sind optional: manche YuNet-Exporte liefern diesen
        // Ausgabezweig nicht. Ohne ihn wird weiterhin erkannt, nur ohne die
        // Möglichkeit zur Ausrichtung vor dem SFace-Embedding (siehe
        // [alignFace]).
        final kps = await _asDoubleList(outputs['kps_$stride']);
        if (cls == null || obj == null || bbox == null) continue;

        for (var r = 0; r < gridSize; r++) {
          for (var c = 0; c < gridSize; c++) {
            final cellIdx = r * gridSize + c;
            if (cellIdx >= cls.length || cellIdx >= obj.length) continue;
            final score = FacePostprocess.combinedScore(cls[cellIdx], obj[cellIdx]);
            if (score < scoreThreshold) continue;

            final bboxOffset = cellIdx * 4;
            if (bboxOffset + 3 >= bbox.length) continue;

            List<double>? landmarks;
            if (kps != null) {
              final kpsOffset = cellIdx * 10;
              if (kpsOffset + 9 < kps.length) {
                landmarks = FacePostprocess.decodeLandmarks(
                  row: r,
                  col: c,
                  stride: stride,
                  kps: kps.sublist(kpsOffset, kpsOffset + 10),
                  inputSize: _yunetInputSize,
                );
              }
            }

            candidates.add(FacePostprocess.decodeBox(
              row: r,
              col: c,
              stride: stride,
              dx: bbox[bboxOffset],
              dy: bbox[bboxOffset + 1],
              dw: bbox[bboxOffset + 2],
              dh: bbox[bboxOffset + 3],
              inputSize: _yunetInputSize,
              score: score,
              landmarks: landmarks,
            ));
          }
        }
      }

      return FacePostprocess.nonMaxSuppression(candidates, iouThreshold: 0.3);
    } finally {
      await inputTensor.dispose();
      for (final v in outputs?.values ?? const <OrtValue>[]) {
        await v.dispose();
      }
    }
  }

  /// Berechnet ein Embedding für ein erkanntes Gesicht: richtet es, falls
  /// [box] Landmarks enthält, per Ähnlichkeitstransformation aus ([alignFace]
  /// – das SFace-Referenzverfahren), sonst greift als Fallback ein einfacher
  /// Bounding-Box-Crop ([cropFaceImage], z.B. bei manuell eingezeichneten
  /// Gesichtern ohne Landmarks).
  Future<Float32List?> embedFace(img.Image decoded, DetectedFace box) async {
    if (_recognizer == null) return null;
    final prepared = alignFace(decoded, box) ?? cropFaceImage(decoded, box);
    return _embedPreparedFace(prepared);
  }

  /// Führt die eigentliche SFace-Inferenz auf einem bereits vorbereiteten
  /// (idealerweise ausgerichteten) quadratischen Gesichtsbild aus. Nutzt rohe
  /// 0..255-Pixelwerte ohne Mittelwert-/Skalen-Normalisierung – exakt wie
  /// OpenCVs eigene Referenzimplementierung (`FaceRecognizerSF::feature`) das
  /// SFace-Modell füttert.
  Future<Float32List?> _embedPreparedFace(img.Image prepared) async {
    final recognizer = _recognizer;
    if (recognizer == null) return null;
    final resized = img.copyResize(prepared, width: _sfaceInputSize, height: _sfaceInputSize);

    final chw = Float32List(3 * _sfaceInputSize * _sfaceInputSize);
    var idx = 0;
    for (var c = 0; c < 3; c++) {
      for (var y = 0; y < _sfaceInputSize; y++) {
        for (var x = 0; x < _sfaceInputSize; x++) {
          final pixel = resized.getPixel(x, y);
          final value = c == 0 ? pixel.b : (c == 1 ? pixel.g : pixel.r);
          chw[idx++] = value.toDouble();
        }
      }
    }

    final inputTensor = await OrtValue.fromList(chw, [1, 3, _sfaceInputSize, _sfaceInputSize]);
    Map<String, OrtValue>? outputs;
    try {
      outputs = await recognizer.run({recognizer.inputNames.first: inputTensor});
      final raw = await _asDoubleList(outputs.values.first);
      if (raw == null) return null;
      return _l2Normalize(Float32List.fromList(raw));
    } finally {
      await inputTensor.dispose();
      for (final v in outputs?.values ?? const <OrtValue>[]) {
        await v.dispose();
      }
    }
  }

  /// Referenz-Landmarks (rechtes Auge, linkes Auge, Nasenspitze, rechter und
  /// linker Mundwinkel) im 112x112-SFace-Eingaberaum – identisch zu OpenCVs
  /// `FaceRecognizerSF::alignCrop`-Referenzpunkten (bzw. dem gleichen
  /// ArcFace-Standard-Template).
  static const List<double> _sfaceTemplate = [
    38.2946, 51.6963,
    73.5318, 51.5014,
    56.0252, 71.7366,
    41.5493, 92.3655,
    70.7299, 92.2041,
  ];

  /// Richtet ein erkanntes Gesicht anhand seiner 5 Landmarks per
  /// Ähnlichkeitstransformation (Rotation + gleichmäßige Skalierung +
  /// Verschiebung, ohne Spiegelung) auf das SFace-Referenz-Layout aus und
  /// gibt ein 112x112-Bild zurück. Gibt `null` zurück, wenn [box] keine
  /// Landmarks hat (z.B. manuell eingezeichnete Gesichter) – Aufrufer sollen
  /// dann auf [cropFaceImage] zurückfallen.
  static img.Image? alignFace(img.Image decoded, DetectedFace box) {
    final lm = box.landmarks;
    if (lm == null) return null;

    final src = List<double>.filled(10, 0.0);
    for (var i = 0; i < 5; i++) {
      src[i * 2] = lm[i * 2] * decoded.width;
      src[i * 2 + 1] = lm[i * 2 + 1] * decoded.height;
    }

    final transform = _SimilarityTransform.fit(src, _sfaceTemplate);
    final aligned = img.Image(width: _sfaceInputSize, height: _sfaceInputSize);
    for (var v = 0; v < _sfaceInputSize; v++) {
      for (var u = 0; u < _sfaceInputSize; u++) {
        final (srcX, srcY) = transform.mapInverse(u.toDouble(), v.toDouble());
        final (r, g, b) = _bilinearSample(decoded, srcX, srcY);
        aligned.setPixelRgb(u, v, r, g, b);
      }
    }
    return aligned;
  }

  /// Bilineare Interpolation an einer (nicht notwendigerweise ganzzahligen)
  /// Bildposition – wird beim Ausrichten gebraucht, da die Ähnlichkeits-
  /// transformation i.A. auf Zwischenpixel-Koordinaten im Quellbild abbildet.
  /// Koordinaten außerhalb des Bildes werden geklemmt (Rand wird wiederholt)
  /// statt schwarze Ränder zu erzeugen.
  static (double, double, double) _bilinearSample(img.Image src, double x, double y) {
    final maxX = src.width - 1, maxY = src.height - 1;
    final cx = x.clamp(0.0, maxX.toDouble());
    final cy = y.clamp(0.0, maxY.toDouble());
    final x0 = cx.floor(), y0 = cy.floor();
    final x1 = math.min(x0 + 1, maxX), y1 = math.min(y0 + 1, maxY);
    final fx = cx - x0, fy = cy - y0;

    final p00 = src.getPixel(x0, y0);
    final p10 = src.getPixel(x1, y0);
    final p01 = src.getPixel(x0, y1);
    final p11 = src.getPixel(x1, y1);

    double lerp2(double a, double b, double c, double d) {
      final top = a + (b - a) * fx;
      final bottom = c + (d - c) * fx;
      return top + (bottom - top) * fy;
    }

    return (
      lerp2(p00.r.toDouble(), p10.r.toDouble(), p01.r.toDouble(), p11.r.toDouble()),
      lerp2(p00.g.toDouble(), p10.g.toDouble(), p01.g.toDouble(), p11.g.toDouble()),
      lerp2(p00.b.toDouble(), p10.b.toDouble(), p01.b.toDouble(), p11.b.toDouble()),
    );
  }

  static double cosineSimilarity(Float32List a, Float32List b) {
    var dot = 0.0;
    final len = math.min(a.length, b.length);
    for (var i = 0; i < len; i++) {
      dot += a[i] * b[i];
    }
    return dot; // beide Vektoren sind bereits L2-normalisiert
  }

  Float32List _l2Normalize(Float32List vector) {
    var sumSq = 0.0;
    for (final v in vector) {
      sumSq += v * v;
    }
    final norm = math.sqrt(sumSq);
    if (norm == 0) return vector;
    final result = Float32List(vector.length);
    for (var i = 0; i < vector.length; i++) {
      result[i] = vector[i] / norm;
    }
    return result;
  }

  Future<List<double>?> _asDoubleList(OrtValue? value) async {
    if (value == null) return null;
    final raw = await value.asFlattenedList();
    return raw.map((e) => (e as num).toDouble()).toList();
  }

  /// Schneidet ein erkanntes Gesicht (mit etwas Rand) aus dem bereits
  /// dekodierten Originalbild aus und skaliert es auf 160x160 – als reine
  /// Bildoperation ohne Datei-I/O, damit das Ergebnis sowohl zum Speichern
  /// ([saveFaceCrop], für die "Unbenannte Gesichter"-Übersicht) als auch
  /// direkt als Fallback-Eingabe für [embedFace] wiederverwendet werden kann
  /// (wenn keine Landmarks vorliegen), ohne die Crop-Datei danach erneut von
  /// der Platte einzulesen.
  static img.Image cropFaceImage(img.Image decoded, DetectedFace box) {
    const pad = 0.15;
    final x = ((box.x - box.width * pad) * decoded.width).clamp(0, decoded.width - 1).toInt();
    final y = ((box.y - box.height * pad) * decoded.height).clamp(0, decoded.height - 1).toInt();
    final w = ((box.width * (1 + 2 * pad)) * decoded.width).clamp(1, decoded.width - x).toInt();
    final h = ((box.height * (1 + 2 * pad)) * decoded.height).clamp(1, decoded.height - y).toInt();

    final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
    return img.copyResize(cropped, width: 160, height: 160);
  }

  static Future<File> saveFaceCrop(img.Image croppedThumb, File targetFile) async {
    await targetFile.create(recursive: true);
    await targetFile.writeAsBytes(img.encodeJpg(croppedThumb, quality: 85));
    return targetFile;
  }

  Future<void> dispose() async {
    await _detector.close();
    await _recognizer?.close();
  }
}

/// 2D-Ähnlichkeitstransformation (gleichmäßige Skalierung + Rotation +
/// Verschiebung, keine Spiegelung), im kleinsten-Quadrate-Sinn an zwei
/// Punktmengen angepasst – die geschlossene Lösung über komplexe Zahlen
/// entspricht dem Spezialfall von Umeyamas Verfahren für 2 Dimensionen ohne
/// Spiegelungskorrektur (für Gesichts-Landmarks nie nötig).
///
/// Intern als `z_dst = m * z_src + t` mit komplexem `m = a + bi`
/// (Skalierung+Rotation) und `t = tx + tyi` (Verschiebung) dargestellt.
class _SimilarityTransform {
  final double a, b, tx, ty;
  const _SimilarityTransform(this.a, this.b, this.tx, this.ty);

  /// Passt die Transformation an, die [src] (flache Liste von x/y-Paaren)
  /// im kleinste-Quadrate-Sinn auf [dst] abbildet.
  static _SimilarityTransform fit(List<double> src, List<double> dst) {
    final n = src.length ~/ 2;
    var sx = 0.0, sy = 0.0, dx = 0.0, dy = 0.0;
    for (var i = 0; i < n; i++) {
      sx += src[i * 2];
      sy += src[i * 2 + 1];
      dx += dst[i * 2];
      dy += dst[i * 2 + 1];
    }
    sx /= n;
    sy /= n;
    dx /= n;
    dy /= n;

    var num1 = 0.0, num2 = 0.0, den = 0.0;
    for (var i = 0; i < n; i++) {
      final cxs = src[i * 2] - sx, cys = src[i * 2 + 1] - sy;
      final cxd = dst[i * 2] - dx, cyd = dst[i * 2 + 1] - dy;
      num1 += cxs * cxd + cys * cyd;
      num2 += cxs * cyd - cys * cxd;
      den += cxs * cxs + cys * cys;
    }
    if (den == 0) return const _SimilarityTransform(1, 0, 0, 0);
    final a = num1 / den;
    final b = num2 / den;
    final tx = dx - (a * sx - b * sy);
    final ty = dy - (b * sx + a * sy);
    return _SimilarityTransform(a, b, tx, ty);
  }

  /// Bildet einen Punkt im Ziel-Koordinatensystem (z.B. ein Pixel im
  /// 112x112-Ausgabebild) zurück auf die entsprechende Position im
  /// Quellbild ab – gebraucht, um pro Ausgabepixel aus dem Originalbild zu
  /// sampeln (inverse Abbildung von `z_dst = m*z_src + t`).
  (double, double) mapInverse(double dstX, double dstY) {
    final denom = a * a + b * b;
    if (denom == 0) return (dstX, dstY);
    final px = dstX - tx, py = dstY - ty;
    final srcX = (px * a + py * b) / denom;
    final srcY = (py * a - px * b) / denom;
    return (srcX, srcY);
  }
}
