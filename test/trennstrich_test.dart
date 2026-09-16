import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/widgets/develop_preview.dart';

/// Der Vorher/Nachher-Trennstrich im Entwickeln-Bildschirm.
///
/// Geprüft wird die Geometrie, nicht das Aussehen: Wo liegt das
/// dargestellte Bild in der Fläche, und wohin gehört der Strich. Das ist
/// die Rechnung, die man am Bildschirm am schlechtesten beurteilen kann –
/// ein Strich, der um wenige Punkte danebenliegt, sieht richtig aus und
/// schneidet trotzdem an der falschen Stelle.
void main() {
  group('Wann der Strich zu sehen ist', () {
    test('eingeschaltet, Original da, kein Shader: sichtbar', () {
      expect(
        trennstrichZeigen(
            eingeschaltet: true, originalDa: true, shaderLaeuft: false),
        isTrue,
      );
    });

    test('ohne das unbearbeitete Bild bleibt er aus', () {
      // Es wird erst auf Anforderung gerendert. Zeigte man den Strich
      // schon vorher, stünde links eine leere Flaeche - und die saehe
      // aus wie ein kaputtes Bild.
      expect(
        trennstrichZeigen(
            eingeschaltet: true, originalDa: false, shaderLaeuft: false),
        isFalse,
      );
    });

    test('waehrend der Shader-Vorschau tritt er zurueck', () {
      // Der Shader zeichnet nur das BEARBEITETE Bild. Ein Strich darueber
      // zeigte links wie rechts dasselbe und behauptete damit, es gaebe
      // keinen Unterschied - die schlimmste Art, falsch zu liegen.
      expect(
        trennstrichZeigen(
            eingeschaltet: true, originalDa: true, shaderLaeuft: true),
        isFalse,
      );
    });

    test('ausgeschaltet bleibt ausgeschaltet', () {
      expect(
        trennstrichZeigen(
            eingeschaltet: false, originalDa: true, shaderLaeuft: false),
        isFalse,
      );
    });
  });

  group('Das dargestellte Bildrechteck', () {
    test('gleiches Verhaeltnis fuellt die Flaeche ganz aus', () {
      final r = dargestelltesBild(const Size(400, 200), 2.0);
      expect(r, const Rect.fromLTWH(0, 0, 400, 200));
    });

    test('Querformat in quadratischer Flaeche: Raender oben und unten', () {
      final r = dargestelltesBild(const Size(400, 400), 2.0);
      expect(r.width, 400);
      expect(r.height, 200);
      expect(r.top, 100, reason: 'mittig, nicht oben angeschlagen');
      expect(r.left, 0);
    });

    test('Hochformat in breiter Flaeche: Raender links und rechts', () {
      // Genau der Fall, für den die Rechnung überhaupt da ist. Ohne sie
      // liefe das Ziehen zu einem grossen Teil durch Leere.
      final r = dargestelltesBild(const Size(400, 200), 0.5);
      expect(r.height, 200);
      expect(r.width, 100);
      expect(r.left, 150);
      expect(r.right, 250);
    });

    test('leere Flaeche ergibt ein leeres Rechteck statt NaN', () {
      expect(dargestelltesBild(Size.zero, 1.5), Rect.zero);
      expect(dargestelltesBild(const Size(100, 100), 0), Rect.zero);
    });
  });

  group('Die Position des Strichs', () {
    const bild = Rect.fromLTWH(150, 0, 100, 200);

    test('links vom Bild ergibt 0, rechts davon 1', () {
      // Ausserhalb wird begrenzt statt ueber 0..1 hinauszulaufen: Ein
      // Anteil von -0,4 waere ein Schnitt links vom Bild, und der
      // Clipper zeigte dann gar nichts mehr.
      expect(trennstrichAnteil(0, bild), 0.0);
      expect(trennstrichAnteil(400, bild), 1.0);
    });

    test('die Mitte des Bildes ist 0,5 - nicht die Mitte der Flaeche', () {
      expect(trennstrichAnteil(200, bild), 0.5);
      // Die Flaechenmitte laege bei x=200 nur zufaellig richtig; bei
      // aussermittigem Bild waere sie es nicht:
      const versetzt = Rect.fromLTWH(0, 0, 100, 200);
      expect(trennstrichAnteil(50, versetzt), 0.5);
      expect(trennstrichAnteil(200, versetzt), 1.0);
    });

    test('ein Bild ohne Breite liefert die Mitte statt zu teilen', () {
      expect(trennstrichAnteil(10, Rect.zero), 0.5);
    });
  });

  group('Das Widget selbst', () {
    // Ein 1x1-PNG. Reicht: Geprueft wird der Aufbau, nicht der Inhalt -
    // und dass beide Bilder GLEICHZEITIG im Baum stehen, ist genau der
    // Unterschied zum Gedrueckt-Halten, das immer nur eines zeigt.
    final einPixel = Uint8List.fromList(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
      0x42, 0x60, 0x82,
    ]);

    Future<void> zeige(WidgetTester tester, double anteil,
        {ValueChanged<double>? beiVerschieben}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 200,
            child: VorherNachherVergleich(
              original: einPixel,
              bearbeitet: einPixel,
              seitenverhaeltnis: 2.0,
              anteil: anteil,
              beiVerschieben: beiVerschieben ?? (_) {},
              vorherText: 'Vorher',
              nachherText: 'Nachher',
            ),
          ),
        ),
      ));
    }

    testWidgets('zeigt beide Bilder gleichzeitig', (tester) async {
      await zeige(tester, 0.5);
      expect(find.byType(Image), findsNWidgets(2),
          reason: 'genau das kann das Gedrueckt-Halten nicht');
      expect(find.text('Vorher'), findsOneWidget);
      expect(find.text('Nachher'), findsOneWidget);
    });

    testWidgets('das Ziehen am Griff meldet eine neue Position',
        (tester) async {
      double? gemeldet;
      await zeige(tester, 0.5, beiVerschieben: (a) => gemeldet = a);

      // Der Griff sitzt bei halber Breite; 100 Punkte nach rechts sind
      // bei 400 Punkten Bildbreite ein Viertel.
      //
      // `touchSlopX: 0` ist hier kein Schoenrechnen, sondern die
      // Trennung der Fragen: Flutter verschluckt am Anfang jeder Wisch-
      // geste 18 Punkte als Schwelle. Ohne diese Angabe kaeme 0,705
      // heraus - richtig, aber ein Wert, der die Schwelle misst statt
      // die Umrechnung von Punkten in Anteile.
      await tester.drag(
          find.byIcon(Icons.compare_arrows), const Offset(100, 0),
          touchSlopX: 0);
      await tester.pump();

      expect(gemeldet, isNotNull, reason: 'der Griff nimmt das Ziehen an');
      expect(gemeldet, closeTo(0.75, 0.001));
    });

    testWidgets('ein Anteil von 0 blendet das bearbeitete Bild ganz aus',
        (tester) async {
      // Der Randfall, in dem der Clipper eine Breite von 0 bekommt. Er
      // darf dabei nicht werfen.
      await zeige(tester, 0.0);
      expect(tester.takeException(), isNull);
      await zeige(tester, 1.0);
      expect(tester.takeException(), isNull);
    });
  });
}
