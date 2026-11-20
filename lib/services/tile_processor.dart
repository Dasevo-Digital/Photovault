import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Ein einzelner Bildausschnitt aus [splitIntoTiles], inklusive
/// Überlappungsrand. [x]/[y] sind die Koordinaten der linken oberen Ecke im
/// UNSKALIERTEN Quellbild – [processInTiles] nutzt sie, um das (bereits um
/// den Skalierungsfaktor vergrößerte) Inferenz-Ergebnis an der richtigen
/// Stelle im Ausgabebild zu platzieren.
class Tile {
  final int x;
  final int y;
  final img.Image image;
  const Tile({required this.x, required this.y, required this.image});
}

/// Start-Positionen für Kacheln entlang einer Achse: normaler Schritt
/// [stride], aber die letzte Kachel wird bündig an den Rand geschoben
/// (statt über den Rand hinauszuragen) – so bleibt jede Kachel intern
/// exakt [tileSize] groß (außer wenn [length] selbst kleiner ist), was die
/// spätere Kachel-Inferenz vereinfacht. Kann dazu führen, dass die letzte
/// Überlappung größer als [stride]s nominale Lücke ist – das ist für
/// [processInTiles]s gewichtete Überblendung unproblematisch (siehe dort).
List<int> _tileStarts(int length, int tileSize, int stride) {
  if (length <= tileSize) return [0];
  final starts = <int>[];
  var pos = 0;
  while (pos + tileSize < length) {
    starts.add(pos);
    pos += stride;
  }
  starts.add(length - tileSize);
  return starts;
}

/// Zerlegt [source] in überlappende Kacheln der Größe [tileSize] (Rand
/// [overlap] Pixel geteilt mit dem jeweiligen Nachbarn). Für ein reales
/// 12-48-MP-Foto mit 512px-Kacheln typischerweise mehrere Dutzend Kacheln.
List<Tile> splitIntoTiles(
  img.Image source, {
  required int tileSize,
  required int overlap,
}) {
  _pruefeKacheln(tileSize, overlap, 1);
  final stride = tileSize - overlap;
  final xs = _tileStarts(source.width, tileSize, stride);
  final ys = _tileStarts(source.height, tileSize, stride);
  final tiles = <Tile>[];
  for (final y in ys) {
    for (final x in xs) {
      final w = math.min(tileSize, source.width - x);
      final h = math.min(tileSize, source.height - y);
      tiles.add(
        Tile(
          x: x,
          y: y,
          image: img.copyCrop(source, x: x, y: y, width: w, height: h),
        ),
      );
    }
  }
  return tiles;
}

/// Gewichtsmaske für eine einzelne (bereits skalierte) Kachel: volles
/// Gewicht (1.0) im Kern, linearer Abfall zu 0 hin zu jeder Kante, die einen
/// Nachbarn hat (`touches* == false`) – Kanten, die den tatsächlichen
/// Bildrand berühren, behalten volles Gewicht (dort gibt es nichts zum
/// Überblenden). Die Kachel-Zusammensetzung normalisiert am Ende durch die
/// Gewichtssumme, daher müssen sich die Gewichte benachbarter Kacheln NICHT
/// exakt zu 1 aufsummieren (siehe processInTiles) – das macht die
/// Überblendung robust gegenüber der ungleichmäßigen letzten Überlappung
/// aus [_tileStarts].
Float32List _tileWeights({
  required int width,
  required int height,
  required int featherX,
  required int featherY,
  required bool touchesLeft,
  required bool touchesTop,
  required bool touchesRight,
  required bool touchesBottom,
}) {
  final fx = featherX.clamp(0, width ~/ 2);
  final fy = featherY.clamp(0, height ~/ 2);
  final weights = Float32List(width * height);
  for (var y = 0; y < height; y++) {
    var wy = 1.0;
    if (!touchesTop && fy > 0 && y < fy) wy = (y + 1) / fy;
    if (!touchesBottom && fy > 0 && y >= height - fy) {
      wy = math.min(wy, (height - y) / fy);
    }
    for (var x = 0; x < width; x++) {
      var wx = 1.0;
      if (!touchesLeft && fx > 0 && x < fx) wx = (x + 1) / fx;
      if (!touchesRight && fx > 0 && x >= width - fx) {
        wx = math.min(wx, (width - x) / fx);
      }
      weights[y * width + x] = wx * wy;
    }
  }
  return weights;
}

/// Geplanter Speicher für Quelle, Ergebnis und Zusammensetzung. Der
/// native Modellspeicher ist zusätzlich vom jeweiligen Modell abhängig.
class TileMemoryPlan {
  const TileMemoryPlan(
    this.sourceBytes,
    this.outputBytes,
    this.bandBytes,
    this.tileBytes,
  );
  final int sourceBytes, outputBytes, bandBytes, tileBytes;
  int get totalBytes => sourceBytes + outputBytes + bandBytes + tileBytes;
}

void _pruefeKacheln(int tileSize, int overlap, int scaleFactor) {
  if (tileSize <= 0 || overlap < 0 || overlap >= tileSize || scaleFactor <= 0) {
    throw ArgumentError('pv_kachel_parameter');
  }
}

