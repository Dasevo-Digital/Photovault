// **Was der Spurzug je Bild kostet.**
//
// Der Maler projiziert in JEDEM Bild jeden Punkt der Spur. Die echte
// Wanderung dieser Bibliothek hat 3.965 Punkte - der bestehende
// Messstand (`messe_gelaendemaler_test.dart`) laeuft mit `spur: const []`
// und sieht davon nichts.
//
//   flutter test tool/messe_spurzug_test.dart
// ignore_for_file: avoid_print
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/gelaendekacheln.dart';
import 'package:photo_vault/services/gelaendesicht.dart';
import 'package:photo_vault/widgets/gelaende.dart';

Hoehengitter _gitter(int n) {
  final h = Float32List(n * n);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      h[y * n + x] = 400 +
          220 * math.sin(x / 9.0) * math.cos(y / 7.0) +
          90 * math.sin((x + y) / 21.0);
    }
  }
  return Hoehengitter(
    spalten: n, zeilen: n, hoehen: h,
    nord: 51.90, sued: 51.80, west: 10.55, ost: 10.71,
  );
}

void main() {
  testWidgets('Spurzug je Bild', (tester) async {
    final netz = baueNetz(_gitter(220), kante: 96, grundstufe: 14);
    const kamera = Gelaendekamera(
      drehung: math.pi * 0.7,
      neigung: 0.35,
      entfernung: 4000,
      brennweite: 900,
      mitte: Offset(600, 400),
      blickpunkt: (x: 0.0, y: 0.0, z: 0.0),
    );

    // Eine Spur in der Groessenordnung der echten Wanderung, quer durchs
    // Gelaende gelegt.
    List<Raumpunkt> spurMit(int n) => [
          for (var i = 0; i < n; i++)
            (
              x: -2000 + 4000 * i / n + 300 * math.sin(i / 40),
              y: -1800 + 3600 * i / n + 300 * math.cos(i / 33),
              z: 520 + 90 * math.sin(i / 25),
            ),
        ];

    for (final n in [0, 500, 2000, 3965]) {
      final spur = spurMit(n);
      final strecke = [for (var i = 0; i < n; i++) i * 4.0];
      for (final imFlug in [false, true]) {
        if (n == 0 && imFlug) continue;
        final maler = Gelaendemaler(
          netz: netz,
          kamera: kamera,
          spur: spur,
          spurfarbe: const Color(0xFFFF7043),
          gefahrenBis: imFlug ? n * 2.0 : null,
          streckeJePunkt: imFlug ? strecke : null,
        );
        for (var i = 0; i < 5; i++) {
          maler.paint(ui.Canvas(ui.PictureRecorder()), const Size(1200, 800));
        }
        const laeufe = 60;
        final uhr = Stopwatch()..start();
        for (var i = 0; i < laeufe; i++) {
          maler.paint(ui.Canvas(ui.PictureRecorder()), const Size(1200, 800));
        }
        uhr.stop();
        final je = uhr.elapsedMicroseconds / laeufe / 1000;
        print('${n.toString().padLeft(5)} Punkte'
            '${imFlug ? ", im Flug " : ", stehend"}   '
            '${je.toStringAsFixed(2).padLeft(6)} ms je Bild');
      }
    }
  });
}
