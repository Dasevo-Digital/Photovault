import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/segmentation_service.dart';

/// Prüft [maskToOriginalResolution] – die reine, von der ONNX-Sitzung
/// unabhängige Nachbearbeitung der 256x256-Masken-Logits (Schwellenwert,
/// Zurückskalieren auf die Original-Bildauflösung). Die eigentliche
/// ONNX-Inferenz selbst braucht die native Plattform (siehe
/// SegmentationService.encodeImage/decodeMask) und wird stattdessen über
/// einen echten `flutter run -d macos`-Lauf verifiziert.
void main() {
  SamImageEmbedding embedding({required double scale, required int width, required int height}) => SamImageEmbedding(
        embeddings: Float32List(0),
        positionalEmbeddings: Float32List(0),
        scale: scale,
        originalWidth: width,
        originalHeight: height,
      );

  test('liefert ein Graustufenbild in der Original-Bildauflösung, nicht in 256x256', () {
    final logits = Float32List(256 * 256); // alles <= 0 -> nichts ausgewählt
    final result = SamMaskResult(
      logits: logits,
      iouScore: 0.9,
      sourceEmbedding: embedding(scale: 1024 / 2000, width: 2000, height: 1000),
    );

    final mask = maskToOriginalResolution(result);

    expect(mask.width, 2000);
    expect(mask.height, 1000);
  });

  test('schwellt Logits bei 0 (entspricht sigmoid > 0.5): positive Logits werden weiß, negative schwarz', () {
    const maskSize = 256;
    final logits = Float32List(maskSize * maskSize);
    // Obere Hälfte "ausgewählt" (positiver Logit), untere Hälfte nicht.
    for (var y = 0; y < maskSize; y++) {
      for (var x = 0; x < maskSize; x++) {
        logits[y * maskSize + x] = y < maskSize ~/ 2 ? 5.0 : -5.0;
      }
    }
    // Quadratisches 256x256-Originalbild, realistische Skalierung
    // (1024/längste Kante = 4.0) -> füllt die Encoder-Leinwand komplett aus,
    // kein Auffüllen nötig, daher bildet sich die Logit-Maske 1:1 (ohne
    // Zuschneide-Verzerrung) auf die Original-Auflösung zurück ab.
    final result = SamMaskResult(
      logits: logits,
      iouScore: 0.9,
      sourceEmbedding: embedding(scale: 4.0, width: 256, height: 256),
    );

    final mask = maskToOriginalResolution(result);

    expect(mask.getPixel(128, 10).r, 255); // obere Hälfte: ausgewählt
    expect(mask.getPixel(128, 245).r, 0); // untere Hälfte: nicht ausgewählt
  });

  test('schneidet den aufgefüllten Bereich weg statt ihn mit ins Bild zu übernehmen', () {
    // Ein sehr breites Originalbild (Encoder-Leinwand wird oben/unten
    // aufgefüllt) – alles im Logit-Raster als "ausgewählt" markiert; nach
    // dem Zuschneiden auf die tatsächlich genutzte Fläche darf am Rand des
    // Original-Seitenverhältnisses keine unerwartete Verzerrung entstehen.
    final logits = Float32List(256 * 256);
    for (var i = 0; i < logits.length; i++) {
      logits[i] = 1.0;
    }
    final result = SamMaskResult(
      logits: logits,
      iouScore: 0.9,
      sourceEmbedding: embedding(scale: 1024 / 4000, width: 4000, height: 1000),
    );

    final mask = maskToOriginalResolution(result);

    expect(mask.width, 4000);
    expect(mask.height, 1000);
    // Vollständig "ausgewählt" bleibt nach dem Zuschneiden/Skalieren erhalten.
    expect(mask.getPixel(2000, 500).r, 255);
  });
}
