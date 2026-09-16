/// **Wie oft die Flugkamera im Berg steht – an einer echten Spur.**
///
/// Kein Teil der Prüfsuite: Es braucht eine echte GPX-Spur, und die liegt
/// in einer Bibliothek, nicht im Repository.
///
/// Aus dem Erstlauf-Bericht (G12): „im Flug teilweise breiig oder es
/// fliegt unter dem Berg". Die Kamera kreist um den Blickpunkt und steht
/// bei flacher Neigung fast auf dessen Höhe – der Hang **hinter** dem
/// Weg ist dann höher als sie. Wie oft das auf einer Wanderung vorkommt,
/// sagt keine Meinung, sondern die Zählung.
///
/// Der Boden unter der Kamera wird hier aus dem Höhenprofil der Spur
/// selbst genommen: Die Kamera steht entgegen der Laufrichtung hinter
/// dem Wanderer, also ungefähr dort, wo er vorhin war. Das ist eine
/// Näherung – das echte Höhengitter kennt auch die Hänge neben dem Weg –
/// und sie unterschätzt das Problem eher, als es aufzubauschen.
///
/// ```sh
/// PV_SPUR=/tmp/spur.csv flutter test tool/messe_bodenabstand_test.dart
/// ```
library;

// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/gelaendeflug.dart';
import 'package:photo_vault/services/gelaendesicht.dart';

void main() {
  test('wie oft die Kamera unter dem Boden steht', () {
    final pfad = Platform.environment['PV_SPUR'];
    if (pfad == null) {
      markTestSkipped('PV_SPUR nicht gesetzt');
      return;
    }
    final breiten = <double>[];
    final laengen = <double>[];
    final hoehen = <double>[];
    for (final z in File(pfad).readAsLinesSync()) {
      final t = z.trim().split(',');
      if (t.length < 3) continue;
      final b = double.tryParse(t[0]);
      final l = double.tryParse(t[1]);
      final h = double.tryParse(t[2]);
      if (b == null || l == null) continue;
      breiten.add(b);
      laengen.add(l);
      hoehen.add(h ?? 0);
    }
    expect(breiten.length, greaterThan(100));

    final nord = breiten.reduce(math.max);
    final sued = breiten.reduce(math.min);
    final ost = laengen.reduce(math.max);
    final west = laengen.reduce(math.min);
    final mittlereHoehe =
        hoehen.reduce((a, b) => a + b) / hoehen.length;
    final breiteMeter = (ost - west) * meterJeGradLaenge((nord + sued) / 2);
    final hoeheMeter = (nord - sued) * meterJeGradBreite;
    final ausdehnung = math.max(breiteMeter, hoeheMeter);
    // Wie am Bildschirm: kurze Fensterkante 900, Faktor 1,1.
    const brennweite = 900 * 1.1;
    final entfernung = Gelaendeflug.flugabstand(
        ausdehnung: ausdehnung, kante: 96, brennweite: brennweite);

    // Meter entlang der Spur, damit „hinter mir" eine Strecke ist.
    final bisHier = <double>[0];
    for (var i = 1; i < breiten.length; i++) {
      final dx = (laengen[i] - laengen[i - 1]) *
          meterJeGradLaenge(breiten[i]);
      final dy = (breiten[i] - breiten[i - 1]) * meterJeGradBreite;
      bisHier.add(bisHier.last + math.sqrt(dx * dx + dy * dy));
    }
    final gesamt = bisHier.last;

    double bodenBei(double meter) {
      final m = meter.clamp(0.0, gesamt);
      var lo = 0, hi = bisHier.length - 1;
      while (lo < hi - 1) {
        final mi = (lo + hi) ~/ 2;
        if (bisHier[mi] <= m) {
          lo = mi;
        } else {
          hi = mi;
        }
      }
      return (hoehen[lo] - mittlereHoehe) * gelaendeUeberhoehung;
    }

    // Dieselben Neigungen, die die Bedienung zulässt.
    for (final neigung in [0.15, 0.5, 0.95, 1.45]) {
      var drunter = 0;
      // Von oben herunter: Mit 0 begonnen kaeme nie ein Wert darueber
      // heraus, und ein freier Flug meldete faelschlich "0 m Abstand".
      var tiefste = double.infinity;
      const schritte = 500;
      for (var i = 0; i <= schritte; i++) {
        final meter = gesamt * i / schritte;
        final kamera = Gelaendekamera(
          drehung: 0,
          neigung: neigung,
          entfernung: entfernung,
          brennweite: brennweite,
          mitte: const Offset(450, 300),
          blickpunkt: (x: 0.0, y: 0.0, z: bodenBei(meter)),
        );
        // Der Boden dort, wo die Kamera steht: hinter dem Wanderer.
        final boden = bodenBei(meter - entfernung);
        final frei = kamera.standort.z - boden;
        if (frei < gelaendeBodenabstand) drunter++;
        tiefste = math.min(tiefste, frei);
      }
      print('Neigung ${neigung.toStringAsFixed(2)}: '
          '$drunter von ${schritte + 1} Bildern unter dem Boden, '
          'schlimmstenfalls ${tiefste.toStringAsFixed(0)} m Abstand');
    }
    print('Flugabstand: ${entfernung.toStringAsFixed(0)} m, '
        'Ausdehnung ${ausdehnung.toStringAsFixed(0)} m, '
        'Strecke ${(gesamt / 1000).toStringAsFixed(1)} km');
  });
}
