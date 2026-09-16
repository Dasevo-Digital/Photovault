// Die Landschaft zerfällt in Blöcke – und darf dabei nicht auseinander-
// fallen.
//
// Drei Fragen, die eine Blockeinteilung neu aufwirft und die es vorher
// nicht gab:
//
// 1. **Klaffen die Blöcke?** Zwei Nachbarn teilen sich eine Kante. Wenn
//    ihre Eckpunkte dort auch nur um einen Zentimeter auseinanderliegen,
//    scheint der Himmel durch einen Riss quer durch die Landschaft.
// 2. **Bleibt die Textur im Block?** Zeigt eine Texturstelle über den
//    Rand des Blockbildes hinaus, zieht `TileMode.clamp` dort den
//    letzten Bildpunkt in die Länge – ein Schmierstreifen entlang der
//    Kante.
// 3. **Liegt die Übersichtskarte richtig darauf?** Solange ein Block
//    seine eigene Textur nicht hat, schneidet er sich sein Stück aus der
//    Übersicht heraus. Rechnet er dabei falsch, trägt jeder Block die
//    ganze Karte statt seines Ausschnitts – und das sieht man nur am
//    gerenderten Bild.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/gelaendekacheln.dart';
import 'package:photo_vault/services/gelaendesicht.dart';
import 'package:photo_vault/widgets/gelaende.dart';

/// Ein Ausschnitt im Harz, gross genug für mehrere Blockspalten und
/// -zeilen – und mit Bergen, damit die Höhe an den Blockgrenzen
/// überhaupt etwas zu tun bekommt.
Hoehengitter _gitter({int n = 120}) {
  final h = Float32List(n * n);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      h[y * n + x] = 400 +
          260 * math.sin(x / 11.0) * math.cos(y / 9.0) +
          80 * math.sin((x + y) / 17.0);
    }
  }
  return Hoehengitter(
    spalten: n,
    zeilen: n,
    hoehen: h,
    nord: 51.86,
    sued: 51.82,
    west: 10.60,
    ost: 10.66,
  );
}

/// Ein Bild mit einem waagerechten Verlauf: links reines Rot, rechts
/// reines Blau.
///
/// Der Verlauf ist die Probe: Wenn ein Block sich sein Stück richtig aus
/// der Übersicht schneidet, steht im linken Teil der Landschaft Rot und
/// im rechten Blau. Rechnet er falsch, trägt **jeder** Block den ganzen
/// Verlauf, und Rot und Blau wechseln sich über das Bild ab.
Future<ui.Image> _verlauf({int breite = 256, int hoehe = 64}) {
  final daten = Uint8List(breite * hoehe * 4);
  for (var y = 0; y < hoehe; y++) {
    for (var x = 0; x < breite; x++) {
      final i = (y * breite + x) * 4;
      final t = x / (breite - 1);
      daten[i] = ((1 - t) * 255).round();
      daten[i + 2] = (t * 255).round();
      daten[i + 3] = 255;
    }
  }
  final fertig = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      daten, breite, hoehe, ui.PixelFormat.rgba8888, fertig.complete);
  return fertig.future;
}

