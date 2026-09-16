import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'modellthreads.dart';

/// SAMs Standard-Vorverarbeitung (ImageNet-Mittel/Standardabweichung,
/// längste Kante auf 1024px, danach quadratisch aufgefüllt) – exakt gegen
/// `preprocessor_config.json` des gebündelten Xenova/sam-vit-base-Exports
/// verifiziert, siehe model_catalog.dart.
const _samMean = [0.485, 0.456, 0.406];
const _samStd = [0.229, 0.224, 0.225];
const _samInputSize = 1024;
const _samMaskSize = 256;

/// Bild-Embedding eines Fotos (Ausgabe von [SegmentationService.encodeImage])
/// – wird nur im Speicher der offenen Maskier-Sitzung gehalten, NICHT in der
/// Datenbank persistiert (siehe DevelopMasks: gespeichert wird nur das
/// fertige Masken-Ergebnis als PNG, nicht die Zwischenwerte).
class SamImageEmbedding {
  final Float32List embeddings;
  final Float32List positionalEmbeddings;

  /// Skalierungsfaktor Original- → Encoder-Koordinatenraum (siehe
  /// [SegmentationService._preprocess]) – wird gebraucht, um vom Nutzer im
  /// Originalbild angetippte Punkte in Encoder-Koordinaten umzurechnen.
  final double scale;
  final int originalWidth;
  final int originalHeight;

  const SamImageEmbedding({
    required this.embeddings,
    required this.positionalEmbeddings,
    required this.scale,
    required this.originalWidth,
    required this.originalHeight,
  });
}

/// Ergebnis eines einzelnen Masken-Decoder-Aufrufs (siehe
/// [SegmentationService.decodeMask]) – die rohen 256x256-Logits der
/// besten (höchster IoU-Wert) der 3 Kandidatenmasken, noch NICHT auf die
/// Original-Bildauflösung hochskaliert (siehe [maskToOriginalResolution]).
class SamMaskResult {
  final Float32List logits;
  final double iouScore;
  final SamImageEmbedding sourceEmbedding;

  const SamMaskResult({required this.logits, required this.iouScore, required this.sourceEmbedding});
}

/// Kapselt On-Device-Inferenz mit einem SAM-Modell (Bild-Encoder + Prompt-/
/// Masken-Decoder als zwei separate ONNX-Dateien) für KI-Objektmasken im
/// Entwickeln-Screen (siehe DevelopMasks, MaskEditor). Dasselbe
/// Zwei-Sitzungen-Muster wie [ClipService] – anders als bei einem
/// generativen Bildbeschreibungs-Modell ist auch der "promptbare"
/// Masken-Decoder nur EIN Forward-Pass pro Klick, kein Mehrschritt-Loop.
///
/// Ein-/Ausgabenamen sind fest gegen die tatsächlichen ONNX-Dateien
/// verifiziert (siehe model_catalog.dart), nicht geraten.
class SegmentationService {
  SegmentationService._(this._visionSession, this._decoderSession);

  final OrtSession _visionSession;
  final OrtSession _decoderSession;

  static bool _filesPresent(String modelsDir) {
    for (final name in ['sam_vision_encoder.onnx', 'sam_prompt_mask_decoder.onnx']) {
      if (!File('$modelsDir/$name').existsSync()) return false;
    }
    return true;
  }

  static bool isAvailable(String modelsDir) => _filesPresent(modelsDir);

  static Future<SegmentationService> load(String modelsDir) async {
    final ort = OnnxRuntime();
    final visionSession = await ort.createSession('$modelsDir/sam_vision_encoder.onnx',
        options: modelloptionen());
    final decoderSession = await ort.createSession('$modelsDir/sam_prompt_mask_decoder.onnx',
        options: modelloptionen());
    return SegmentationService._(visionSession, decoderSession);
  }

  /// Skaliert [decoded] auf die längste Kante [_samInputSize] und komponiert
  /// es in die obere linke Ecke einer [_samInputSize]x[_samInputSize]
  /// großen, ansonsten schwarzen Leinwand (SAMs Standard-"Pad rechts/unten").
  ({img.Image padded, double scale}) _preprocess(img.Image decoded) {
    final longSide = math.max(decoded.width, decoded.height);
    final scale = _samInputSize / longSide;
    final resized = img.copyResize(
      decoded,
      width: (decoded.width * scale).round(),
      height: (decoded.height * scale).round(),
    );
    final padded = img.Image(width: _samInputSize, height: _samInputSize);
    img.compositeImage(padded, resized);
    return (padded: padded, scale: scale);
  }

