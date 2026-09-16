// **Wo die Zeit einer Videoausgabe hingeht.**
//
// Ein Überflug von einer Minute sind rund zweitausend Bilder. Bevor
// irgendwo gespart wird, muss klar sein, welcher Schritt überhaupt
// etwas kostet: das Malen, das Rastern (`toImage`), das Herausholen der
// Bildpunkte (`toByteData`) – oder der Weg hinüber zum Kodierer.
//
//   flutter test tool/messe_videobild_test.dart
// ignore_for_file: avoid_print
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('je Bild', (tester) async {
    for (final (b, h) in [(1280, 720), (1920, 1080), (2560, 1440)]) {
      await tester.runAsync(() async {
        var malen = 0, rastern = 0, holen = 0;
        const laeufe = 12;
        for (var i = -2; i < laeufe; i++) {
          final warm = i < 0; // zwei Durchgänge zum Warmlaufen
          var uhr = Stopwatch()..start();
          final sammler = ui.PictureRecorder();
          final leinwand = ui.Canvas(sammler);
          leinwand.drawRect(ui.Rect.fromLTWH(0, 0, b.toDouble(), h.toDouble()),
              ui.Paint()..color = Colors.indigo);
          // Etwas Geometrie, damit nicht eine leere Fläche gemessen wird.
          for (var k = 0; k < 400; k++) {
            leinwand.drawCircle(
                Offset(b * (k % 20) / 20, h * (k ~/ 20) / 20),
                12 + (k % 7) * 3,
                ui.Paint()..color = Colors.white.withValues(alpha: 0.5));
          }
          final aufnahme = sammler.endRecording();
          if (!warm) malen += uhr.elapsedMicroseconds;

          uhr = Stopwatch()..start();
          final bild = await aufnahme.toImage(b, h);
          aufnahme.dispose();
          if (!warm) rastern += uhr.elapsedMicroseconds;

          uhr = Stopwatch()..start();
          final roh = await bild.toByteData(format: ui.ImageByteFormat.rawRgba);
          if (!warm) holen += uhr.elapsedMicroseconds;
          bild.dispose();
          if (i == 0) {
            print('${b}x$h: ${(roh!.lengthInBytes / 1024 / 1024).toStringAsFixed(1)} MB je Bild');
          }
        }
        double ms(int us) => us / laeufe / 1000;
        print('${b}x$h  malen ${ms(malen).toStringAsFixed(1)} ms · '
            'rastern ${ms(rastern).toStringAsFixed(1)} ms · '
            'holen ${ms(holen).toStringAsFixed(1)} ms · '
            'zusammen ${ms(malen + rastern + holen).toStringAsFixed(1)} ms'
            ' -> 1800 Bilder in '
            '${(ms(malen + rastern + holen) * 1800 / 1000).toStringAsFixed(0)} s');
      });
    }
    expect(math.pi, greaterThan(3));
  });
}
