import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/gelaendekacheln.dart';
import 'package:photo_vault/services/gelaendesicht.dart';
import 'package:photo_vault/widgets/gelaende.dart';

/// **Die Messung, die über die Geländeansicht entscheidet.**
///
/// Der Plan sagte: „Ein Gitter von 256×256 sind 130.000 Dreiecke je
/// Kachel – das ist zu viel und muss heruntergerechnet werden. Die Zahl
/// entscheidet die Messung, nicht die Schätzung."
///
/// Gemessen wird beides getrennt: das **Bauen** des Netzes (einmal je
/// Gitter) und das **Zeichnen** (jedes Bild, also sechzigmal in der
/// Sekunde beim Drehen). Nur das zweite muss schnell sein.
void main() {
  /// Ein Gitter mit einer Landschaft darin – Wellen, damit die
  /// Schattierung etwas zu rechnen hat.
  Hoehengitter gitter(int kante) {
    final hoehen = Float32List(kante * kante);
    for (var y = 0; y < kante; y++) {
      for (var x = 0; x < kante; x++) {
        hoehen[y * kante + x] =
            300 + 200 * ((x % 17) / 17) + 150 * ((y % 23) / 23);
      }
    }
    return Hoehengitter(
      spalten: kante,
      zeilen: kante,
      hoehen: hoehen,
      nord: 50.7,
      sued: 50.6,
      west: 9.8,
      ost: 9.95,
    );
  }

  test('Dreieckszahl gegen Zeit – Bauen und Zeichnen', () {
    // ignore: avoid_print
    print('Kante | Dreiecke | Bauen | Zeichnen');
    for (final kante in [32, 64, 96, 128, 192, 256]) {
      final roh = gitter(256);

      final bauUhr = Stopwatch()..start();
      final netz = baueNetz(roh, kante: kante);
      bauUhr.stop();

      const kamera = Gelaendekamera(
        drehung: 0.35,
        neigung: 0.95,
        entfernung: 20000,
        brennweite: 900,
        mitte: Offset(500, 400),
      );
      final maler = Gelaendemaler(
        netz: netz,
        kamera: kamera,
        spur: const [],
        spurfarbe: const Color(0xFFFF0000),
      );

      // Ein Aufwärmlauf, dann zehn gemessene: Der erste zahlt für alles,
      // was einmalig ist.
      final sammler = ui.PictureRecorder();
      maler.paint(Canvas(sammler), const Size(1000, 800));
      sammler.endRecording().dispose();

      final zeichenUhr = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        final s = ui.PictureRecorder();
        maler.paint(Canvas(s), const Size(1000, 800));
        s.endRecording().dispose();
      }
      zeichenUhr.stop();

      // ignore: avoid_print
      print('${kante.toString().padLeft(5)} | '
          '${netz.dreiecke.toString().padLeft(8)} | '
          '${bauUhr.elapsedMilliseconds.toString().padLeft(5)} ms | '
          '${(zeichenUhr.elapsedMicroseconds / 10 / 1000).toStringAsFixed(2).padLeft(8)} ms');
    }

    // Keine Zusicherung über Millisekunden – die hinge an der Maschine.
    // Was hier zugesichert wird, ist die Grössenordnung der Dreiecke:
    // Sie ist der Grund für die gewählte Kante. Genau
    // `(kante-1)² · 2` sind es nicht mehr, seit die Landschaft in Blöcke
    // zerfällt – jeder Block rundet seine Maschenzahl für sich.
    final netz = baueNetz(gitter(256), kante: gelaendeGitterkante);
    const erwartet = gelaendeGitterkante * gelaendeGitterkante * 2;
    expect(netz.dreiecke, greaterThan(erwartet ~/ 2));
    expect(netz.dreiecke, lessThan(erwartet * 2));
  });
}
