import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show ByteData;
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/screens/map_screen.dart';

/// Wo sitzt die sichtbare Tinte einer Glyphe in ihrem Kasten?
///
/// Zeichnet das Widget in ein Bild und sucht die äußersten dunklen Pixel.
/// [feinheit] vervierfacht die Auflösung, damit auch Bruchteile eines
/// Punktes messbar sind.
Future<({double oben, double unten, double links, double rechts, Size kasten})>
    _tinte(WidgetTester tester, Widget kind, {double feinheit = 4}) async {
  final schluessel = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    home: Center(
      child: RepaintBoundary(
        key: schluessel,
        child: ColoredBox(color: Colors.white, child: kind),
      ),
    ),
  ));
  await tester.pumpAndSettle();

  final grenze =
      schluessel.currentContext!.findRenderObject() as RenderRepaintBoundary;
  // toImage und toByteData sind echte Ein-/Ausgabe. Ohne runAsync wartet
  // der Test auf eine Uhr, die im Testrahmen niemand weiterstellt – und
  // zwar wortlos.
  late final ui.Image bild;
  ByteData? daten;
  await tester.runAsync(() async {
    bild = await grenze.toImage(pixelRatio: feinheit);
    daten = await bild.toByteData(format: ui.ImageByteFormat.rawRgba);
  });

  final breite = bild.width, hoehe = bild.height;
  double? oben, unten, links, rechts;
  for (var y = 0; y < hoehe; y++) {
    for (var x = 0; x < breite; x++) {
      if (daten!.getUint8((y * breite + x) * 4) >= 128) continue;
      oben ??= y.toDouble();
      unten = y.toDouble();
      if (links == null || x < links) links = x.toDouble();
      if (rechts == null || x > rechts) rechts = x.toDouble();
    }
  }
  return (
    oben: oben! / feinheit,
    unten: unten! / feinheit,
    links: links! / feinheit,
    rechts: rechts! / feinheit,
    kasten: Size(breite / feinheit, hoehe / feinheit),
  );
}

void main() {
  // Die Kugel selbst lässt sich im Test nicht zeichnen – ohne GPU lädt der
  // Shader nicht, und dann rendert die Bibliothek überhaupt keine Punkte.
  // Prüfbar ist aber das, worauf es ankommt: dass die Zahl, mit der wir
  // den Pin zurechtrücken, wirklich der Glyphe entspricht. Ändert sich die
  // Symbolschrift, fällt dieser Test und nicht erst der Nutzer, der seinen
  // Pin im Meer sucht.
  testWidgets('die Spitze des Pins sitzt dort, wo pinSpitzeUeberKante sagt',
      (tester) async {
    final t = await _tinte(
      tester,
      const Icon(Icons.location_pin, color: Colors.black, size: pinGroesse),
    );

    expect(t.kasten, const Size(pinGroesse, pinGroesse));
    expect(t.kasten.height - t.unten, closeTo(pinSpitzeUeberKante, 0.3),
        reason: 'Die Glyphe endet bei ${t.unten} von ${t.kasten.height} – '
            'pinSpitzeUeberKante muss diesen Abstand abbilden, sonst zeigt '
            'der Pin nach Norden an seinem Ort vorbei.');
  });

  testWidgets('im richtig breiten Kasten steht der Pin waagerecht mittig',
      (tester) async {
    final t = await _tinte(
      tester,
      const Icon(Icons.location_pin, color: Colors.black, size: pinGroesse),
    );
    final mitte = (t.links + t.rechts) / 2;
    expect(mitte, closeTo(t.kasten.width / 2, 0.3),
        reason: 'Ein zu schmaler Kasten quetscht die Glyphe aus der Mitte – '
            'genau das war vorher der Fall (30 statt 34 Punkte).');
  });

  testWidgets('ein zu schmaler Kasten verschiebt die Glyphe messbar',
      (tester) async {
    // Die Gegenprobe: der alte Zustand. Ohne sie stünde nur die
    // Behauptung da, die Breite habe etwas ausgemacht.
    final t = await _tinte(
      tester,
      const SizedBox(
        width: 30,
        height: pinGroesse,
        child: Icon(Icons.location_pin, color: Colors.black, size: pinGroesse),
      ),
    );
    final mitte = (t.links + t.rechts) / 2;
    expect((mitte - t.kasten.width / 2).abs(), greaterThan(1.0));
  });
}
