// ignore_for_file: avoid_print
// Zeigt der Globus beim Heranzoomen wirklich die Luftbildkacheln (#9)?
//
// Im laufenden Programm, mit dem GPU-Renderer der Plattform und echten
// Kacheln von Esri: Globus über den Alpen bei Zoomstufe 3,5, einmal mit,
// einmal ohne Mosaik, gemessen wird die Schärfe der Bildmitte
// (Laplace-Varianz). Ohne Netz kommt kein Mosaik; dann meldet der Test das
// und prüft nichts.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_earth_globe/flutter_earth_globe.dart';
import 'package:flutter_earth_globe/flutter_earth_globe_controller.dart';
import 'package:flutter_earth_globe/globe_coordinates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photo_vault/services/globuskacheln.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Luftbildkacheln auf dem Globus', (tester) async {
    final regler = FlutterEarthGlobeController(
      surface: const AssetImage('assets/globe/8k_earth_daymap.jpg'),
      isRotating: false,
      zoom: 3.5,
      maxZoom: 6,
    );
    final rahmen = GlobalKey();
    const breite = 900.0, hoehe = 600.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: rahmen,
            child: SizedBox(
              width: breite,
              height: hoehe,
              child: FlutterEarthGlobe(controller: regler, radius: 250),
            ),
          ),
        ),
      ),
    );
    // Warten, bis die Textur da ist.
    await _warte(tester, () => regler.surface != null, sekunden: 15);
    expect(regler.surface, isNotNull, reason: 'Erdtextur nicht geladen');
    regler.focusOnCoordinates(
      const GlobeCoordinates(46.5, 8.0),
      animate: false,
    );
    await tester.pump(const Duration(milliseconds: 100));

    final dichte = tester.view.devicePixelRatio;
    final kacheln = Globuskacheln(
      regler,
      ansicht: () => (breite: breite, hoehe: hoehe, pixeldichte: dichte),
    );
    final uhr = Stopwatch()..start();
    await _warte(tester, () => kacheln.aktiv, sekunden: 30);
    if (!kacheln.aktiv) {
      final b = regler.blick.value;
      print(
        'GLOBUS Blick $b, Dichte $dichte, Fenster '
        '${b == null ? '-' : globusFenster(breitengrad: b.mitte.latitude, laengengrad: b.mitte.longitude, radius: b.radius, ansichtBreite: breite, ansichtHoehe: hoehe, pixeldichte: dichte)}',
      );
      print('GLOBUS keine Kacheln (kein Netz?) – nichts geprüft');
      kacheln.dispose();
      return;
    }
    print(
      'GLOBUS ${regler.detailBreite.toInt()}x${regler.detailHoehe.toInt()} '
      'Kacheln, Stufe ${regler.detailStufe}, nach ${uhr.elapsedMilliseconds} ms',
    );
    await tester.pump(const Duration(milliseconds: 100));
    final mit = await _schaerfe(tester, rahmen);

    regler.setzeDetail(null);
    await tester.pump(const Duration(milliseconds: 100));
    final ohne = await _schaerfe(tester, rahmen);
    print(
      'GLOBUS Schärfe der Mitte: mit ${mit.toStringAsFixed(1)}, '
      'ohne ${ohne.toStringAsFixed(1)}',
    );
    expect(mit, greaterThan(ohne * 1.5), reason: 'mit Kacheln nicht schärfer');
    kacheln.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// Wartet in echter Zeit, mit einem Bild dazwischen: `pump(Dauer)` allein
/// wartet im Integrationstest nicht, und der Kachellader rechnet mit
/// echten Zeitgebern und Netzantworten.
Future<void> _warte(
  WidgetTester tester,
  bool Function() fertig, {
  required int sekunden,
}) async {
  final uhr = Stopwatch()..start();
  while (!fertig() && uhr.elapsed.inSeconds < sekunden) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

/// Laplace-Varianz der Bildmitte (ein Viertel der Fläche) – je höher,
/// desto mehr feine Struktur.
Future<double> _schaerfe(WidgetTester tester, GlobalKey rahmen) async {
  final grenze =
      rahmen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bild = (await tester.runAsync(() => grenze.toImage()))!;
  final roh = (await tester.runAsync(
    () => bild.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final w = bild.width, h = bild.height;
  double hell(int x, int y) {
    final i = (y * w + x) * 4;
    return 0.299 * roh.getUint8(i) +
        0.587 * roh.getUint8(i + 1) +
        0.114 * roh.getUint8(i + 2);
  }

  var summe = 0.0, quadrate = 0.0, n = 0;
  for (var y = h * 3 ~/ 8; y < h * 5 ~/ 8; y++) {
    for (var x = w * 3 ~/ 8; x < w * 5 ~/ 8; x++) {
      final l =
          4 * hell(x, y) -
          hell(x - 1, y) -
          hell(x + 1, y) -
          hell(x, y - 1) -
          hell(x, y + 1);
      summe += l;
      quadrate += l * l;
      n++;
    }
  }
  final mittel = summe / n;
  return quadrate / n - mittel * mittel;
}
