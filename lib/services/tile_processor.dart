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
List<Tile> splitIntoTiles(img.Image source, {required int tileSize, required int overlap}) {
  assert(tileSize > overlap, 'tileSize muss größer als overlap sein');
  final stride = tileSize - overlap;
  final xs = _tileStarts(source.width, tileSize, stride);
  final ys = _tileStarts(source.height, tileSize, stride);
  final tiles = <Tile>[];
  for (final y in ys) {
    for (final x in xs) {
      final w = math.min(tileSize, source.width - x);
      final h = math.min(tileSize, source.height - y);
      tiles.add(Tile(x: x, y: y, image: img.copyCrop(source, x: x, y: y, width: w, height: h)));
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
    if (!touchesBottom && fy > 0 && y >= height - fy) wy = math.min(wy, (height - y) / fy);
    for (var x = 0; x < width; x++) {
      var wx = 1.0;
      if (!touchesLeft && fx > 0 && x < fx) wx = (x + 1) / fx;
      if (!touchesRight && fx > 0 && x >= width - fx) wx = math.min(wx, (width - x) / fx);
      weights[y * width + x] = wx * wy;
    }
  }
  return weights;
}

/// Zerlegt [source] in Kacheln, ruft [infer] pro Kachel auf (z.B. eine
/// ONNX-Inferenz, siehe RestoreService) und setzt die – bereits um
/// [scaleFactor] vergrößerten – Ergebnis-Kacheln mit gewichteter
/// Rand-Überblendung zu einem [scaleFactor]-fach größeren Gesamtbild
/// zusammen. Generischer Baustein, unabhängig von ONNX/Real-ESRGAN –
/// [infer] kann für Tests auch eine reine Identitäts-/Skalierungsfunktion
/// sein (siehe tile_processor_test.dart).
///
/// [isCancelled] wird zwischen Kacheln geprüft (kein Abbruch mitten in
/// einer laufenden Inferenz) – bei Abbruch werden nur die bereits
/// verarbeiteten Kacheln zusammengesetzt (das Ergebnis ist dann nicht
/// vollständig und wird vom Aufrufer verworfen, nicht gespeichert).
Future<img.Image> processInTiles(
  img.Image source, {
  required int tileSize,
  required int overlap,
  required int scaleFactor,
  required Future<img.Image> Function(img.Image tile) infer,
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  final tiles = splitIntoTiles(source, tileSize: tileSize, overlap: overlap);
  final outWidth = source.width * scaleFactor;
  final outHeight = source.height * scaleFactor;
  final accum = Float32List(outWidth * outHeight * 3);
  final weightSum = Float32List(outWidth * outHeight);

  for (var i = 0; i < tiles.length; i++) {
    if (isCancelled?.call() ?? false) break;
    final tile = tiles[i];
    final processed = await infer(tile.image);
    final ox = tile.x * scaleFactor;
    final oy = tile.y * scaleFactor;
    final weights = _tileWeights(
      width: processed.width,
      height: processed.height,
      featherX: overlap * scaleFactor,
      featherY: overlap * scaleFactor,
      touchesLeft: tile.x == 0,
      touchesTop: tile.y == 0,
      touchesRight: tile.x + tile.image.width >= source.width,
      touchesBottom: tile.y + tile.image.height >= source.height,
    );

    for (var y = 0; y < processed.height; y++) {
      final outY = oy + y;
      if (outY >= outHeight) continue;
      final rowBase = outY * outWidth;
      final tileRowBase = y * processed.width;
      for (var x = 0; x < processed.width; x++) {
        final outX = ox + x;
        if (outX >= outWidth) continue;
        final w = weights[tileRowBase + x];
        if (w <= 0) continue;
        final px = processed.getPixel(x, y);
        final outIdx = rowBase + outX;
        accum[outIdx * 3] += px.r * w;
        accum[outIdx * 3 + 1] += px.g * w;
        accum[outIdx * 3 + 2] += px.b * w;
        weightSum[outIdx] += w;
      }
    }
    onProgress?.call(i + 1, tiles.length);
  }

  final result = img.Image(width: outWidth, height: outHeight);
  for (var y = 0; y < outHeight; y++) {
    final rowBase = y * outWidth;
    for (var x = 0; x < outWidth; x++) {
      final idx = rowBase + x;
      final w = weightSum[idx];
      if (w <= 0) continue; // Bei voller Kachel-Abdeckung sollte das nie vorkommen.
      result.setPixelRgb(
        x,
        y,
        (accum[idx * 3] / w).round().clamp(0, 255),
        (accum[idx * 3 + 1] / w).round().clamp(0, 255),
        (accum[idx * 3 + 2] / w).round().clamp(0, 255),
      );
    }
  }
  return result;
}
