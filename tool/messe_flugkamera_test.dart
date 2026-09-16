/// **Wie unruhig die Flugkamera ist – an einer echten Spur gemessen.**
///
/// Kein Teil der Prüfsuite: Es braucht eine echte GPX-Spur, und die liegt
/// in einer Bibliothek, nicht im Repository.
///
/// Die Kamera dreht sich in Laufrichtung. Auf einem Wanderweg mit
/// Serpentinen heisst das: Sie dreht sich viel. Wie viel, sagt keine
/// Meinung, sondern die Winkelgeschwindigkeit über die Flugzeit.
///
/// ```sh
/// # Spur aus einer Bibliothek holen (Kopie, nicht das Original):
/// sqlite3 -csv kopie.sqlite \
///   "SELECT breite, laenge, hoehe FROM spurpunkte ORDER BY spur_id, nummer" \
///   > /tmp/spur.csv
/// PV_SPUR=/tmp/spur.csv flutter test tool/messe_flugkamera_test.dart
/// ```
library;

// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/gelaendeflug.dart';
import 'package:photo_vault/services/gelaendesicht.dart';

void main() {
  test('Winkelgeschwindigkeit der Flugkamera', () {
    final pfad = Platform.environment['PV_SPUR'];
    if (pfad == null) {
      markTestSkipped('PV_SPUR nicht gesetzt');
      return;
    }
    final zeilen = File(pfad).readAsLinesSync().where((z) => z.trim().isNotEmpty);
    final breiten = <double>[];
    final laengen = <double>[];
    final hoehen = <double>[];
    for (final z in zeilen) {
      final t = z.split(',');
      if (t.length < 2) continue;
      final b = double.tryParse(t[0]);
      final l = double.tryParse(t[1]);
      if (b == null || l == null) continue;
      breiten.add(b);
      laengen.add(l);
      hoehen.add(t.length > 2 ? (double.tryParse(t[2]) ?? 0) : 0);
    }
    expect(breiten.length, greaterThan(100), reason: 'zu wenig Punkte');

    // Dieselbe Abbildung wie im Bildschirm: Grad auf Meter, waagerecht.
    final mitteBreite =
        breiten.reduce((a, b) => a + b) / breiten.length;
    const mB = meterJeGradBreite;
    final mL = meterJeGradLaenge(mitteBreite);
    final l0 = laengen.first, b0 = breiten.first;
    final spur = <Raumpunkt>[
      for (var i = 0; i < breiten.length; i++)
        (
          x: (laengen[i] - l0) * mL,
          y: (breiten[i] - b0) * mB,
          z: hoehen[i] * gelaendeUeberhoehung,
        ),
    ];

    final g = double.tryParse(Platform.environment['PV_GLAETTUNG'] ?? '') ?? 900;
    final flug = Gelaendeflug(spur, blickglaettung: g);
    print('Blickglaettung: ${g.round()} m');
    print('Spur: ${spur.length} Punkte, '
        '${(flug.laengeMeter / 1000).toStringAsFixed(1)} km');

    // Die Kamera fliegt mit dem Tempo, das die Ansicht setzt.
    const tempo = 300.0;
    final dauer = flug.dauerBei(tempo);
    final sekunden = dauer.inMilliseconds / 1000;
    print('Flugdauer: ${sekunden.toStringAsFixed(1)} s '
        '(${(flug.laengeMeter / sekunden).round()} m/s)');

    // Was der Aufbau der Richtungstafel einmalig kostet: Sie entsteht
    // beim ersten Zugriff, also beim ersten Bild des Fluges.
    final tafeluhr = Stopwatch()..start();
    flug.richtungBei(flug.laengeMeter / 2);
    tafeluhr.stop();
    print('Richtungstafel: ${tafeluhr.elapsedMilliseconds} ms einmalig');
    final profiluhr = Stopwatch()..start();
    final profil = flug.hoehenprofil;
    profiluhr.stop();
    print('Hoehenprofil: ${profil.length} Punkte in '
        '${profiluhr.elapsedMicroseconds / 1000} ms einmalig');

    // In Bildschritten abtasten, so wie es auch gezeichnet wird.
    const bilderJeSekunde = 30;
    final bilder = (sekunden * bilderJeSekunde).round();
    final winkel = <double>[
      for (var i = 0; i < bilder; i++)
        flug.bei(i / (bilder - 1)).drehung,
    ];

    // Differenzen ueber den Sprung von +pi auf -pi hinweg.
    double diff(double a, double b) {
      var d = a - b;
      while (d > math.pi) {
        d -= 2 * math.pi;
      }
      while (d < -math.pi) {
        d += 2 * math.pi;
      }
      return d;
    }

    final raten = <double>[
      for (var i = 1; i < winkel.length; i++)
        (diff(winkel[i], winkel[i - 1])).abs() *
            180 /
            math.pi *
            bilderJeSekunde,
    ];
    raten.sort();
    final summe = raten.fold<double>(0, (a, b) => a + b) / bilderJeSekunde;
    double bei(double anteil) => raten[(raten.length * anteil).floor().clamp(0, raten.length - 1)];

    print('');
    print('Gesamtdrehung  ${summe.round()} Grad '
        '(${(summe / 360).toStringAsFixed(1)} volle Umdrehungen)');
    print('Drehrate       Median ${bei(0.5).toStringAsFixed(1)} Grad/s, '
        '90 % ${bei(0.9).toStringAsFixed(1)}, '
        '99 % ${bei(0.99).toStringAsFixed(1)}, '
        'hoechste ${raten.last.toStringAsFixed(1)}');
    final ueber = raten.where((r) => r > 60).length / raten.length * 100;
    print('ueber 60 Grad/s in ${ueber.toStringAsFixed(1)} % der Bilder');
  });
}