  /// Berechnet das (teure) Bild-Embedding einmalig beim Öffnen des
  /// Maskier-Modus – wird für JEDEN nachfolgenden Klick in [decodeMask]
  /// wiederverwendet, statt bei jedem Punkt neu berechnet zu werden.
  ///
  /// try/finally stellt sicher, dass der ~12,6 MB große Eingabe-Tensor und
  /// die Ausgabe-Tensoren auch dann disposed werden, wenn `run()`/
  /// `asFlattenedList()` mittendrin wirft (Audit-Fund – vorher kein
  /// try/finally, natives Tensor-Handle hätte für immer geleakt).
  Future<SamImageEmbedding> encodeImage(img.Image decoded) async {
    final prep = _preprocess(decoded);
    final chw = Float32List(3 * _samInputSize * _samInputSize);
    var idx = 0;
    for (var c = 0; c < 3; c++) {
      for (var y = 0; y < _samInputSize; y++) {
        for (var x = 0; x < _samInputSize; x++) {
          final pixel = prep.padded.getPixel(x, y);
          final value = c == 0 ? pixel.r : (c == 1 ? pixel.g : pixel.b);
          chw[idx++] = (value / 255.0 - _samMean[c]) / _samStd[c];
        }
      }
    }

    final inputTensor = await OrtValue.fromList(chw, [1, 3, _samInputSize, _samInputSize]);
    final liveTensors = <OrtValue>{inputTensor};
    try {
      final outputs = await _visionSession.run({'pixel_values': inputTensor});
      liveTensors.addAll(outputs.values);
      final embeddingsRaw = await outputs['image_embeddings']!.asFlattenedList();
      final positionalRaw = await outputs['image_positional_embeddings']!.asFlattenedList();

      return SamImageEmbedding(
        embeddings: Float32List.fromList(embeddingsRaw.map((e) => (e as num).toDouble()).toList()),
        positionalEmbeddings: Float32List.fromList(positionalRaw.map((e) => (e as num).toDouble()).toList()),
        scale: prep.scale,
        originalWidth: decoded.width,
        originalHeight: decoded.height,
      );
    } finally {
      for (final v in liveTensors) {
        try {
          await v.dispose();
        } catch (_) {
          // Bereits disposed – bestmöglich.
        }
      }
    }
  }

  /// Sagt eine Maske für die gegebenen Vordergrund-/Hintergrund-Punkte
  /// voraus (Koordinaten im ORIGINAL-Bild, siehe [SamImageEmbedding.scale]
  /// zur Umrechnung) – EIN einzelner Forward-Pass, kein Loop. Der Decoder
  /// liefert 3 Kandidatenmasken samt IoU-Schätzung; die mit dem höchsten
  /// Wert wird zurückgegeben.
  Future<SamMaskResult> decodeMask(
    SamImageEmbedding embedding, {
    required List<Offset> foregroundPoints,
    List<Offset> backgroundPoints = const [],
  }) async {
    final points = [...foregroundPoints, ...backgroundPoints];
    if (points.isEmpty) {
      throw ArgumentError('decodeMask benötigt mindestens einen Punkt.');
    }

    final pointsFlat = Float32List(points.length * 2);
    final labelsFlat = Int64List(points.length);
    for (var i = 0; i < points.length; i++) {
      pointsFlat[i * 2] = points[i].dx * embedding.scale;
      pointsFlat[i * 2 + 1] = points[i].dy * embedding.scale;
      // SAM-Konvention: 1 = Vordergrund-Punkt, 0 = Hintergrund-Punkt.
      labelsFlat[i] = i < foregroundPoints.length ? 1 : 0;
    }

    final pointsTensor = await OrtValue.fromList(pointsFlat, [1, 1, points.length, 2]);
    final labelsTensor = await OrtValue.fromList(labelsFlat, [1, 1, points.length]);
    final embeddingsTensor = await OrtValue.fromList(embedding.embeddings, [1, 256, 64, 64]);
    final positionalTensor = await OrtValue.fromList(embedding.positionalEmbeddings, [1, 256, 64, 64]);
    // try/finally analog zu encodeImage: sichert die bis zu ~8 MB an
    // Tensoren auch bei einem Fehler mitten im Aufruf ab (Audit-Fund) –
    // relevant, da decodeMask bei jedem Punkt-Tap im Masken-Editor läuft.
    final liveTensors = <OrtValue>{pointsTensor, labelsTensor, embeddingsTensor, positionalTensor};

    try {
      final outputs = await _decoderSession.run({
        'input_points': pointsTensor,
        'input_labels': labelsTensor,
        'image_embeddings': embeddingsTensor,
        'image_positional_embeddings': positionalTensor,
      });
      liveTensors.addAll(outputs.values);

      final iouRaw = await outputs['iou_scores']!.asFlattenedList();
      final masksRaw = await outputs['pred_masks']!.asFlattenedList();

      final iouScores = iouRaw.map((e) => (e as num).toDouble()).toList();
      var bestIndex = 0;
      for (var i = 1; i < iouScores.length; i++) {
        if (iouScores[i] > iouScores[bestIndex]) bestIndex = i;
      }

      final maskLogits = Float32List(_samMaskSize * _samMaskSize);
      final offset = bestIndex * _samMaskSize * _samMaskSize;
      for (var i = 0; i < maskLogits.length; i++) {
        maskLogits[i] = (masksRaw[offset + i] as num).toDouble();
      }

      return SamMaskResult(logits: maskLogits, iouScore: iouScores[bestIndex], sourceEmbedding: embedding);
    } finally {
      for (final v in liveTensors) {
        try {
          await v.dispose();
        } catch (_) {
          // Bereits disposed – bestmöglich.
        }
      }
    }
  }

