// ignore_for_file: avoid_print
// Rechnen der Shader und Core Image beim Lichter-Regler dasselbe?
//
// Die Live-Vorschau laeuft ueber den Shader
// (shaders/develop_adjustments.frag), das gespeicherte Ergebnis unter
// macOS ueber Core Image (ImageConverter.swift, lichterKern). Beide
// tragen dieselbe Formel - aber "dieselbe Formel geschrieben" und
// "dasselbe Ergebnis gerechnet" sind zwei verschiedene Aussagen. Laufen
// sie auseinander, sieht der Nutzer beim Speichern ein anderes Bild als
// beim Ziehen, und niemand kann sagen, welches das richtige ist.
//
// Laeuft nur unter macOS: Auf den anderen Plattformen IST der Shader der
// Renderpfad, dort gibt es nichts zu vergleichen.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/develop_render.dart';
import 'package:photo_vault/services/native_image_converter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  double mittel(Uint8List jpeg) {
    final b = img.decodeImage(jpeg)!;
    var summe = 0.0;
    var n = 0;
    for (var x = 0; x < b.width; x += 4) {
      for (var y = 0; y < b.height; y += 4) {
        summe += b.getPixel(x, y).luminance;
        n++;
      }
    }
    return summe / n;
  }

  test('Shader und Core Image rechnen den Lichter-Regler gleich', () async {
    if (!Platform.isMacOS) {
      print('nur unter macOS sinnvoll - uebersprungen');
      return;
    }
    final temp = Directory.systemTemp.createTempSync('pv_lichter_');
    try {
      // Mehrere Helligkeiten: Die Gewichtung haengt an der Luminanz, ein
      // einzelner Wert koennte zufaellig passen.
      for (final grundwert in [140, 190, 220, 240]) {
        final bild = img.Image(width: 256, height: 256);
        img.fill(bild, color: img.ColorRgb8(grundwert, grundwert, grundwert));
        final quelle = File(p.join(temp.path, 'g$grundwert.png'))
          ..writeAsBytesSync(img.encodePng(bild));

        for (final lichter in [-0.5, 0.5]) {
          final werte = DevelopAdjustments(highlights: lichter);
          final ueberShader =
              await DevelopRender.rendere(quelle, adjustments: werte);
          final ueberCoreImage =
              await NativeImageConverter.developImage(quelle, adjustments: werte);

          expect(ueberShader, isNotNull, reason: 'Shader lieferte nichts');
          expect(ueberCoreImage, isNotNull, reason: 'Core Image lieferte nichts');

          final s = mittel(ueberShader!);
          final c = mittel(ueberCoreImage!);
          print('Grau $grundwert, Lichter $lichter: '
              'Shader ${s.toStringAsFixed(1)}, Core Image ${c.toStringAsFixed(1)}, '
              'Abweichung ${(s - c).abs().toStringAsFixed(1)}');

          // Drei Tonwertstufen Toleranz. Das deckt JPEG-Rundung und
          // Unterschiede im Farbraum-Handling ab, aber keine andere
          // Formel: Bei vertauschten Grenzen der Gewichtung laegen hier
          // zweistellige Abweichungen.
          expect((s - c).abs(), lessThan(3.0),
              reason: 'Grau $grundwert, Lichter $lichter');
        }
      }
    } finally {
      temp.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
