// **Wo die Zeit einer Videoausgabe wirklich hingeht.**
//
// `messe_videobild_test.dart` hat den festen Preis je Bild gemessen:
// 4,4 ms bei 1920x1080 fürs Rastern und Herausholen. Das kann es also
// nicht sein, wenn eine Ausgabe Minuten dauert.
//
// Der Verdacht ist das Warten: Vor jedem Bild sagt die Ausgabe dem Lader,
// welche Blöcke darin stehen, und wartet dann **bis zu 700 ms**, dass er
// sie bringt. Am Bildschirm holt er nach, während man fliegt; ein Video
// hat kein „ein Bild später". Bei zweitausend Bildern ist der Unterschied
// zwischen 5 ms und 700 ms Wartezeit der zwischen zwanzig Sekunden und
// zwanzig Minuten.
//
// Gemessen mit einem gestellten Netz, das SOFORT antwortet – die
// Wartezeit hier ist also die untere Schranke: Was ein echter Server
// braucht, kommt oben drauf.
//
//   flutter test tool/messe_videolauf_test.dart
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show DisabledMapCachingProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photo_vault/services/blocktexturen.dart';
import 'package:photo_vault/services/gelaendeebenen.dart';
import 'package:photo_vault/services/gelaendekacheln.dart';
import 'package:photo_vault/services/gelaendesicht.dart';
import 'package:photo_vault/widgets/gelaende.dart';

Future<Uint8List> _kachel() async {
  const kante = 256;
  final rgba = Uint8List(kante * kante * 4);
  for (var i = 0; i < kante * kante; i++) {
    rgba[i * 4 + 1] = 140;
    rgba[i * 4 + 3] = 255;
  }
  final fertig = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      rgba, kante, kante, ui.PixelFormat.rgba8888, fertig.complete);
  final bild = await fertig.future;
  final daten = await bild.toByteData(format: ui.ImageByteFormat.png);
  bild.dispose();
  return daten!.buffer.asUint8List();
}

void main() {
  testWidgets('Warten je Bild', (tester) async {
    await tester.runAsync(() async {
      final kachel = await _kachel();
      var abrufe = 0;
      final netz = MockClient((_) async {
        abrufe++;
        return http.Response.bytes(kachel, 200);
      });

      const n = 220;
      final hoehen = Float32List(n * n);
      for (var y = 0; y < n; y++) {
        for (var x = 0; x < n; x++) {
          hoehen[y * n + x] = 400 + 220 * math.sin(x / 9.0) * math.cos(y / 7.0);
        }
      }
      final gitter = Hoehengitter(
        spalten: n, zeilen: n, hoehen: hoehen,
        nord: 51.90, sued: 51.80, west: 10.55, ost: 10.71,
      );
      final netzDreiecke = baueNetz(gitter, kante: 96, grundstufe: 15);
      final lader = Blocktexturlader(
        karte: const Gelaendekarte(),
        hoehen: gitter,
        grundstufe: netzDreiecke.grundstufe,
        netz: netz,
        speicher: const DisabledMapCachingProvider(),
        hoechstensBytes:
            int.tryParse(Platform.environment['PV_BUDGET'] ?? '') ??
                blocktexturSpeicher,
      );
      addTearDown(lader.schliessen);

      const flaeche = Size(1920, 1080);
      const bilder = 40;
      var warten = 0, scharf = 0, gesamt = 0, scharf24 = 0, gesamt24 = 0;
      final uhr = Stopwatch()..start();
      for (var i = 0; i < bilder; i++) {
        final t = i / (bilder - 1);
        final kamera = Gelaendekamera(
          drehung: t * math.pi,
          neigung: 0.35,
          entfernung: 2600,
          brennweite: 1000,
          mitte: const Offset(960, 670),
          blickpunkt: (
            x: -2000 + 4000 * t,
            y: -1500 + 3000 * t,
            z: 0,
          ),
        );
        lader.brauche(bloeckeImBild(netzDreiecke, kamera, flaeche));
        final w = Stopwatch()..start();
        if (Platform.environment['PV_ALT'] != null) {
          await lader.ruhe(hoechstens: const Duration(milliseconds: 700));
        } else {
          await lader.ruheNah(hoechstens: const Duration(milliseconds: 300));
        }
        warten += w.elapsedMicroseconds;
        final nah = lader.schaerfeNah(24);
        scharf24 += nah.scharf;
        gesamt24 += nah.gesamt;
        final sch = lader.schaerfeNah(60);
        scharf += sch.scharf;
        gesamt += sch.gesamt;
      }
      uhr.stop();
      print('$bilder Bilder: ${uhr.elapsedMilliseconds} ms gesamt, '
          'davon ${(warten / 1000).round()} ms Warten '
          '(${(warten / bilder / 1000).toStringAsFixed(0)} ms je Bild)');
      print('$abrufe Kachelabrufe, ${lader.gehalten} Texturen im Vorrat, '
          '${(lader.belegt / 1024 / 1024).toStringAsFixed(0)} MB');
      print('auf Zielstufe: die 24 naechsten '
          '${(scharf24 / gesamt24 * 100).toStringAsFixed(0)} %, '
          'die 60 naechsten ${(scharf / gesamt * 100).toStringAsFixed(0)} %');
      print('hochgerechnet auf 1800 Bilder: '
          '${(warten / bilder * 1800 / 1e6).toStringAsFixed(0)} s allein Warten');
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}