  Future<void> dispose() async {
    await _visionSession.close();
    await _decoderSession.close();
  }
}

/// Wandelt die rohen 256x256-Masken-Logits eines [SamMaskResult] in ein
/// Graustufenbild in der ORIGINAL-Bildauflösung um (weiß = ausgewählt,
/// schwarz = nicht ausgewählt) – geeignet sowohl für die Dart-seitige
/// Live-Vorschau (halbtransparentes Overlay) als auch zum Speichern als
/// PNG-Alphamaske (siehe DevelopMasks.maskRelativePath). Reine, von der
/// ONNX-Sitzung unabhängige Funktion.
img.Image maskToOriginalResolution(SamMaskResult result) {
  final embedding = result.sourceEmbedding;

  // Logits (>0 = ausgewählt, entspricht sigmoid > 0.5) zunächst 1:1 in ein
  // 256x256-Graustufenbild übertragen.
  final small = img.Image(width: _samMaskSize, height: _samMaskSize);
  for (var y = 0; y < _samMaskSize; y++) {
    for (var x = 0; x < _samMaskSize; x++) {
      final selected = result.logits[y * _samMaskSize + x] > 0;
      final v = selected ? 255 : 0;
      small.setPixelRgb(x, y, v, v, v);
    }
  }

  // Zurück auf die 1024er-Encoder-Leinwand hochskalieren (nearest-neighbor,
  // da es eine binäre Maske ist, keine Farbwerte – Interpolation würde
  // unerwünschte Graustufen am Rand erzeugen), dann auf den tatsächlich
  // genutzten (nicht aufgefüllten) Bereich zuschneiden und auf die
  // Original-Bildauflösung skalieren.
  final upscaledToPadded = img.copyResize(
    small,
    width: _samInputSize,
    height: _samInputSize,
    interpolation: img.Interpolation.nearest,
  );
  final resizedWidth = (embedding.originalWidth * embedding.scale).round();
  final resizedHeight = (embedding.originalHeight * embedding.scale).round();
  final cropped = img.copyCrop(upscaledToPadded, x: 0, y: 0, width: resizedWidth, height: resizedHeight);
  return img.copyResize(
    cropped,
    width: embedding.originalWidth,
    height: embedding.originalHeight,
    interpolation: img.Interpolation.nearest,
  );
}

/// Wandelt eine schwarz/weiße Maske (siehe [maskToOriginalResolution]) in
/// ein eingefärbtes, halbtransparentes Overlay um – für die Dart-seitige
/// Live-Vorschau während des Maskierens (MaskEditor), NICHT für die
/// gespeicherte Maskendatei selbst (die bleibt eine reine Graustufen-PNG,
/// siehe DevelopMasks.maskRelativePath). Ausgewählte (weiße) Pixel werden
/// zu [color] mit Deckkraft [alpha], nicht ausgewählte bleiben komplett
/// transparent.
img.Image maskToPreviewOverlay(img.Image grayscaleMask, {required int r, required int g, required int b, int alpha = 140}) {
  final overlay = img.Image(width: grayscaleMask.width, height: grayscaleMask.height, numChannels: 4);
  for (var y = 0; y < grayscaleMask.height; y++) {
    for (var x = 0; x < grayscaleMask.width; x++) {
      final selected = grayscaleMask.getPixel(x, y).r > 127;
      overlay.setPixelRgba(x, y, r, g, b, selected ? alpha : 0);
    }
  }
  return overlay;
}

/// Reine, isolate-taugliche Funktion (kein Zugriff auf Widgets/Plugins,
/// analog zu [computeBlurScore]/`decodeImageBytes`): baut aus einem
/// [SamMaskResult] das eingefärbte Vorschau-Overlay UND kodiert es direkt
/// zu PNG-Bytes, damit der komplette, bei jedem Punkt-Tap im MaskEditor
/// anfallende Nachbearbeitungs-Aufwand (Hochskalieren auf Originalgröße,
/// Overlay-Einfärbung, PNG/zlib-Kompression – bei großen Fotos spürbar) via
/// `compute()` vom Haupt-Isolate weg verlagert werden kann, statt bei jedem
/// Tap kurz die UI einfrieren zu lassen.
Uint8List renderMaskPreviewPng(SamMaskResult result) {
  final overlay = maskToPreviewOverlay(maskToOriginalResolution(result), r: 33, g: 150, b: 243);
  return Uint8List.fromList(img.encodePng(overlay));
}

/// Wie [renderMaskPreviewPng], aber für die tatsächlich gespeicherte
/// Graustufen-Alphamaske (kein Einfärben) – genutzt beim Bestätigen einer
/// Maske (`_commitMask`), ebenfalls über `compute()` auslagerbar.
Uint8List renderMaskPngBytes(SamMaskResult result) {
  return Uint8List.fromList(img.encodePng(maskToOriginalResolution(result)));
}
