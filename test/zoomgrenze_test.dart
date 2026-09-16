import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';
import 'package:photo_vault/widgets/wisch_zoom.dart';

/// Wie weit die Karte hineinzoomen darf.
///
/// Anlass: Gemeldet war, dass ab einer bestimmten Stufe keine Kacheln
/// mehr kommen. Der Befund war ein anderer als „laden nicht" – es gab
/// **gar keine Grenze**. Oberhalb der letzten echten Stufe vergrössert
/// flutter_map die vorhandene Kachel weiter: auf Anzeigestufe 24 deckt
/// eine einzige Topo-Kachel 32.768 Punkte ab, auf Stufe 28 über eine
/// halbe Million. Das kann keine Grafikeinheit mehr zeichnen.
///
/// An den Servern nachgemessen, mitten in Berlin:
///
/// ```
/// OSM     z19 200,  z20 400
/// CARTO   z20 200 (3.765 B, mit Inhalt)
/// Topo    z17 200,  z18 200 aber 4.343 B einfarbig
/// ```
void main() {
  group('Die Grenzen der drei Quellen', () {
    tearDown(() => setzeCartoSchluessel(null));

    test('jede Quelle kennt ihre letzte echte Stufe', () {
      expect(Kartenstil.hell.hoechsteEchteStufe, 19,
          reason: 'ab 20 antwortet OSM mit 400');
      // Ohne Schluessel zeichnet die dunkle Karte OSM-Kacheln - und
      // erbt damit deren Grenze, nicht die von CARTO.
      expect(Kartenstil.dunkel.hoechsteEchteStufe, 19,
          reason: 'ohne Schluessel sind es OSM-Kacheln');
      setzeCartoSchluessel('probe');
      expect(Kartenstil.dunkel.hoechsteEchteStufe, 20,
          reason: 'CARTO traegt eine Stufe weiter');
      expect(Kartenstil.topo.hoechsteEchteStufe, 17,
          reason: 'darueber kommt eine einfarbige Kachel');
    });

    test('die Grenze zieht mit dem Schluessel mit', () {
      // Der Fall, der ohne diesen Test durchginge: Der Schluessel wird
      // eingetragen, die Karte holt CARTO-Kacheln - aber die
      // Zoomgrenze bliebe auf 19 stehen. Die zwanzigste Stufe waere
      // bezahlt und unerreichbar.
      expect(Kartenstil.dunkel.hoechsteAnzeigeStufe, 21);
      setzeCartoSchluessel('probe');
      expect(Kartenstil.dunkel.hoechsteAnzeigeStufe, 22);
    });

    test('die Anzeige darf zwei Stufen weiter als die Kacheln', () {
      // Nicht hart bei der echten Stufe abschneiden: Die Kachel wird
      // dabei vierfach vergroessert, also unschaerfer, aber sie ist DA.
      // Ein hartes Ende fuehlte sich wie ein Defekt an.
      for (final stil in Kartenstil.values) {
        expect(stil.hoechsteAnzeigeStufe, stil.hoechsteEchteStufe! + 2,
            reason: stil.name);
      }
    });

    test('keine Quelle darf ins Unendliche zoomen', () {
      // Der eigentliche Fehler. Oberhalb von rund 22 wird die skalierte
      // Kachel groesser als jede Textur, die gezeichnet werden kann.
      for (final stil in Kartenstil.values) {
        expect(stil.hoechsteAnzeigeStufe, lessThanOrEqualTo(22),
            reason: stil.name);
      }
    });

    test('die Verdrahtung: jede Karte setzt maxZoom', () {
      // Quelltext-Pruefung nach dem Muster von
      // keine_festen_texte_test.dart. Eine Karte OHNE Grenze faellt
      // sonst niemandem auf - bis jemand weit hineinzoomt.
      final karten = [
        for (final f in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')))
          if (f.readAsStringSync().contains('MapOptions(')) f.path
      ];
      expect(karten, isNotEmpty, reason: 'sonst prueft der Test nichts');
      for (final pfad in karten) {
        expect(File(pfad).readAsStringSync(), contains('maxZoom:'),
            reason: '$pfad baut eine Karte ohne Zoomgrenze');
      }
    });
  });

  group('An der echten Karte', () {
    Future<MapController> karte(WidgetTester tester,
        {required double grenze}) async {
      final steuerung = MapController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 500,
            child: WischZoom(
              steuerung: steuerung,
              groesserZoom: grenze,
              child: FlutterMap(
                mapController: steuerung,
                options: MapOptions(
                  initialCenter: const LatLng(52.5163, 13.3777),
                  initialZoom: 15,
                  maxZoom: grenze,
                ),
                children: const [],
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return steuerung;
    }

    testWidgets('ein sehr langer Wisch bleibt an der Grenze stehen',
        (tester) async {
      final steuerung = await karte(tester, grenze: 19);
      final geste = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      await geste.panZoomStart(const Offset(400, 250));
      // 3000 Punkte nach oben waeren ohne Grenze Stufe 45.
      for (var i = 1; i <= 10; i++) {
        await geste.panZoomUpdate(const Offset(400, 250),
            pan: Offset(0, -300.0 * i));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await geste.panZoomEnd();
      await tester.pumpAndSettle();

      expect(steuerung.camera.zoom, 19.0);
    });

    testWidgets('auch move() kommt nicht darueber hinaus', (tester) async {
      // Der Weg, den die Standortsuche und das Anspringen eines Fotos
      // nehmen. Ohne die Grenze in den Optionen liefe er daran vorbei.
      final steuerung = await karte(tester, grenze: 19);
      steuerung.move(const LatLng(52.5163, 13.3777), 30);
      await tester.pumpAndSettle();
      expect(steuerung.camera.zoom, lessThanOrEqualTo(19.0));
    });

    testWidgets('ohne Grenze zoomt es ins Nichts - der Ausgangsbefund',
        (tester) async {
      // Die Gegenprobe. Ohne sie belegten die Tests darueber nur, dass
      // eine Grenze eingehalten wird - nicht, dass es vorher keine gab.
      final steuerung = await karte(tester, grenze: double.infinity);
      steuerung.move(const LatLng(52.5163, 13.3777), 30);
      await tester.pumpAndSettle();
      expect(steuerung.camera.zoom, 30.0,
          reason: 'so weit liess sich die Karte vorher treiben');
    });
  });
}
