import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

import 'face_postprocess.dart';
import 'modellthreads.dart';

const int _eyeStateInputWidth = 40;
const int _eyeStateInputHeight = 24;

/// Ganzzahliges Ausschnitts-Rechteck innerhalb eines Bildes, bereits an die
/// Bildgrenzen geklemmt.
class EyeCropRect {
  final int x;
  final int y;
  final int width;
  final int height;
  const EyeCropRect({required this.x, required this.y, required this.width, required this.height});
}

/// Berechnet die beiden Augen-Ausschnitte (rechtes, linkes Auge – in dieser
/// Reihenfolge) aus den normalisierten YuNet-Landmarks. Reine Geometrie ohne
/// Bild-/Modell-Zugriff, daher ohne ONNX-Laufzeit testbar. Gibt `null`
/// zurück, wenn [landmarks] fehlt (weniger als 4 Werte) oder ein berechneter
/// Ausschnitt zu klein würde (z.B. bei extrem kleinen Bildern).
(EyeCropRect?, EyeCropRect?)? eyeCropRects(int imageWidth, int imageHeight, List<double>? landmarks) {
  if (landmarks == null || landmarks.length < 4) return null;

  final rightEyeX = landmarks[0] * imageWidth;
  final rightEyeY = landmarks[1] * imageHeight;
  final leftEyeX = landmarks[2] * imageWidth;
  final leftEyeY = landmarks[3] * imageHeight;

  final interocular = math.sqrt(
    math.pow(rightEyeX - leftEyeX, 2) + math.pow(rightEyeY - leftEyeY, 2),
  );
  final windowWidth = math.max(interocular * 0.6, 12.0);
  final windowHeight = windowWidth * _eyeStateInputHeight / _eyeStateInputWidth;

  EyeCropRect? rectAt(double cx, double cy) {
    final x = (cx - windowWidth / 2).round().clamp(0, imageWidth - 1);
    final y = (cy - windowHeight / 2).round().clamp(0, imageHeight - 1);
    final width = windowWidth.round().clamp(1, imageWidth - x);
    final height = windowHeight.round().clamp(1, imageHeight - y);
    if (width < 2 || height < 2) return null;
    return EyeCropRect(x: x, y: y, width: width, height: height);
  }

  return (rectAt(rightEyeX, rightEyeY), rectAt(leftEyeX, leftEyeY));
}

/// Kapselt Geschlossene-Augen-Erkennung über ein kleines ONNX-Modell (OCEC,
/// siehe model_catalog.dart) – ergänzt YuNets bereits vorhandene 5-Punkt-
/// Landmarks (siehe FacePostprocess/FaceEngineService.detectFaces) um eine
/// tatsächliche Augen-offen/geschlossen-Klassifikation. Die Augen-
/// Mittelpunkte allein reichen dafür nicht aus: YuNet liefert keine
/// Lidwinkel-Punkte, mit denen sich eine geometrische Eye-Aspect-Ratio-
/// Heuristik berechnen ließe – daher ein separater, winziger Klassifikator
/// auf kleinen Augen-Ausschnitten.
///
/// Vorverarbeitung real gegen das Original-Repository (PINTO0309/OCEC,
/// `demo_ocec.py`) verifiziert: Zielgröße 40x24 (Breite x Höhe), Werte auf
/// 0..1 skaliert (KEIN ImageNet-Mittel/Std wie bei CLIP/SAM), BGR-
/// Kanalreihenfolge (wie bei YuNet/SFace – dieselbe OpenCV-nahe
/// Modellfamilie, siehe FaceEngineService.detectFaces).
class EyeStateService {
  EyeStateService._(this._session);

  final OrtSession _session;

  static bool isAvailable(String modelsDir) => File('$modelsDir/eye_state_ocec_n.onnx').existsSync();

  static Future<EyeStateService?> load(String modelsDir) async {
    if (!isAvailable(modelsDir)) return null;
    final ort = OnnxRuntime();
    final session = await ort.createSession('$modelsDir/eye_state_ocec_n.onnx',
        options: modelloptionen());
    return EyeStateService._(session);
  }

  /// Wahrscheinlichkeit "Augen offen" (0..1) für [face] in [decoded] – das
  /// Minimum beider Augen-Scores (konservativ: ein einzelnes geschlossenes
  /// Auge reicht bereits, um das Gesicht als "Augen zu" zu werten). `null`,
  /// falls [face] keine Landmarks hat (z.B. manuell eingezeichnete
  /// Gesichter ohne Detektions-Landmarks).
  Future<double?> eyeOpenScore(img.Image decoded, DetectedFace face) async {
    final rects = eyeCropRects(decoded.width, decoded.height, face.landmarks);
    if (rects == null) return null;
    final (rightRect, leftRect) = rects;

    final rightScore = rightRect == null ? null : await _scoreEyeCrop(decoded, rightRect);
    final leftScore = leftRect == null ? null : await _scoreEyeCrop(decoded, leftRect);
    if (rightScore == null && leftScore == null) return null;
    if (rightScore == null) return leftScore;
    if (leftScore == null) return rightScore;
    return math.min(rightScore, leftScore);
  }

  Future<double?> _scoreEyeCrop(img.Image decoded, EyeCropRect rect) async {
    final cropped = img.copyCrop(decoded, x: rect.x, y: rect.y, width: rect.width, height: rect.height);
    final resized = img.copyResize(cropped, width: _eyeStateInputWidth, height: _eyeStateInputHeight);

    final chw = Float32List(3 * _eyeStateInputHeight * _eyeStateInputWidth);
    var idx = 0;
    for (var c = 0; c < 3; c++) {
      for (var yy = 0; yy < _eyeStateInputHeight; yy++) {
        for (var xx = 0; xx < _eyeStateInputWidth; xx++) {
          final pixel = resized.getPixel(xx, yy);
          final value = c == 0 ? pixel.b : (c == 1 ? pixel.g : pixel.r);
          // Auf -1..1, nicht auf 0..1. Mit `value / 255` meldete das Modell
          // für Gesichter mit offenen Augen Werte um 0,00 – nachgesehen an
          // den gespeicherten Ausschnitten: fünf Gesichter mit dem Wert
          // 0,00 hatten alle die Augen offen, ein schlafendes Kind stand
          // bei 0,98. An denselben Ausschnitten mit dieser Normierung
          // gegengerechnet kippen genau die sichtbar offenen Augen auf
          // Werte über 0,9.
          chw[idx++] = (value / 255.0 - 0.5) / 0.5;
        }
      }
    }

    final inputTensor = await OrtValue.fromList(chw, [1, 3, _eyeStateInputHeight, _eyeStateInputWidth]);
    Map<String, OrtValue>? outputs;
    try {
      outputs = await _session.run({_session.inputNames.first: inputTensor});
      final outputTensor = outputs[_session.outputNames.first]!;
      final raw = await outputTensor.asFlattenedList();
      if (raw.isEmpty) return null;
      return (raw.first as num).toDouble().clamp(0.0, 1.0);
    } finally {
      await inputTensor.dispose();
      for (final v in outputs?.values ?? const <OrtValue>[]) {
        await v.dispose();
      }
    }
  }

  Future<void> dispose() async {
    await _session.close();
  }
}
