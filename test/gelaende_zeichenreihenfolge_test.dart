/// **Nahes Gelände deckt fernes zu – in jeder Blickrichtung.**
///
/// `drawVertices` kennt keinen Tiefenpuffer. Der Maler verliess sich
/// deshalb darauf, dass „die Dreiecke in der Reihenfolge des Gitters
/// liegen, und die läuft von Norden nach Süden, also von hinten nach
/// vorn". Das gilt nur, solange die Kamera nach Norden sieht – die
/// Flugkamera dreht sich aber in Laufrichtung ([Gelaendeflug.drehung]).
///
/// Wer nach Süden wandert, sah deshalb fernes Gelände über nahem. Am
/// gerenderten Bild war es ein breites Band quer durch die Landschaft.
///
/// **Geprüft wird an den Bildpunkten.** Zwei gleich hohe Rücken, einer im
/// Norden und einer im Süden, dazu eine Textur, die den Norden rot und
/// den Süden blau färbt. Die Kamera steht ausserhalb von beiden, so dass
/// der nähere den ferneren verdecken muss. Welche Farbe im Bild steht,
/// sagt, welcher gewonnen hat.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/gelaendekacheln.dart';
import 'package:photo_vault/services/gelaendesicht.dart';
import 'package:photo_vault/widgets/gelaende.dart';

const int _n = 160;

/// Flaches Land mit zwei gleich hohen Rücken: Zeile 40 liegt im Norden,
/// Zeile 120 im Süden.
Hoehengitter _zweiRuecken() {
  final h = Float32List(_n * _n);
  for (var y = 0; y < _n; y++) {
    for (var x = 0; x < _n; x++) {
      var m = 300.0;
      if ((y - 40).abs() <= 10) m = 800;
      if ((y - 120).abs() <= 10) m = 800;
      h[y * _n + x] = m;
    }
  }
  return Hoehengitter(
    spalten: _n, zeilen: _n, hoehen: h,
    nord: 51.90, sued: 51.80, west: 10.55, ost: 10.71,
  );
}

/// Norden rot, Süden blau – Texturzeile 0 liegt im Norden.
Future<ui.Image> _rotBlau() {
  final daten = Uint8List(4 * 8);
  for (var i = 0; i < 8; i++) {
    final rot = i < 4;
    daten[i * 4] = rot ? 255 : 0;
    daten[i * 4 + 2] = rot ? 0 : 255;
    daten[i * 4 + 3] = 255;
  }
  final fertig = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      daten, 1, 8, ui.PixelFormat.rgba8888, fertig.complete);
  return fertig.future;
}

void main() {
  test('jeder Block laesst sich ueberhaupt ordnen', () {
    // Flutter verweist auf Eckpunkte mit sechzehn Bit. Waere ein Block
    // groesser, schnitte `Uint16List` die Verweise stillschweigend ab -
    // Dreiecke aus dem Nichts, ohne Fehlermeldung.
    //
    // Seit die Landschaft in Bloecke zerfaellt, ist das keine Frage der
    // Gitterkante mehr, sondern eine je Block: Jeder traegt seine eigene
    // Reihenfolge, und die Grenze gilt fuer jeden einzeln. Der Test
    // haelt fest, dass keine Einstellung sie erreicht.
    for (final kante in [gelaendeGitterkante, 160, 256]) {
      final netz = baueNetz(_zweiRuecken(), kante: kante);
      var groesster = 0;
      for (final b in netz.bloecke) {
        if (b.eckenzahl > groesster) groesster = b.eckenzahl;
      }
      expect(groesster, lessThanOrEqualTo(65536),
          reason: 'Kante $kante ergibt einen Block mit $groesster Eckpunkten');
    }
  });

  testWidgets('der nahe Ruecken deckt den fernen zu', (tester) async {
    tester.view.physicalSize = const Size(600, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final netz = baueNetz(_zweiRuecken(), grundfarbe: const Color(0xFFFFFFFF));

    // **Beide Ruecken muessen VOR der Kamera liegen.** Der erste Anlauf
    // setzte den Blickpunkt zwischen sie - dann lag je einer hinter der
    // Kamera, und beide Bilder waren richtig, ohne dass die Frage
    // ueberhaupt gestellt war. Die Ruecken stehen bei y = +2750 (Norden)
    // und y = -2750 (Sueden).
    Gelaendekamera kamera(double drehung, double y) => Gelaendekamera(
          drehung: drehung,
          neigung: 0.10,
          entfernung: 2500,
          brennweite: 700,
          mitte: const Offset(300, 200),
          blickpunkt: (x: 0.0, y: y, z: -400.0),
        );

    // `toImage` ist echte Arbeit ausserhalb der Testbuehne: ohne
    // `runAsync` kehrt das `await` nie zurueck und der Lauf haengt
    // wortlos bis zur Zeitgrenze.
    await tester.runAsync(() async {
      final textur = await _rotBlau();
      addTearDown(textur.dispose);

      for (final fall in [
        // Blick nach Norden, Kamera im Sueden von beiden: naeher ist der
        // suedliche Ruecken - blau.
        (name: 'nordwaerts', drehung: 0.0, y: -4200.0, blauGewinnt: true),
        // Blick nach Sueden, Kamera im Norden: naeher ist der noerdliche
        // Ruecken - rot.
        (name: 'suedwaerts', drehung: math.pi, y: 4200.0, blauGewinnt: false),
      ]) {
        final sammler = ui.PictureRecorder();
        Gelaendemaler(
          netz: netz,
          kamera: kamera(fall.drehung, fall.y),
          karte: textur,
          spur: const [],
          spurfarbe: const Color(0xFFFF7043),
        ).paint(ui.Canvas(sammler), const Size(600, 400));
        final bild = await sammler.endRecording().toImage(600, 400);
        final roh = await bild.toByteData(format: ui.ImageByteFormat.rawRgba);
        bild.dispose();
        final punkte = roh!.buffer.asUint8List();

        var rot = 0, blau = 0;
        for (var zeile = 120; zeile < 380; zeile += 10) {
          for (var x = 60; x < 540; x += 4) {
            final i = (zeile * 600 + x) * 4;
            if (punkte[i] > punkte[i + 2] + 12) rot++;
            if (punkte[i + 2] > punkte[i] + 12) blau++;
          }
        }
        final fremd = fall.blauGewinnt ? rot : blau;
        final eigen = fall.blauGewinnt ? blau : rot;
        expect(eigen, greaterThan(0),
            reason: '${fall.name}: der nahe Ruecken ist gar nicht zu sehen - '
                'dann prueft dieser Test nichts');
        expect(fremd, 0,
            reason: '${fall.name}: der FERNE Ruecken steht in $fremd von '
                '${fremd + eigen} Proben ueber dem nahen');
      }
    });
  });
}
