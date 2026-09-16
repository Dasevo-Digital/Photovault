@Tags(['netz'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:photo_vault/widgets/mini_location_map.dart';

/// Sonde: Wie viel der Karte bleibt grau?
///
/// Läuft auf Zuruf:
///   flutter test --tags netz --run-skipped test/karten_kacheln_netz_probe_test.dart
///
/// Gemessen wird, was der Betrachter sieht: der Anteil der Fläche, der
/// noch die Hintergrundfarbe von flutter_map (0xFFE0E0E0) trägt, statt
/// eine Kachel.
const _hintergrund = 0xFFE0E0E0;

Future<double> _grauAnteil(WidgetTester tester) async {
  final grenze = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('rahmen')));
  final bild = await grenze.toImage();
  final daten = await bild.toByteData(format: ui.ImageByteFormat.rawRgba);
  final b = daten!.buffer.asUint8List();
  var grau = 0;
  final gesamt = b.length ~/ 4;
  for (var i = 0; i < b.length; i += 4) {
    final farbe = 0xFF000000 | (b[i] << 16) | (b[i + 1] << 8) | b[i + 2];
    if (farbe == _hintergrund) grau++;
  }
  bild.dispose();
  return grau / gesamt;
}

Future<double> _probe(
  WidgetTester tester,
  Kartenstil stil, {
  required double zoom,
  required Duration warten,
}) async {
  late double anteil;
  await tester.runAsync(() async {
    await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(
        key: const ValueKey('rahmen'),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: const ll.LatLng(50.0, 14.0),
            initialZoom: zoom,
            maxZoom: stil.hoechsteAnzeigeStufe.toDouble(),
          ),
          children: [Kachelschicht(stil: stil)],
        ),
      ),
    ));
    final ende = DateTime.now().add(warten);
    while (DateTime.now().isBefore(ende)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }
    anteil = await _grauAnteil(tester);
  });
  return anteil;
}

void main() {
  late Directory speicher;

  setUp(() async {
    HttpOverrides.global = null;
    speicher = await Directory.systemTemp.createTemp('kachelsonde');
    // Ohne eigenen Pfad fragt der Speicher das Betriebssystem – im Test
    // gibt es dafür keinen Kanal, und dann wartet jede Kachel ewig.
    BuiltInMapCachingProvider.getOrCreateInstance(
      cacheDirectory: speicher.path,
      overrideFreshAge: kartenKachelFrische,
      maxCacheSize: kartenSpeicherGrenze,
    );
  });

  tearDown(() async {
    await BuiltInMapCachingProvider.getOrCreateInstance().destroy();
    if (speicher.existsSync()) speicher.deleteSync(recursive: true);
  });

  testWidgets('wie viel bleibt grau?', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final (stil, zoom) in [
      (Kartenstil.hell, 7.0),
      (Kartenstil.dunkel, 7.0),
      (Kartenstil.topo, 7.0),
      (Kartenstil.dunkel, 8.0),
      // Bis zur Strassenebene, und darueber hinaus: Genau davon hiess
      // es, es sei „nicht moeglich".
      (Kartenstil.hell, 14.0),
      (Kartenstil.hell, 17.0),
      (Kartenstil.hell, 19.0),
      (Kartenstil.dunkel, 19.0),
      (Kartenstil.topo, 17.0),
    ]) {
      final anteil = await _probe(tester, stil,
          zoom: zoom, warten: const Duration(seconds: 12));
      // ignore: avoid_print
      print('${stil.name} z$zoom: ${(anteil * 100).toStringAsFixed(1)} % grau');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
