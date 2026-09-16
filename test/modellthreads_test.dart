import 'dart:io' show Directory, File, Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/modellthreads.dart';

/// **„Bei der Ausführung der Aufgabe Standbilder generieren war die App
/// nicht mehr oder schlecht bedienbar."**
///
/// Keine Sitzung dieser App setzte je eine Threadzahl – `createSession`
/// stand an sechzehn Stellen ohne Angabe da, und ONNX Runtime nimmt sich
/// dann so viele Threads, wie der Rechner Kerne hat. Während eines Laufs
/// war damit jeder Kern belegt, auch der, auf dem das Fenster gezeichnet
/// wird. Die Oberfläche wurde nicht langsam, weil die Arbeit langsam war,
/// sondern weil für sie nichts übrig blieb.
void main() {
  test('auf einer grossen Maschine bleiben zwei Kerne frei', () {
    // Flutter braucht zwei: den Plattform-Thread (Fenster, Eingaben) und
    // den Raster-Thread (Zeichnen).
    expect(modellThreads(kerne: 16), 14);
    expect(modellThreads(kerne: 8), 6);
    expect(modellThreads(kerne: 4), 2);
  });

  test('auf kleinen Maschinen wird nichts abgezogen, was nicht da ist', () {
    expect(modellThreads(kerne: 3), 1);
    expect(modellThreads(kerne: 2), 1);
    expect(modellThreads(kerne: 1), 1);
  });

  test('nie null oder weniger – das waere ORTs Vorgabe „alle Kerne"', () {
    for (var k = 1; k <= 64; k++) {
      expect(modellThreads(kerne: k), greaterThanOrEqualTo(1), reason: '$k');
      expect(modellThreads(kerne: k), lessThanOrEqualTo(k), reason: '$k');
    }
  });

  test('jede Sitzung dieser App bekommt die Optionen auch', () {
    // Der eigentliche Fund war nicht die Rechnung, sondern dass sie
    // NIRGENDS gestellt wurde. Ein Prüfstand auf [modellThreads] allein
    // saehe nicht, ob ein siebzehntes Modell sie wieder vergisst.
    final ohne = <String>[];
    for (final datei in Directory('lib/services')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final quelle = datei.readAsStringSync();
      var ab = 0;
      while (true) {
        final i = quelle.indexOf('createSession(', ab);
        if (i < 0) break;
        ab = i + 1;
        // Der Aufruf reicht bis zur schliessenden Klammer; ein Fenster
        // von 300 Zeichen deckt auch den umgebrochenen Fall ab.
        final ende = (i + 300).clamp(0, quelle.length);
        if (!quelle.substring(i, ende).contains('modelloptionen(')) {
          ohne.add('${datei.path}: ${quelle.substring(i, (i + 60).clamp(0, quelle.length))}');
        }
      }
    }
    expect(ohne, isEmpty,
        reason: 'ohne Optionen nimmt ORT alle Kerne:\n${ohne.join('\n')}');
  });

  test('die Optionen tragen die Zahl wirklich', () {
    final o = modelloptionen();
    expect(o.intraOpNumThreads, modellThreads());
    expect(o.intraOpNumThreads, lessThan(Platform.numberOfProcessors),
        reason: 'auf dieser Maschine muss mindestens ein Kern frei bleiben');
    // Die zweite Zahl wirkt nur bei ORT_PARALLEL, das hier nirgends
    // eingestellt ist – ausdruecklich auf eins, damit eine kuenftige
    // Voreinstellung nicht unbemerkt Kerne belegt.
    expect(o.interOpNumThreads, 1);
  });
}
