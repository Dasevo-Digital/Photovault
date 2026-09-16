
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/inpainting_service.dart';

/// Die Objektentfernung am ECHTEN Modell.
///
/// Warum als Integrationstest und nicht unter `test/`: Die ONNX-Anbindung
/// läuft über einen Plattformkanal und ist in einem reinen `flutter test`
/// nicht erreichbar. Ohne diesen Lauf wäre die Dart-Seite der Anbindung –
/// Tensor packen, Ausgabe auslesen – gar nicht geprüft, und genau dort
/// sitzen die Fehler, die man dem Ergebnis nicht ansieht: vertauschte
/// Kanäle, falscher Wertebereich.
///
/// Übersprungen, wenn das Modell nicht installiert ist.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ein Fleck verschwindet und die Umgebung bleibt', (tester) async {
    final support = await getApplicationSupportDirectory();
    final modelle = p.join(support.path, 'PhotoVault', 'models');
    if (!InpaintingService.isAvailable(modelle)) {
      // markTestSkipped statt eines blossen return - sonst meldet sich
      // ein Lauf ohne Modell als bestanden.
      markTestSkipped('lama_fp32.onnx nicht installiert in $modelle');
      return;
    }

    // Ein glatter Farbverlauf mit einem schwarzen Fleck darin. Ein Modell,
    // das funktioniert, muss den Verlauf fortsetzen.
    const n = 700;
    final soll = img.Image(width: n, height: n);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        soll.setPixelRgb(x, y, 60 + 150 * x ~/ n, 90 + 120 * y ~/ n, 200 - 100 * x ~/ n);
      }
    }
    final kaputt = img.Image.from(soll);
    final maske = img.Image(width: n, height: n);
    img.fillRect(kaputt, x1: 300, y1: 300, x2: 400, y2: 400,
        color: img.ColorRgb8(0, 0, 0));
    img.fillRect(maske, x1: 300, y1: 300, x2: 400, y2: 400,
        color: img.ColorRgb8(255, 255, 255));

    final dienst = await InpaintingService.load(modelle);
    final uhr = Stopwatch()..start();
    final ergebnis = await dienst.entferne(kaputt, maske);
    uhr.stop();
    await dienst.dispose();

    expect(ergebnis, isNotNull);

    // 1. Der Fleck ist weg: Im gefüllten Bereich liegt das Ergebnis nah am
    //    ursprünglichen Verlauf, nicht bei Schwarz.
    var summe = 0.0;
    var punkte = 0;
    for (var y = 320; y < 380; y++) {
      for (var x = 320; x < 380; x++) {
        final e = ergebnis!.getPixel(x, y);
        final s = soll.getPixel(x, y);
        summe += (e.r - s.r).abs() + (e.g - s.g).abs() + (e.b - s.b).abs();
        punkte += 3;
      }
    }
    final mittlererFehler = summe / punkte;
    // ignore: avoid_print
    print('MESSUNG Objektentfernung: mittlerer Fehler im gefüllten Bereich '
        '${mittlererFehler.toStringAsFixed(1)} von 255, Dauer ${uhr.elapsedMilliseconds} ms');
    // Gemessen 1,4 – die Schranke lässt Luft für Modellversionen, ist aber
    // eng genug, dass ein zu kleiner Ausschnitt auffällt: Mit einem
    // Ausschnitt unter 512 Punkten, der hochgerechnet werden muss, lag der
    // Fehler bei 19,2.
    expect(mittlererFehler, lessThan(8),
        reason: 'der Verlauf muss fortgesetzt werden, nicht irgendetwas');

    // 2. Ausserhalb der Maske bleibt das Bild unangetastet – sonst
    //    veränderte eine Retusche das ganze Foto.
    for (final punkt in [[10, 10], [690, 10], [10, 690], [690, 690], [150, 500]]) {
      final e = ergebnis!.getPixel(punkt[0], punkt[1]);
      final k = kaputt.getPixel(punkt[0], punkt[1]);
      expect(e.r, k.r, reason: 'bei $punkt');
      expect(e.g, k.g, reason: 'bei $punkt');
      expect(e.b, k.b, reason: 'bei $punkt');
    }

    // 3. Jeder Kanal einzeln – so fällt ein Kanaldreher auf, den der
    //    Gesamtfehler verschlucken könnte. Der Verlauf ist absichtlich in
    //    allen drei Kanälen verschieden steil.
    for (final kanal in [0, 1, 2]) {
      var e = 0.0, sw = 0.0;
      for (var y = 320; y < 380; y++) {
        for (var x = 320; x < 380; x++) {
          final pe = ergebnis!.getPixel(x, y);
          final ps = soll.getPixel(x, y);
          e += kanal == 0 ? pe.r : (kanal == 1 ? pe.g : pe.b);
          sw += kanal == 0 ? ps.r : (kanal == 1 ? ps.g : ps.b);
        }
      }
      expect(e / 3600, closeTo(sw / 3600, 8), reason: 'Kanal $kanal');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('eine leere Maske ändert nichts', (tester) async {
    final support = await getApplicationSupportDirectory();
    final modelle = p.join(support.path, 'PhotoVault', 'models');
    if (!InpaintingService.isAvailable(modelle)) {
      markTestSkipped('lama_fp32.onnx nicht installiert in $modelle');
      return;
    }

    final bild = img.Image(width: 200, height: 200);
    img.fill(bild, color: img.ColorRgb8(100, 110, 120));
    final dienst = await InpaintingService.load(modelle);
    final ergebnis = await dienst.entferne(bild, img.Image(width: 200, height: 200));
    await dienst.dispose();
    expect(ergebnis, isNull, reason: 'ohne Markierung gibt es nichts zu tun');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
