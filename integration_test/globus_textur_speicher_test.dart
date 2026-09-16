// ignore_for_file: avoid_print
// Was die 8K-Erdtextur im Speicher kostet – und ob Flutters Bildspeicher
// sie überhaupt behält.
//
// Anlass: 8192×4096 sind dekodiert 134 MB. Flutters ImageCache fasst
// standardmässig 100 MB. Passt ein Bild nicht hinein, wird es NICHT
// zwischengespeichert und bei jedem Bedarf neu dekodiert. Genau dieser
// Effekt hat in der Kartenansicht schon einmal graue Platzhalter
// verursacht.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Erdtextur im Bildspeicher', (tester) async {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
    print('Grenze des Bildspeichers: '
        '${(cache.maximumSizeBytes / 1e6).toStringAsFixed(1)} MB');

    const bild = AssetImage('assets/globe/8k_earth_daymap.jpg');
    final fertig = Completer<void>();
    late ImageInfo info;
    final strom = bild.resolve(ImageConfiguration.empty);
    strom.addListener(ImageStreamListener((i, _) {
      info = i;
      if (!fertig.isCompleted) fertig.complete();
    }, onError: (e, _) {
      if (!fertig.isCompleted) fertig.completeError(e);
    }));
    await tester.runAsync(() => fertig.future);

    final w = info.image.width, h = info.image.height;
    final bytes = w * h * 4;
    print('Textur: ${w}x$h = ${(bytes / 1e6).toStringAsFixed(1)} MB dekodiert');
    print('im Speicher gehalten: ${(cache.currentSizeBytes / 1e6).toStringAsFixed(1)} MB '
        'in ${cache.currentSize} Bildern');
    expect(w, 8192);
    expect(h, 4096);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
