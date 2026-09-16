// Was das Zeichnen einer Landschaft kostet - je Kante und je Blockzahl.
//
//   flutter test tool/messe_gelaendemaler_test.dart
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
  testWidgets('Zeichnen je Bild', (tester) async {
    for (final fall in [
      (kante: 96, stufe: 12),
      (kante: 96, stufe: 13),
      (kante: 96, stufe: 14),
      (kante: 96, stufe: 15),
      (kante: 96, stufe: 16),
    ]) {
      final kante = fall.kante;
      final netz = baueNetz(_gitter(220), kante: kante, grundstufe: fall.stufe);
      final maler = Gelaendemaler(
        netz: netz,
        kamera: const Gelaendekamera(
          drehung: math.pi * 0.7,
          neigung: 0.35,
          entfernung: 4000,
          brennweite: 900,
          mitte: Offset(600, 400),
          blickpunkt: (x: 0.0, y: 0.0, z: 0.0),
        ),
        spur: const [],
        spurfarbe: const Color(0xFFFF7043),
      );
      // Warmlaufen: der erste Durchgang legt das Kratzpapier an.
      for (var i = 0; i < 5; i++) {
        maler.paint(ui.Canvas(ui.PictureRecorder()), const Size(1200, 800));
      }
      const laeufe = 60;
      final uhr = Stopwatch()..start();
      for (var i = 0; i < laeufe; i++) {
        maler.paint(ui.Canvas(ui.PictureRecorder()), const Size(1200, 800));
      }
      uhr.stop();
      // ignore: avoid_print
      final sichtbar =
          bloeckeAnzahlImBild(netz, maler.kamera, const Size(1200, 800));
      // ignore: avoid_print
      print('Stufe ${fall.stufe}: ${netz.bloecke.length} Bloecke, '
          'davon $sichtbar im Bild, '
          '${netz.dreiecke} Dreiecke, '
          '${(uhr.elapsedMicroseconds / laeufe / 1000).toStringAsFixed(2)} ms '
          'je Bild');
    }
  });
}
