import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

import 'tile_processor.dart';
import 'modellthreads.dart';

/// Kapselt On-Device-Inferenz mit Real-ESRGAN x4 (siehe model_catalog.dart:
/// `neuralRestore`) für KI-Restaurierung (Hochskalieren + Entrauschen in
/// einem Durchgang, siehe RestoreQueueService/RestoreJobs). Anders als bei
/// SAM/CLIP EIN einzelnes Modell mit dynamischer Eingabegröße `[1,3,h,w]`,
/// Ausgabe `[1,3,4h,4w]` – siehe [restore] für die Kachel-Verarbeitung
/// (das Modell selbst kennt keine ganzen Fotos, nur einzelne Kacheln).
///
/// Real per Python `onnxruntime`-Benchmark auf diesem Gerät gemessen: eine
/// 512×512-Kachel dauert ~20,1s auf der CPU, ~4,8s mit dem CoreML Execution
/// Provider (2 von 1024 Graph-Knoten sind nicht CoreML-fähig und fallen auf
/// CPU zurück) – [load] fordert CoreML deshalb explizit an, mit CPU als
/// Fallback, falls CoreML auf dem jeweiligen Gerät nicht verfügbar ist.
class RestoreService {
  RestoreService._(this._session);

  final OrtSession _session;

  static const tileSize = 512;
  static const overlap = 16;
  static const scaleFactor = 4;

  static bool isAvailable(String modelsDir) => File('$modelsDir/real_esrgan_x4.onnx').existsSync();

  static Future<RestoreService> load(String modelsDir) async {
    final ort = OnnxRuntime();
    final session = await ort.createSession(
      '$modelsDir/real_esrgan_x4.onnx',
      options: modelloptionen(providers: [OrtProvider.CORE_ML, OrtProvider.CPU]),
    );
    return RestoreService._(session);
  }

  /// Hochskaliert+entrauscht [source] um Faktor [scaleFactor] – läuft
  /// kachelweise (siehe [processInTiles]), typischerweise mehrere Minuten
  /// für ein reales Foto. [onProgress] meldet nach jeder Kachel
  /// `done`/`total` (für RestoreJobs.tilesDone/tilesTotal), [isCancelled]
  /// wird zwischen Kacheln geprüft.
  Future<img.Image> restore(
    img.Image source, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) {
    return processInTiles(
      source,
      tileSize: tileSize,
      overlap: overlap,
      scaleFactor: scaleFactor,
      infer: _inferTile,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }

  /// EIN Forward-Pass für eine einzelne Kachel. try/finally analog zu
  /// SegmentationService.encodeImage/decodeMask: stellt sicher, dass die
  /// (bei 512×512 rund 3 MB großen) Ein-/Ausgabe-Tensoren auch bei einem
  /// Fehler mitten im Aufruf disposed werden.
  Future<img.Image> _inferTile(img.Image tile) async {
    final width = tile.width;
    final height = tile.height;
    final chw = Float32List(3 * width * height);
    var idx = 0;
    for (var c = 0; c < 3; c++) {
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final pixel = tile.getPixel(x, y);
          final value = c == 0 ? pixel.r : (c == 1 ? pixel.g : pixel.b);
          chw[idx++] = value / 255.0;
        }
      }
    }

    final inputTensor = await OrtValue.fromList(chw, [1, 3, height, width]);
    final liveTensors = <OrtValue>{inputTensor};
    try {
      final outputs = await _session.run({'input': inputTensor});
      liveTensors.addAll(outputs.values);
      final outputRaw = await outputs['output']!.asFlattenedList();

      final outWidth = width * scaleFactor;
      final outHeight = height * scaleFactor;
      final channelSize = outWidth * outHeight;
      final result = img.Image(width: outWidth, height: outHeight);
      for (var y = 0; y < outHeight; y++) {
        final rowBase = y * outWidth;
        for (var x = 0; x < outWidth; x++) {
          final pixelIdx = rowBase + x;
          final r = ((outputRaw[pixelIdx] as num).toDouble() * 255).round().clamp(0, 255);
          final g = ((outputRaw[channelSize + pixelIdx] as num).toDouble() * 255).round().clamp(0, 255);
          final b = ((outputRaw[2 * channelSize + pixelIdx] as num).toDouble() * 255).round().clamp(0, 255);
          result.setPixelRgb(x, y, r, g, b);
        }
      }
      return result;
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
    await _session.close();
  }
}
