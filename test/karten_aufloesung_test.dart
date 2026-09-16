import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/eigenkarte.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

void main() {
  group('der Massstab in Metern', () {
    test('die Umrechnung stimmt mit dem Mercator-Gitter ueberein', () {
      // Hundert Bildpunkte auf 52 Grad Breite. Nachgerechnet und zugleich
      // die Antwort auf „wie nah komme ich heran".
      expect(massstabMeter(14).round(), 588);
      expect(massstabMeter(15).round(), 294);
      expect(massstabMeter(16).round(), 147);
      expect(massstabMeter(17).round(), 74);
      expect(massstabMeter(19).round(), 18);
      expect(massstabMeter(20).round(), 9);
    });

    test('jede Stufe halbiert', () {
      for (var z = 3; z < 20; z++) {
        expect(massstabMeter(z) / massstabMeter(z + 1), closeTo(2.0, 1e-9));
      }
    });

    test('am Aequator ist es weiter als bei uns', () {
      expect(massstabMeter(15, breite: 0),
          greaterThan(massstabMeter(15, breite: 52)));
    });
  });

  group('die Aufloesung der Kacheln', () {
    /// Baut die Kachelschicht unter einer bestimmten Punktdichte und
    /// gibt zurueck, was flutter_map daraus gemacht hat.
    Future<TileLayer> schicht(WidgetTester tester,
        {required double dichte, required Kartenstil stil}) async {
      late TileLayer gebaut;
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(devicePixelRatio: dichte),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(builder: (context) {
            gebaut = buildMapTileLayer(context, stil: stil);
            return const SizedBox();
          }),
        ),
      ));
      return gebaut;
    }

    testWidgets('auf einem gewoehnlichen Bildschirm bleibt sie aus',
        (tester) async {
      final s = await schicht(tester, dichte: 1.0, stil: Kartenstil.dunkel);
      expect(s.resolvedRetinaMode, RetinaMode.disabled);
    });

    testWidgets('auf einem Retina-Bildschirm wird sie nachgebildet',
        (tester) async {
      // OpenStreetMap kennt keine @2x-Kacheln (nachgemessen: HTTP 400),
      // also holt flutter_map vier Kacheln der naechsttieferen Stufe.
      for (final stil in [Kartenstil.hell, Kartenstil.dunkel, Kartenstil.topo]) {
        final s = await schicht(tester, dichte: 2.0, stil: stil);
        expect(s.resolvedRetinaMode, RetinaMode.simulation, reason: stil.name);
      }
    });

    testWidgets('mit CARTO-Schluessel kommt sie vom Server', (tester) async {
      // Die CARTO-Adresse traegt `{r}` – dann fragt flutter_map die
      // doppelt aufgeloesten Kacheln direkt an, ohne Umweg und ohne den
      // Verlust einer Zoomstufe.
      addTearDown(() => setzeCartoSchluessel(null));
      setzeCartoSchluessel('probe');
      final s = await schicht(tester, dichte: 2.0, stil: Kartenstil.dunkel);
      expect(s.resolvedRetinaMode, RetinaMode.server);
    });

    testWidgets('eine eigene Quelle mit {r} ebenso', (tester) async {
      addTearDown(() => setzeEigeneKarte(null));
      setzeEigeneKarte(const Eigenkarte(
        name: 'Meine',
        url: 'https://beispiel.de/{z}/{x}/{y}{r}.png',
        nennung: '© Beispiel',
        zugestimmt: true,
      ));
      final s = await schicht(tester, dichte: 2.0, stil: Kartenstil.eigene);
      expect(s.resolvedRetinaMode, RetinaMode.server);
    });

    testWidgets('die nachgebildete Fassung kostet eine native Stufe',
        (tester) async {
      // Der Preis, und er steht hier, damit ihn niemand uebersieht:
      // flutter_map senkt maxNativeZoom um eins und rechnet einen
      // Zoomversatz dazu. Wer die Zahl anhebt, um das auszugleichen,
      // laesst Kacheln anfordern, die es nicht gibt (OSM z20 -> 400).
      final ohne = await schicht(tester, dichte: 1.0, stil: Kartenstil.dunkel);
      final mit = await schicht(tester, dichte: 2.0, stil: Kartenstil.dunkel);
      expect(ohne.maxNativeZoom, 19);
      expect(mit.maxNativeZoom, 18);
      expect(mit.zoomOffset, ohne.zoomOffset + 1);
    });
  });

  group('die Massstabsleiste', () {
    testWidgets('steht auf der flachen Karte', (tester) async {
      // Ohne sie liess sich ueber Kartentiefe nur in Zoomstufen reden.
      final quelle =
          File('lib/screens/map_screen.dart').readAsStringSync();
      expect(quelle.contains('Scalebar('), isTrue);
    });
  });
}
