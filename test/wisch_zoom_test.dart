import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:photo_vault/widgets/wisch_zoom.dart';

/// Zoomen mit einer Maus ohne Rad.
///
/// Eine Magic Mouse hat eine Tastfläche statt eines Rades; macOS meldet
/// ein Wischen darauf wie ein Trackpad. flutter_map und Flutters
/// [InteractiveViewer] behandeln solche Eingaben ab Werk als
/// **Verschieben**. An der nackten Karte nachgemessen, fünf
/// Wischschritte nach oben:
///
/// ```
/// Zoom:  8.0 -> 8.0     (unverändert)
/// Mitte: 51,0 -> 50,72  (verschoben)
/// ```
void main() {
  group('Die Rechnung', () {
    test('nach oben wischen vergroessert', () {
      // In Flutter waechst y nach unten; ein Wisch nach oben liefert
      // also einen negativen Weg.
      expect(wischZoomStufe(startZoom: 8, wischWegY: -100), 9);
    });

    test('nach unten wischen verkleinert', () {
      expect(wischZoomStufe(startZoom: 8, wischWegY: 100), 7);
    });

    test('kein Weg, kein Zoomwechsel', () {
      expect(wischZoomStufe(startZoom: 8, wischWegY: 0), 8);
    });

    test('die Grenzen halten', () {
      expect(
          wischZoomStufe(
              startZoom: 8, wischWegY: -10000, groesserZoom: 19),
          19);
      expect(
          wischZoomStufe(startZoom: 8, wischWegY: 10000, kleinsterZoom: 2), 2);
    });

    test('Kneifen wird als solches erkannt', () {
      // Ein echtes Trackpad schickt beim Zweifinger-Kneifen dieselbe Art
      // Ereignis, nur mit einem Skalenwert. Das kann flutter_map selbst -
      // dort darf nicht dazwischengefunkt werden, sonst zoomt es doppelt.
      expect(istWischen(1.0), isTrue);
      expect(istWischen(1.4), isFalse);
      expect(istWischen(0.6), isFalse);
    });
  });

  group('An der echten Karte', () {
    late MapController steuerung;

    Future<void> karteAufbauen(WidgetTester tester, {bool mitZoom = true}) async {
      steuerung = MapController();
      final karte = FlutterMap(
        mapController: steuerung,
        options: const MapOptions(
          initialCenter: LatLng(51.0, 10.0),
          initialZoom: 8,
        ),
        children: const [],
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: mitZoom
                ? WischZoom(steuerung: steuerung, child: karte)
                : karte,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    /// Genau das, was macOS bei einer Wischgeste auf einer Tastflaeche
    /// schickt: eine Pan-Zoom-Folge, kein Radschritt.
    Future<void> wischen(WidgetTester tester,
        {required double wegY, double skala = 1.0}) async {
      final geste = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      await geste.panZoomStart(const Offset(300, 200));
      for (var i = 1; i <= 5; i++) {
        await geste.panZoomUpdate(const Offset(300, 200),
            pan: Offset(0, wegY * i / 5), scale: skala);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await geste.panZoomEnd();
      await tester.pumpAndSettle();
    }

    testWidgets('ohne WischZoom verschiebt es nur - der Ausgangsbefund',
        (tester) async {
      // Die Gegenprobe. Ohne sie belegte der Test darunter nur, dass die
      // Karte zoomt - nicht, dass es an dieser Ergaenzung liegt.
      await karteAufbauen(tester, mitZoom: false);
      await wischen(tester, wegY: -100);
      expect(steuerung.camera.zoom, 8.0, reason: 'ab Werk zoomt es nicht');
      expect(steuerung.camera.center.latitude, isNot(51.0),
          reason: 'ab Werk verschiebt es');
    });

    testWidgets('mit WischZoom wird gezoomt statt verschoben', (tester) async {
      await karteAufbauen(tester);
      await wischen(tester, wegY: -100);
      expect(steuerung.camera.zoom, greaterThan(8.0));
      // Und die Mitte bleibt, wo sie war: Sie nimmt zurueck, was die
      // Karte aus derselben Geste als Verschiebung gemacht hat.
      expect(steuerung.camera.center.latitude, closeTo(51.0, 0.0001));
      expect(steuerung.camera.center.longitude, closeTo(10.0, 0.0001));
    });

    testWidgets('nach unten wischen zoomt heraus', (tester) async {
      await karteAufbauen(tester);
      await wischen(tester, wegY: 100);
      expect(steuerung.camera.zoom, lessThan(8.0));
    });

    testWidgets('Kneifen bleibt der Karte ueberlassen', (tester) async {
      // Der Fall, der am leichtesten doppelt zoomt: flutter_map setzt
      // beim Kneifen selbst den Zoom. Griffe WischZoom auch zu, addierten
      // sich beide - und die Mitte bliebe faelschlich festgenagelt.
      await karteAufbauen(tester);
      await wischen(tester, wegY: 0, skala: 2.0);
      expect(steuerung.camera.zoom, greaterThan(8.0),
          reason: 'das Kneifen selbst muss weiter wirken');
    });
  });
}
