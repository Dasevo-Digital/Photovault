import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/florence_captioning_service.dart';

/// Die Bildbeschreibung am ECHTEN Modell.
///
/// Warum als Integrationstest: siehe objektentfernung_test.dart – die
/// ONNX-Anbindung läuft über einen Plattformkanal und ist in einem reinen
/// `flutter test` nicht erreichbar.
///
/// Hier zählt eine Eigenschaft besonders, weil genau sie beim Nachbau
/// schiefging: Der zusammengeführte Decoder gibt den
/// Kreuz-Aufmerksamkeits-Cache nur im ERSTEN Schritt heraus, danach einen
/// Platzhalter. Wer den übernimmt, bekommt ab dem zweiten Wort ein
/// schwarzes Bild vorgesetzt – und für jedes Foto denselben Satz. Das
/// sieht man einem einzelnen Ergebnis nicht an; man sieht es erst, wenn
/// man zwei verschiedene Bilder vergleicht.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('zwei verschiedene Bilder ergeben zwei verschiedene Sätze',
      (tester) async {
    final support = await getApplicationSupportDirectory();
    final modelle = p.join(support.path, 'PhotoVault', 'models');
    if (!FlorenceCaptioningService.isAvailable(modelle)) {
      // markTestSkipped statt eines blossen return: Ein Test, der ohne
      // Modell einfach zurückkehrt, meldet sich als bestanden. Beim
      // Durchsehen einer Suite ist das von einem echten Lauf nicht zu
      // unterscheiden – und genau dieser Test ist der einzige, der die
      // Bildbeschreibung überhaupt prüft.
      markTestSkipped('Florence-2 nicht installiert in $modelle');
      return;
    }

    /// Ein einfarbiger Grund mit einer groben Form darauf – genug, damit
    /// zwei Bilder sich sichtbar unterscheiden.
    img.Image bild(int r, int g, int b, {required bool balken}) {
      const n = 800;
      final i = img.Image(width: n, height: n);
      img.fill(i, color: img.ColorRgb8(r, g, b));
      if (balken) {
        img.fillRect(i, x1: 100, y1: 300, x2: 700, y2: 500,
            color: img.ColorRgb8(255 - r, 255 - g, 255 - b));
      } else {
        img.fillCircle(i, x: 400, y: 400, radius: 220,
            color: img.ColorRgb8(255 - r, 255 - g, 255 - b));
      }
      return i;
    }

    final dienst = await FlorenceCaptioningService.load(modelle);
    try {
      final uhr = Stopwatch()..start();
      final eins = await dienst.generateCaption(bild(20, 90, 180, balken: true));
      final zeitEins = uhr.elapsedMilliseconds;
      final zwei = await dienst.generateCaption(bild(200, 160, 40, balken: false));
      uhr.stop();

      // ignore: avoid_print
      print('Satz 1 (${zeitEins}ms): $eins');
      // ignore: avoid_print
      print('Satz 2 (${uhr.elapsedMilliseconds - zeitEins}ms): $zwei');

      expect(eins, isNotEmpty, reason: 'ein leerer Satz heisst: Decoder bricht sofort ab');
      expect(zwei, isNotEmpty);
      expect(eins, isNot(equals(zwei)),
          reason: 'gleiche Sätze für verschiedene Bilder heissen: das Bild '
              'kommt nach dem ersten Schritt nicht mehr an');

      // Kein Wort dreimal hintereinander – die Wiederholungsbremse greift.
      final woerter = eins.toLowerCase().split(RegExp(r'\s+'));
      for (var i = 0; i + 2 < woerter.length; i++) {
        expect(woerter[i] == woerter[i + 1] && woerter[i + 1] == woerter[i + 2],
            isFalse, reason: 'Wiederholung ab Wort $i in „$eins"');
      }
    } finally {
      await dienst.dispose();
    }
  });
}
