// Schilder im Gelände – Sichtprüfung und Überdeckung.
//
// Beides lässt sich nur teilweise rechnen. Die Sichtprüfung ist reine
// Geometrie und wird hier an einer Landschaft geprüft, deren Antwort
// vorher feststeht. Ob die Kästchen einander überdecken, entscheidet
// dagegen das gerenderte Bild – deshalb stehen darunter Tests, die
// wirklich zeichnen. Einer zählt Bildpunkte, einer zählt Kästchen: Die
// erste Fassung zählte nur Bildpunkte und ging mit ausgebauter Deckelung
// durch, weil vierzig Kästchen übereinander kaum mehr Farbe verbrauchen
// als eines.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/gelaendekacheln.dart';
import 'package:photo_vault/services/gelaendesicht.dart';
import 'package:photo_vault/services/wanderobjekte.dart';
import 'package:photo_vault/widgets/gelaendeschilder.dart';

void main() {
  group('Die Sichtpruefung', () {
    // Eine Landschaft mit einem Grat bei x = 0: 300 Meter hoch, sonst
    // flach auf null.
    double? grat(double x, double y) => x.abs() < 100 ? 300 : 0;

    test('freie Sicht ueber ebenes Gelaende', () {
      expect(
          sichtfrei((x: -1000, y: 0, z: 50), (x: -500, y: 0, z: 20), grat),
          isTrue);
    });

    test('ein Grat dazwischen verdeckt', () {
      // Von weit westlich nach weit oestlich, beide auf 20 Metern: Der
      // Grat bei x = 0 steht mit 300 Metern im Weg.
      expect(
          sichtfrei((x: -1000, y: 0, z: 20), (x: 1000, y: 0, z: 20), grat),
          isFalse);
    });

    test('ueber den Grat hinweg ist frei', () {
      expect(
          sichtfrei((x: -1000, y: 0, z: 800), (x: 1000, y: 0, z: 700), grat),
          isTrue);
    });

    test('ein Punkt auf dem Grat selbst ist sichtbar', () {
      // Das ist der Fall, der ohne Zugabe fehlschluege: Ein Schild sitzt
      // genau auf der Oberflaeche, und von einer flachen Kamera aus
      // waere es damit immer verdeckt. Deshalb sitzt es
      // [schildHoeheMeter] darueber.
      expect(
          sichtfrei((x: -1000, y: 0, z: 400),
              (x: 0, y: 0, z: 300 + schildHoeheMeter), grat),
          isTrue);
    });

    test('unbekannte Hoehen verdecken nichts', () {
      // Ein Loch im Gitter ist kein Berg. Ohne diese Regel verschwaenden
      // alle Schilder hinter einer fehlenden Kachel.
      expect(
          sichtfrei((x: -1000, y: 0, z: 20), (x: 1000, y: 0, z: 20),
              (x, y) => null),
          isTrue);
    });
  });

  group('Was gezeichnet wird', () {
    /// Zaehlt die Bildpunkte, die weder Hintergrund noch durchsichtig
    /// sind – ein grobes Mass dafuer, wie viel im Bild steht.
    Future<int> gemalt(List<Gelaendeschild> schilder,
        {double? Function(double, double)? hoeheBei}) async {
      const flaeche = ui.Size(600, 400);
      final sammler = ui.PictureRecorder();
      final leinwand = ui.Canvas(sammler);
      leinwand.drawRect(
          const ui.Rect.fromLTWH(0, 0, 600, 400),
          ui.Paint()..color = const Color(0xFF000000));
      zeichneSchilder(
        leinwand,
        flaeche,
        const Gelaendekamera(
          drehung: 0,
          neigung: 0.3,
          entfernung: 2000,
          brennweite: 800,
          mitte: Offset(300, 200),
        ),
        schilder,
        hoeheBei: hoeheBei,
      );
      final bild = await sammler.endRecording().toImage(600, 400);
      final roh = await bild.toByteData(format: ui.ImageByteFormat.rawRgba);
      bild.dispose();
      final px = roh!.buffer.asUint8List();
      var n = 0;
      for (var i = 0; i < px.length; i += 4) {
        if (px[i] > 20 || px[i + 1] > 20 || px[i + 2] > 20) n++;
      }
      return n;
    }

    testWidgets('ein Schild mit Namen malt mehr als eines ohne',
        (tester) async {
      await tester.runAsync(() async {
        final ohne = await gemalt([
          Gelaendeschild(
              ort: (x: 0, y: 0, z: 100), art: Wanderart.gipfel),
        ]);
        final mit = await gemalt([
          Gelaendeschild(
              ort: (x: 0, y: 0, z: 100),
              art: Wanderart.gipfel,
              beschriftung: 'Rohnberg  564 m'),
        ]);
        expect(ohne, greaterThan(0), reason: 'das Zeichen fehlt');
        expect(mit, greaterThan(ohne * 3),
            reason: 'der Name kommt nicht an');
      });
    });

    testWidgets('was verdeckt ist, wird gar nicht erst gemalt',
        (tester) async {
      await tester.runAsync(() async {
        final schild = [
          Gelaendeschild(
              ort: (x: 0, y: 0, z: 100),
              art: Wanderart.gipfel,
              beschriftung: 'Rohnberg'),
        ];
        final frei = await gemalt(schild, hoeheBei: (x, y) => 0);
        final verdeckt =
            await gemalt(schild, hoeheBei: (x, y) => 5000);
        expect(frei, greaterThan(0));
        expect(verdeckt, 0,
            reason: 'ohne Sichtpruefung schwebt der Name durch den Berg');
      });
    });

    test('hoechstens zwoelf Kaestchen, und keines auf dem anderen', () {
      // Vierzig Schilder auf engem Raum – so wie das Ilsetal, das 41
      // Punkte auf 2,8 × 3,3 km hat. Ohne Deckelung waere das Bild eine
      // Wand aus Kaestchen.
      //
      // **Gezaehlt wird, nicht gemessen.** Die erste Fassung dieses
      // Tests zaehlte gemalte Bildpunkte und ging mit ausgebauter
      // Deckelung durch: Vierzig Kaestchen uebereinander verbrauchen
      // kaum mehr Farbe als eines, weil sie einander verdecken.
      int male(List<Gelaendeschild> schilder) {
        final sammler = ui.PictureRecorder();
        final n = zeichneSchilder(
          ui.Canvas(sammler),
          const ui.Size(600, 400),
          const Gelaendekamera(
            drehung: 0,
            neigung: 0.3,
            entfernung: 2000,
            brennweite: 800,
            mitte: Offset(300, 200),
          ),
          schilder,
        );
        sammler.endRecording().dispose();
        return n;
      }

      final viele = [
        for (var i = 0; i < 40; i++)
          Gelaendeschild(
            ort: (x: -400 + i * 20.0, y: i * 7.0, z: 100),
            art: Wanderart.gipfel,
            beschriftung: 'Berg Nummer $i',
          ),
      ];
      final gemalt = male(viele);
      expect(gemalt, greaterThan(0), reason: 'gar nichts waere auch falsch');
      expect(gemalt, lessThanOrEqualTo(hoechstensBeschriftet),
          reason: 'die Deckelung greift nicht: $gemalt Kaestchen');
      // Und dicht an dicht bleibt noch weniger uebrig als die Deckelung
      // erlaubt - der Ueberdeckungsschutz.
      final dichtAnDicht = [
        for (var i = 0; i < 40; i++)
          Gelaendeschild(
            ort: (x: -20 + i * 1.0, y: 0, z: 100),
            art: Wanderart.gipfel,
            beschriftung: 'Berg Nummer $i',
          ),
      ];
      expect(male(dichtAnDicht), lessThan(hoechstensBeschriftet),
          reason: 'der Ueberdeckungsschutz greift nicht');
    });

    test('die Deckelung greift auch, wo nichts einander ueberdeckt', () {
      // Der Ueberdeckungsschutz allein reicht nicht als Beleg: Auf einem
      // kleinen Bild ueberdecken sich vierzig Kaestchen ohnehin, und der
      // Test ginge auch ohne Deckelung durch (nachgeprueft). Also ein
      // grosses Bild und Schilder weit auseinander - dann haengt alles
      // an der Deckelung.
      final sammler = ui.PictureRecorder();
      final gemalt = zeichneSchilder(
        ui.Canvas(sammler),
        const ui.Size(4000, 2600),
        const Gelaendekamera(
          drehung: 0,
          neigung: 0.9,
          entfernung: 9000,
          brennweite: 2600,
          mitte: Offset(2000, 1300),
        ),
        [
          for (var zeile = 0; zeile < 8; zeile++)
            for (var spalte = 0; spalte < 5; spalte++)
              Gelaendeschild(
                ort: (
                  x: -3000 + spalte * 1500.0,
                  y: -3000 + zeile * 900.0,
                  z: 0
                ),
                art: Wanderart.gipfel,
                beschriftung: 'B$zeile$spalte',
              ),
        ],
      );
      sammler.endRecording().dispose();
      expect(gemalt, hoechstensBeschriftet,
          reason: 'weit auseinander muessen genau so viele stehen, wie die '
              'Deckelung erlaubt - es sind $gemalt');
    });
  });

  test('das Hoehengitter laesst sich fuer die Sichtpruefung abtasten', () {
    // Der Weg, den der Bildschirm geht: Netzmeter zurueck in Grad, dort
    // das Gitter fragen, und die Hoehe wieder ueberhoehen. Ein
    // Vorzeichenfehler darin faellt sonst erst am Bild auf - und dort
    // sieht er aus wie ein Schild, das grundlos fehlt.
    const n = 16;
    final h = Float32List(n * n);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        h[y * n + x] = 400 + 100 * x / (n - 1);
      }
    }
    final g = Hoehengitter(
        spalten: n, zeilen: n, hoehen: h,
        nord: 51.84, sued: 51.83, west: 10.63, ost: 10.65);
    // Im Westen 400, im Osten 500 - und die Gitterspalte 0 liegt im
    // Westen.
    expect(g.anOrt(51.835, 10.63), closeTo(400, 0.5));
    expect(g.anOrt(51.835, 10.65), closeTo(500, 0.5));
    expect(g.anOrt(51.835, 10.64), closeTo(450, 1.0));
  });

  test('die Zeichen unterscheiden sich nach Art', () {
    // Die Farbe ist bei einem namenlosen Punkt die einzige Auskunft, die
    // er gibt. Zwei Arten mit derselben Farbe UND derselben Form waeren
    // nicht zu unterscheiden.
    final arten = Wanderart.values.toSet();
    expect(arten.length, greaterThan(5));
    // Jede Art muss sich zeichnen lassen, ohne zu werfen.
    final sammler = ui.PictureRecorder();
    final leinwand = ui.Canvas(sammler);
    for (final a in arten) {
      zeichneSchilder(
        leinwand,
        const ui.Size(200, 200),
        const Gelaendekamera(
          drehung: 0,
          neigung: math.pi / 4,
          entfernung: 500,
          brennweite: 400,
          mitte: Offset(100, 100),
        ),
        [Gelaendeschild(ort: (x: 0, y: 0, z: 0), art: a, beschriftung: a.name)],
      );
    }
    sammler.endRecording().dispose();
  });
}
