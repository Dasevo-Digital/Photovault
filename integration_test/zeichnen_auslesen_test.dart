// ignore_for_file: avoid_print
// **Ein abseits des Bildschirms gezeichnetes Bild lässt sich auslesen.**
//
// Diashow, Kameraflug, PDF-Tafeln und Geländetexturen zeichnen in ein
// `PictureRecorder`, machen daraus mit `toImage` ein Bild und lesen dessen
// Pixel mit `toByteData`. Unter Linux mit Impeller (Voreinstellung seit
// Flutter 3.47) kamen dabei nur leere Pixel heraus; die Diashow wurde
// schwarz, ohne Fehlermeldung. Der Linux-Runner schaltet Impeller deshalb
// ab (`linux/runner/my_application.cc`). Dieser Test belegt es im
// Zielprozess, auf jeder Plattform:
//
//   flutter test integration_test/zeichnen_auslesen_test.dart -d linux
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Farbe, Verlauf, Foto und Form kommen beim Auslesen an', (
    tester,
  ) async {
    final daten = await rootBundle.load('assets/lebensbaum/landschaft.jpg');
    late ui.Image foto;
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(daten.buffer.asUint8List());
      foto = (await codec.getNextFrame()).image;
      codec.dispose();
    });

    final rekorder = ui.PictureRecorder();
    final leinwand = Canvas(rekorder)
      ..drawRect(
        const Rect.fromLTWH(0, 0, 100, 100),
        Paint()..color = const Color(0xFFFF0000),
      )
      ..drawRect(
        const Rect.fromLTWH(100, 0, 100, 100),
        Paint()
          ..shader = ui.Gradient.linear(
            const Offset(100, 0),
            const Offset(200, 100),
            [const Color(0xFF00FF00), const Color(0xFF00FF00)],
          ),
      );
    leinwand
      ..drawImageRect(
        foto,
        Rect.fromLTWH(0, 0, foto.width.toDouble(), foto.height.toDouble()),
        const Rect.fromLTWH(200, 0, 100, 100),
        Paint(),
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(300, 0, 100, 100),
          const Radius.circular(10),
        ),
        Paint()..color = const Color(0xFF0000FF),
      );

    final pixel = await tester.runAsync(() async {
      final bild = await rekorder.endRecording().toImage(400, 100);
      final roh = (await bild.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      bild.dispose();
      return [
        for (final x in [50, 150, 250, 350]) roh.getUint32((50 * 400 + x) * 4),
      ];
    });
    foto.dispose();
    print(
      '${Platform.operatingSystem}: '
      '${pixel!.map((v) => v.toRadixString(16).padLeft(8, '0')).join(' ')}',
    );

    expect(pixel[0], 0xFF0000FF, reason: 'Farbfläche fehlt');
    expect(pixel[1], 0x00FF00FF, reason: 'Verlauf fehlt');
    expect(pixel[2] & 0xFF, 0xFF, reason: 'Foto fehlt (durchsichtig)');
    expect(pixel[2], isNot(0x000000FF), reason: 'Foto fehlt (schwarz)');
    expect(pixel[3], 0x0000FFFF, reason: 'Form fehlt');
  });
}
