import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_vault/widgets/bild_zoom_gesten.dart';

/// **Zoomen mit einer Magic Mouse.**
///
/// Aus dem Erstlauf-Bericht (C10): "mit trackpad funktioniert zwei
/// finger zoom, mit magic mouse nicht". Eine Magic Mouse hat kein Rad
/// und keine zwei Finger zum Kneifen - sie kennt nur das Wischen.
void main() {
  group('Die Wischrechnung', () {
    test('nach oben wischen vergroessert', () {
      // In Flutter waechst y nach unten: Ein Wisch nach oben ist negativ.
      final neu = bildWischZoom(
        startZoom: 1,
        wischWegY: -200,
        kleinster: 0.1,
        groesster: 8,
      );
      expect(neu, greaterThan(1));
    });

    test('nach unten wischen verkleinert', () {
      final neu = bildWischZoom(
        startZoom: 2,
        wischWegY: 200,
        kleinster: 0.1,
        groesster: 8,
      );
      expect(neu, lessThan(2));
    });

    test('gleiche Wege ergeben gleiche Spruenge, egal wo man steht', () {
      // Der Zoom ist ein Faktor, keine Stufe. Ein Wisch von 100 Punkten
      // soll bei 1,0 dasselbe Verhaeltnis ergeben wie bei 4,0 - sonst
      // fuehlt sich die Geste weit hineingezoomt zaeh an.
      final vonEins = bildWischZoom(
        startZoom: 1,
        wischWegY: -100,
        kleinster: 0.01,
        groesster: 100,
      );
      final vonVier = bildWischZoom(
        startZoom: 4,
        wischWegY: -100,
        kleinster: 0.01,
        groesster: 100,
      );
      expect(vonVier / 4, closeTo(vonEins / 1, 1e-9));
    });

    test('ein Wisch ohne Weg laesst alles, wie es ist', () {
      expect(
        bildWischZoom(
          startZoom: 1.7,
          wischWegY: 0,
          kleinster: 0.1,
          groesster: 8,
        ),
        closeTo(1.7, 1e-9),
      );
    });

    test('die Grenzen halten', () {
      expect(
        bildWischZoom(
          startZoom: 1,
          wischWegY: -5000,
          kleinster: 0.1,
          groesster: 8,
        ),
        8,
      );
      expect(
        bildWischZoom(
          startZoom: 1,
          wischWegY: 5000,
          kleinster: 0.1,
          groesster: 8,
        ),
        0.1,
      );
    });
  });

  group('Welche Taste den Zoom auslöst', () {
    test('ohne Taste nicht', () {
      expect(zoomtaste(const {}), isFalse);
      expect(zoomtaste({LogicalKeyboardKey.shiftLeft}), isFalse);
    });

    test('Command und Strg beide', () {
      // Beide auf jeder Plattform: Eine externe Tastatur an einem Mac
      // meldet je nach Belegung das eine oder das andere.
      expect(zoomtaste({LogicalKeyboardKey.metaLeft}), isTrue);
      expect(zoomtaste({LogicalKeyboardKey.controlRight}), isTrue);
    });
  });

  group('Zusammen mit PhotoView', () {
    // PhotoView bekommt dieselben Trackpad-Ereignisse über seine
    // Skalierungserkennung (Massstab 1) und setzte den Zoom bei jedem
    // Ereignis auf den Anfang der Geste zurück. Die Rechnung oben stimmte,
    // das Bild blieb trotzdem stehen.
    late PhotoViewController steuerung;

    Future<void> zeige(WidgetTester tester) async {
      steuerung = PhotoViewController();
      addTearDown(steuerung.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: BildZoomGesten(
            steuerung: steuerung,
            child: PhotoView.customChild(
              controller: steuerung,
              childSize: const Size(400, 300),
              child: const ColoredBox(color: Color(0xFF336699)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> wischen(WidgetTester tester, double dy) async {
      final mitte = tester.getCenter(find.byType(PhotoView));
      final g = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      await g.panZoomStart(mitte);
      for (var i = 1; i <= 5; i++) {
        await g.panZoomUpdate(mitte, pan: Offset(0, dy * i / 5));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.panZoomEnd();
      await tester.pumpAndSettle();
    }

    testWidgets('⌘ + Wischen nach oben vergrössert, nach unten verkleinert', (
      tester,
    ) async {
      await zeige(tester);
      final anfang = steuerung.scale!;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await wischen(tester, -120);
      final hoch = steuerung.scale!;
      expect(hoch, greaterThan(anfang * 1.2));
      await wischen(tester, 120);
      expect(steuerung.scale!, lessThan(hoch * 0.9));
      for (var i = 0; i < 4; i++) {
        await wischen(tester, -900);
      }
      expect(steuerung.scale!, closeTo(8, 1e-9), reason: 'Grenze');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    });

    testWidgets('ohne Taste verschiebt der Wisch nur', (tester) async {
      await zeige(tester);
      final anfang = steuerung.scale!;
      await wischen(tester, -120);
      expect(steuerung.scale!, closeTo(anfang, 1e-9));
    });
  });
}