void main() {
  test('zwei Nachbarn treffen sich auf ihrer gemeinsamen Kante genau', () {
    final netz = baueNetz(_gitter());
    expect(netz.bloecke.length, greaterThan(4),
        reason: 'ohne mehrere Blöcke prüft dieser Test nichts');

    /// Die Eckpunkte eines Blocks, die auf einer seiner Kanten liegen –
    /// gerundet auf einen Millimeter, damit die Suche nicht an der
    /// letzten Bitstelle scheitert, aber jeder sichtbare Riss auffällt.
    ///
    /// **Nicht „teilen sie irgendeinen Punkt", sondern „stimmen sie auf
    /// der ganzen Kante überein".** Der erste Anlauf fragte nur nach
    /// einem gemeinsamen Punkt – und den haben zwei Nachbarn schon dann,
    /// wenn nur ihre Ecken zusammenfallen und die Kante dazwischen
    /// verschieden unterteilt ist. Die Gegenprobe (eine Masche mehr in
    /// jeder zweiten Spalte) ging damit durch.
    Set<String> aufKante(Blocknetz b, {double? beiX, double? beiY}) {
      final aus = <String>{};
      for (var i = 0; i < b.eckenzahl; i++) {
        final x = b.ecken[i * 3];
        final y = b.ecken[i * 3 + 1];
        final z = b.ecken[i * 3 + 2];
        if (beiX != null && (x - beiX).abs() > 0.001) continue;
        if (beiY != null && (y - beiY).abs() > 0.001) continue;
        aus.add('${(x * 1000).round()}/${(y * 1000).round()}/'
            '${(z * 1000).round()}');
      }
      return aus;
    }

    final nachOrt = {
      for (final b in netz.bloecke) '${b.block.spalte}/${b.block.zeile}': b,
    };
    var geprueft = 0;
    for (final b in netz.bloecke) {
      final rechts = nachOrt['${b.block.spalte + 1}/${b.block.zeile}'];
      if (rechts != null) {
        expect(aufKante(b, beiX: b.ostM), aufKante(rechts, beiX: rechts.westM),
            reason: '${b.block} und ${rechts.block} stimmen auf ihrer '
                'gemeinsamen Kante nicht überein – dort klafft die '
                'Landschaft');
        expect(aufKante(b, beiX: b.ostM), isNotEmpty);
        geprueft++;
      }
      final unten = nachOrt['${b.block.spalte}/${b.block.zeile + 1}'];
      if (unten != null) {
        expect(aufKante(b, beiY: b.suedM), aufKante(unten, beiY: unten.nordM),
            reason: '${b.block} und ${unten.block} stimmen auf ihrer '
                'gemeinsamen Kante nicht überein');
        expect(aufKante(b, beiY: b.suedM), isNotEmpty);
        geprueft++;
      }
    }
    expect(geprueft, greaterThan(4));
  });

  test('keine Texturstelle zeigt über ihren Block hinaus', () {
    // Die Gegenprobe zu [baueNetz]: Läge das Gitter gleichmässig über den
    // Ausschnitt statt an den Blockgrenzen, ginge eine Masche quer über
    // eine Kante und ihre Stellen lägen ausserhalb von 0..1.
    final netz = baueNetz(_gitter());
    var kleinste = double.infinity;
    var groesste = double.negativeInfinity;
    for (final b in netz.bloecke) {
      for (final t in b.texturstellen) {
        if (t < kleinste) kleinste = t;
        if (t > groesste) groesste = t;
      }
    }
    expect(kleinste, greaterThanOrEqualTo(-1e-9));
    expect(groesste, lessThanOrEqualTo(1 + 1e-9));
    // Und die Blöcke füllen sich wirklich aus, statt in einer Ecke zu
    // kleben.
    expect(groesste, greaterThan(0.99));
  });

  test('was hinter der Kamera liegt, wird gar nicht erst gezeichnet', () {
    // Jeder Block ist ein eigener Zeichenzug; bei 900 Blöcken kostete
    // das Aufzeichnen eines Bildes 7,02 ms statt 1,27 ms bei sechs.
    // Deshalb prüft der Maler vorher, ob ein Block überhaupt ins Bild
    // ragt.
    final netz = baueNetz(_gitter());
    Gelaendemaler maler(double drehung) => Gelaendemaler(
          netz: netz,
          kamera: Gelaendekamera(
            drehung: drehung,
            neigung: 0.12,
            entfernung: 900,
            brennweite: 900,
            mitte: const Offset(400, 300),
          ),
          spur: const [],
          spurfarbe: const Color(0xFFFF0000),
        );
    const flaeche = Size(800, 600);
    final flach =
        bloeckeAnzahlImBild(netz, maler(0).kamera, flaeche);
    expect(flach, lessThan(netz.bloecke.length),
        reason: 'aus Augenhöhe liegt die halbe Landschaft hinter der Kamera');

    // Gegenprobe: von weit oben ist alles zu sehen.
    final vonOben = bloeckeAnzahlImBild(
      netz,
      const Gelaendekamera(
        drehung: 0,
        neigung: math.pi / 2,
        entfernung: 20000,
        brennweite: 900,
        mitte: Offset(400, 300),
      ),
      flaeche,
    );
    expect(vonOben, netz.bloecke.length);
  });

  testWidgets('die Übersichtskarte liegt richtig auf den Blöcken',
      (tester) async {
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Ein flaches Gelände, senkrecht von oben: Dann ist das Bild die
    // Karte, und nur die Karte.
    final flach = Hoehengitter(
      spalten: 8,
      zeilen: 8,
      hoehen: Float32List(8 * 8)..fillRange(0, 64, 400),
      nord: 51.86,
      sued: 51.82,
      west: 10.60,
      ost: 10.66,
    );
    final netz = baueNetz(flach, grundfarbe: const Color(0xFFFFFFFF));
    expect(netz.bloecke.length, greaterThan(4));

    await tester.runAsync(() async {
      final karte = await _verlauf();
      addTearDown(karte.dispose);

      final maler = Gelaendemaler(
        netz: netz,
        kamera: const Gelaendekamera(
          drehung: 0,
          neigung: math.pi / 2,
          entfernung: 6000,
          brennweite: 440,
          mitte: Offset(200, 200),
        ),
        spur: const [],
        spurfarbe: const Color(0xFFFF0000),
        karte: karte,
      );
      final sammler = ui.PictureRecorder();
      maler.paint(ui.Canvas(sammler), const Size(400, 400));
      final bild = await sammler.endRecording().toImage(400, 400);
      addTearDown(bild.dispose);
      final roh = await bild.toByteData(format: ui.ImageByteFormat.rawRgba);
      final px = roh!.buffer.asUint8List();

      ({int rot, int blau}) zaehle(int vonX, int bisX) {
        var rot = 0;
        var blau = 0;
        for (var y = 150; y < 250; y++) {
          for (var x = vonX; x < bisX; x++) {
            final i = (y * 400 + x) * 4;
            if (px[i + 3] < 200) continue;
            if (px[i] > px[i + 2] + 40) rot++;
            if (px[i + 2] > px[i] + 40) blau++;
          }
        }
        return (rot: rot, blau: blau);
      }

      final links = zaehle(120, 170);
      final rechts = zaehle(230, 280);
      expect(links.rot, greaterThan(links.blau * 5),
          reason: 'links muss die rote Seite der Karte stehen – '
              'rot ${links.rot}, blau ${links.blau}');
      expect(rechts.blau, greaterThan(rechts.rot * 5),
          reason: 'rechts muss die blaue Seite stehen – '
              'rot ${rechts.rot}, blau ${rechts.blau}');
    });
  });
}
