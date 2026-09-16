// ignore_for_file: avoid_print
// Wie lange braucht ein nativer Entwickeln-Render fuer die Vorschau?
//
// **Warum die Zahl gebraucht wird.** Vier Regler zeigen beim Ziehen
// nichts: Temperatur, Farbstich, Klarheit und Vignettierung. Der Grund
// ist, dass die Live-Vorschau ueber den Shader laeuft und der genau
// diese vier nicht (Klarheit, Vignettierung) bzw. nur genaehert
// (Weissabgleich, bis 6,1 % Abweichung) rechnet. Statt zu naehern gibt
// es einen zweiten Weg: waehrend des Ziehens **nativ** rechnen, nur
// gedrosselt. Ob das geht, entscheidet allein die Renderzeit.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/native_image_converter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('Renderzeit der Vorschau', () async {
    if (!Platform.isMacOS) {
      print('nur unter macOS sinnvoll - uebersprungen');
      return;
    }
    final temp = Directory.systemTemp.createTempSync('pv_zeit_');
    try {
      // Ein Bild in der Groessenordnung einer echten Aufnahme. Synthetisch,
      // damit kein Foto der Bibliothek beteiligt ist.
      final bild = img.Image(width: 6000, height: 4000);
      for (var y = 0; y < 4000; y += 1) {
        for (var x = 0; x < 6000; x += 1) {
          bild.setPixelRgb(x, y, (x * 255) ~/ 6000, (y * 255) ~/ 4000,
              ((x + y) * 255) ~/ 10000);
        }
      }
      final quelle = File(p.join(temp.path, 'gross.jpg'))
        ..writeAsBytesSync(img.encodeJpg(bild, quality: 92));
      print('Quelle: ${(quelle.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB, 6000x4000');

      for (final kante in [1200, 1600, 2048]) {
        final zeiten = <int>[];
        for (var i = 0; i < 5; i++) {
          final werte = DevelopAdjustments(
              exposure: 0.1 * i, temperature: 5000 + i * 200.0, tint: 0);
          final uhr = Stopwatch()..start();
          final bytes = await NativeImageConverter.developImage(quelle,
              adjustments: werte, maxDimension: kante, quality: 0.85);
          uhr.stop();
          expect(bytes, isNotNull);
          zeiten.add(uhr.elapsedMilliseconds);
        }
        zeiten.sort();
        print('Kante $kante: ${zeiten.join(", ")} ms   Mittelwert '
            '${(zeiten.reduce((a, b) => a + b) / zeiten.length).round()} ms');
      }
    } finally {
      temp.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
