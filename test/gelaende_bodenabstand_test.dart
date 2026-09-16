import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/gelaendesicht.dart';

/// **„Es fliegt unter dem Berg."**
///
/// Aus dem Erstlauf-Bericht (G12). Die Kamera kreist um ihren
/// Blickpunkt; bei flacher Neigung steht sie fast auf dessen Hoehe - und
/// damit innerhalb des Hangs, der hinter dem Weg ansteigt. Gezeichnet
/// wird dann die Landschaft von innen.
void main() {
  Gelaendekamera kamera({double neigung = 0.2, double entfernung = 1000}) =>
      Gelaendekamera(
        drehung: 0,
        neigung: neigung,
        entfernung: entfernung,
        brennweite: 800,
        mitte: const Offset(400, 300),
        blickpunkt: (x: 0.0, y: 0.0, z: 0.0),
      );

  test('ueber flachem Land bleibt alles, wie es ist', () {
    final k = kamera();
    final gehoben = ueberDemBoden(k, hoeheBei: (x, y) => -500);
    expect(gehoben.neigung, k.neigung);
  });

  test('ausserhalb des Hoehengitters bleibt alles, wie es ist', () {
    final k = kamera();
    final gehoben = ueberDemBoden(k, hoeheBei: (x, y) => null);
    expect(gehoben.neigung, k.neigung);
  });

  test('steht die Kamera im Berg, wird angehoben', () {
    final k = kamera();
    // Der Boden liegt ueberall auf 0; bei Neigung 0,2 sitzt die Kamera
    // rund 199 Meter hoch - zu wenig fuer den geforderten Abstand von
    // 300.
    final gehoben = ueberDemBoden(k, hoeheBei: (x, y) => 0, abstand: 300);
    expect(gehoben.neigung, greaterThan(k.neigung));
    final wo = gehoben.standort;
    expect(wo.z, greaterThanOrEqualTo(300));
  });

  test('angehoben wird nur so weit wie noetig', () {
    final k = kamera();
    final gehoben = ueberDemBoden(k, hoeheBei: (x, y) => 0, abstand: 300);
    // Die gefundene Neigung ist knapp: Eine Spur flacher, und der
    // Abstand waere unterschritten. So bleibt der Flug so flach wie
    // moeglich.
    final knapper = gehoben.kopieMit(neigung: gehoben.neigung - 0.05);
    expect(knapper.standort.z, lessThan(300));
  });

  test('reicht auch die steilste Neigung nicht, kommt sie trotzdem', () {
    final k = kamera();
    // Ein Boden weit ueber allem, was die Kamera erreichen kann.
    final gehoben =
        ueberDemBoden(k, hoeheBei: (x, y) => 100000, abstand: 50);
    expect(gehoben.neigung, closeTo(1.45, 1e-9));
  });

  test('nur der Boden UNTER der Kamera zaehlt, nicht der am Blickpunkt', () {
    // Der Berg steht dort, wo die Kamera hinschaut - nicht dort, wo sie
    // steht. Angehoben werden muss deshalb nichts.
    final k = kamera();
    final gehoben = ueberDemBoden(
      k,
      hoeheBei: (x, y) => math.sqrt(x * x + y * y) < 100 ? 5000.0 : -500.0,
      abstand: 50,
    );
    expect(gehoben.neigung, k.neigung);
  });
}
