import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_vault/services/kratzermodell.dart';

/// Das Kratzer-Netz im Zielprozess.
///
/// Nicht in Python geprüft, sondern hier: Ob eine ONNX-Datei sich laden
/// lässt, entscheidet die ONNX Runtime, die die App mitbringt – zwei
/// fp16-Modelle liefen in Python und scheiterten in der App (siehe die
/// Notiz zum CLIP-Ausfall). Übersprungen, wenn das Modell fehlt.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ein Kratzer auf einem alten Bild wird gefunden', (tester) async {
    final support = await getApplicationSupportDirectory();
    final modelle = p.join(support.path, 'PhotoVault', 'models');
    if (!KratzerModellService.isAvailable(modelle)) {
      markTestSkipped('${KratzerModellService.datei} fehlt in $modelle');
      return;
    }
    // Ein grauer, leicht unruhiger Abzug mit einem geschwungenen hellen
    // Kratzer quer durch.
    const b = 900, h = 600;
    final bild = img.Image(width: b, height: h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < b; x++) {
        final v = 110 + (40 * (x / b)).round() + ((x * 7 + y * 13) % 9);
        bild.setPixelRgb(x, y, v, v, v);
      }
    }
    final punkte = <img.Point>[
      for (var i = 0; i <= 20; i++)
        img.Point(40 + i * 40, 120 + (i * i * 0.9).round()),
    ];
    for (var i = 1; i < punkte.length; i++) {
      img.drawLine(
        bild,
        x1: punkte[i - 1].x.toInt(),
        y1: punkte[i - 1].y.toInt(),
        x2: punkte[i].x.toInt(),
        y2: punkte[i].y.toInt(),
        color: img.ColorRgb8(240, 240, 240),
        thickness: 3,
      );
    }

    final dienst = await KratzerModellService.load(modelle);
    final uhr = Stopwatch()..start();
    final fund = await dienst.suche(bild);
    uhr.stop();
    await dienst.dispose();

    var aufKratzer = 0;
    for (final q in punkte.skip(2).take(15)) {
      if (fund.maske.getPixel(q.x.toInt(), q.y.toInt()).r > 0) aufKratzer++;
    }
    final flaeche = fund.maske.where((q) => q.r > 0).length / (b * h);
    // ignore: avoid_print
    print(
      'Kratzer-Netz: $aufKratzer/15 Stützpunkte getroffen, '
      'Fläche ${(flaeche * 100).toStringAsFixed(2)} %, '
      '${fund.kratzer} Stellen, ${uhr.elapsedMilliseconds} ms',
    );
    expect(aufKratzer, greaterThanOrEqualTo(10));
    expect(flaeche, lessThan(0.1), reason: 'nicht das halbe Bild');
  });
}
