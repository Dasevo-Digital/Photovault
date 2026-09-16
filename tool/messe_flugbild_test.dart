// **Was ein Flugbild neben dem Zeichnen kostet.**
//
// `messe_gelaendemaler_test.dart` misst das Zeichnen. Ein Bild besteht
// aber aus mehr: Die Ansicht rechnet in JEDEM Bild aus, welche Blöcke im
// Bild stehen und in welcher Schärfe – und meldet das dem Lader. Bei
// neunhundert Blöcken sind das neunhundert Sichtprüfungen über je acht
// Kastenecken, und danach eine frisch angelegte Liste.
//
//   flutter test tool/messe_flugbild_test.dart
// ignore_for_file: avoid_print
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/blocktexturen.dart';
import 'package:photo_vault/services/gelaendeebenen.dart';
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
  test('Blockwahl je Bild', () {
    for (final stufe in [12, 14, 15, 16]) {
      final netz = baueNetz(_gitter(220), kante: 96, grundstufe: stufe);
      const kamera = Gelaendekamera(
        drehung: math.pi * 0.7,
        neigung: 0.35,
        entfernung: 4000,
        brennweite: 900,
        mitte: Offset(600, 400),
        blickpunkt: (x: 0.0, y: 0.0, z: 0.0),
      );
      const flaeche = Size(1200, 800);
      for (var i = 0; i < 20; i++) {
        bloeckeImBild(netz, kamera, flaeche);
      }
      const laeufe = 300;
      final uhr = Stopwatch()..start();
      var summe = 0;
      for (var i = 0; i < laeufe; i++) {
        summe += bloeckeImBild(netz, kamera, flaeche).length;
      }
      uhr.stop();
      print('Stufe $stufe: ${netz.bloecke.length} Bloecke, '
          '${summe ~/ laeufe} gewuenscht, '
          '${(uhr.elapsedMicroseconds / laeufe / 1000).toStringAsFixed(3)} ms '
          'je Bild');
    }
  });

  test('was der Lader mit dem Wunsch macht', () {
    final netz = baueNetz(_gitter(220), kante: 96, grundstufe: 16);
    const kamera = Gelaendekamera(
      drehung: math.pi * 0.7,
      neigung: 0.35,
      entfernung: 4000,
      brennweite: 900,
      mitte: Offset(600, 400),
      blickpunkt: (x: 0.0, y: 0.0, z: 0.0),
    );
    final lader = Blocktexturlader(
      karte: const Gelaendekarte(),
      grundstufe: netz.grundstufe,
    );
    final wunsch = bloeckeImBild(netz, kamera, const Size(1200, 800));
    for (var i = 0; i < 20; i++) {
      lader.brauche(wunsch);
    }
    const laeufe = 300;
    final uhr = Stopwatch()..start();
    for (var i = 0; i < laeufe; i++) {
      lader.brauche(wunsch);
    }
    uhr.stop();
    print('brauche(${wunsch.length}): '
        '${(uhr.elapsedMicroseconds / laeufe / 1000).toStringAsFixed(3)} ms '
        'je Bild');
    lader.schliessen();
  });
}