TileMemoryPlan tileMemoryPlan(
  img.Image source, {
  required int tileSize,
  required int overlap,
  required int scaleFactor,
}) {
  _pruefeKacheln(tileSize, overlap, scaleFactor);
  final width = source.width * scaleFactor;
  final height = source.height * scaleFactor;
  final tw = math.min(tileSize, source.width),
      th = math.min(tileSize, source.height);
  return TileMemoryPlan(
    source.data?.lengthInBytes ?? source.width * source.height * 4,
    width * height * 3,
    width * th * scaleFactor * 16,
    tw * th * (4 + scaleFactor * scaleFactor * 7),
  );
}

class TileMemoryLimit implements Exception {
  const TileMemoryLimit(this.requiredBytes, this.limitBytes);
  final int requiredBytes, limitBytes;
  @override
  String toString() => 'pv_kachel_speicher:$requiredBytes:$limitBytes';
}

/// Verarbeitet jeweils nur eine Quellkachel. Fertige Zeilen werden sofort
/// normalisiert; Float-Akkumulatoren belegen nur ein umlaufendes Zeilenband.
/// Die Additionsreihenfolge und Überblendung entsprechen der vollständigen
/// Zusammensetzung. Ein abgebrochenes Ergebnis bleibt unvollständig und
/// muss vom Aufrufer verworfen werden.
Future<img.Image> processInTiles(
  img.Image source, {
  required int tileSize,
  required int overlap,
  required int scaleFactor,
  required Future<img.Image> Function(img.Image tile) infer,
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
  int maxWorkingBytes = 1536 * 1024 * 1024,
  void Function(TileMemoryPlan plan)? onMemoryPlan,
}) async {
  final plan = tileMemoryPlan(
    source,
    tileSize: tileSize,
    overlap: overlap,
    scaleFactor: scaleFactor,
  );
  onMemoryPlan?.call(plan);
  if (plan.totalBytes > maxWorkingBytes) {
    throw TileMemoryLimit(plan.totalBytes, maxWorkingBytes);
  }
  final stride = tileSize - overlap;
  final xs = _tileStarts(source.width, tileSize, stride);
  final ys = _tileStarts(source.height, tileSize, stride);
  final outWidth = source.width * scaleFactor;
  final outHeight = source.height * scaleFactor;
  final bandHeight = math.min(tileSize, source.height) * scaleFactor;
  final accum = Float32List(outWidth * bandHeight * 3);
  final weightSum = Float32List(outWidth * bandHeight);
  final result = img.Image(width: outWidth, height: outHeight);
  var written = 0, done = 0;
  void flush(int until) {
    for (; written < until; written++) {
      final row = (written % bandHeight) * outWidth;
      for (var x = 0; x < outWidth; x++) {
        final idx = row + x;
        final w = weightSum[idx];
        if (w > 0) {
          result.setPixelRgb(
            x,
            written,
            (accum[idx * 3] / w).round().clamp(0, 255),
            (accum[idx * 3 + 1] / w).round().clamp(0, 255),
            (accum[idx * 3 + 2] / w).round().clamp(0, 255),
          );
        }
        accum[idx * 3] = 0;
        accum[idx * 3 + 1] = 0;
        accum[idx * 3 + 2] = 0;
        weightSum[idx] = 0;
      }
    }
  }

  rows:
  for (var row = 0; row < ys.length; row++) {
    final ty = ys[row];
    for (final tx in xs) {
      if (isCancelled?.call() ?? false) break rows;
      final tw = math.min(tileSize, source.width - tx);
      final th = math.min(tileSize, source.height - ty);
      final tile = img.copyCrop(source, x: tx, y: ty, width: tw, height: th);
      final processed = await infer(tile);
      if (processed.width != tw * scaleFactor ||
          processed.height != th * scaleFactor) {
        throw StateError('pv_kachel_ausgabe');
      }
      final weights = _tileWeights(
        width: processed.width,
        height: processed.height,
        featherX: overlap * scaleFactor,
        featherY: overlap * scaleFactor,
        touchesLeft: tx == 0,
        touchesTop: ty == 0,
        touchesRight: tx + tw >= source.width,
        touchesBottom: ty + th >= source.height,
      );
      final ox = tx * scaleFactor, oy = ty * scaleFactor;
      for (var y = 0; y < processed.height; y++) {
        final rowBase = ((oy + y) % bandHeight) * outWidth;
        for (var x = 0; x < processed.width; x++) {
          final w = weights[y * processed.width + x];
          if (w <= 0) continue;
          final px = processed.getPixel(x, y);
          final idx = rowBase + ox + x;
          accum[idx * 3] += px.r * w;
          accum[idx * 3 + 1] += px.g * w;
          accum[idx * 3 + 2] += px.b * w;
          weightSum[idx] += w;
        }
      }
      done++;
      onProgress?.call(done, xs.length * ys.length);
    }
    flush(row + 1 < ys.length ? ys[row + 1] * scaleFactor : outHeight);
  }
  flush(outHeight);
  return result;
}
