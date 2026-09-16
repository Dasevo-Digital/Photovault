import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/develop_color.dart';
import 'package:photo_vault/services/native_image_converter.dart';

/// Die Mathematik hinter Tonwertkurve und Farbmischer.
///
/// Sie wird später von zwei Renderpfaden blind übernommen – dem GPU-Shader
/// und der Core-Image-Kette. Keiner von beiden lässt sich in einem Test
/// ausführen; was hier nicht geprüft wird, fällt erst am fertigen Bild auf.
void main() {
  group('Tonwertkurve', () {
    test('die Gerade lässt jeden Wert unverändert', () {
      for (final x in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        expect(evaluateCurve(const [CurvePoint(0, 0), CurvePoint(1, 1)], x),
            closeTo(x, 1e-9));
      }
    });

    test('die neutrale Kurve ergibt eine Rampe', () {
      final tabelle = buildCurveLut(ToneCurve.neutral);
      expect(tabelle, hasLength(curveLutSize * 3));
      for (var i = 0; i < curveLutSize; i++) {
        final erwartet = i / (curveLutSize - 1);
        for (var k = 0; k < 3; k++) {
          expect(tabelle[i * 3 + k], closeTo(erwartet, 1e-6));
        }
      }
    });

    test('Kontrollpunkte werden genau getroffen', () {
      const punkte = [CurvePoint(0, 0), CurvePoint(0.5, 0.8), CurvePoint(1, 1)];
      expect(evaluateCurve(punkte, 0.0), closeTo(0.0, 1e-9));
      expect(evaluateCurve(punkte, 0.5), closeTo(0.8, 1e-9));
      expect(evaluateCurve(punkte, 1.0), closeTo(1.0, 1e-9));
    });

    test('eine steigende Kurve kehrt sich nirgends um', () {
      // Genau der Fall, an dem Catmull-Rom oder eine natürliche Spline
      // überschwingen würde: ein steiler Sprung dicht neben einem flachen
      // Stück. Fritsch–Carlson darf hier nicht zurücklaufen.
      const punkte = [
        CurvePoint(0, 0),
        CurvePoint(0.5, 0.5),
        CurvePoint(0.55, 0.9),
        CurvePoint(1, 1),
      ];
      var vorher = -1.0;
      for (var i = 0; i < 1000; i++) {
        final wert = evaluateCurve(punkte, i / 999);
        expect(wert, greaterThanOrEqualTo(vorher),
            reason: 'bei x=${i / 999} läuft die Kurve zurück');
        vorher = wert;
      }
    });

    test('ein waagerechtes Stück bleibt waagerecht', () {
      // Zwei Punkte auf gleicher Höhe: dazwischen darf keine Delle und
      // keine Beule entstehen – die zweite Hälfte der Fritsch-Carlson-
      // Dämpfung (Sekante null ⇒ beide Tangenten null).
      const punkte = [
        CurvePoint(0, 0),
        CurvePoint(0.4, 0.5),
        CurvePoint(0.6, 0.5),
        CurvePoint(1, 1),
      ];
      for (var i = 0; i <= 20; i++) {
        final x = 0.4 + 0.2 * i / 20;
        expect(evaluateCurve(punkte, x), closeTo(0.5, 1e-9));
      }
    });

    test('ausserhalb der Punkte wird gehalten, nicht extrapoliert', () {
      const punkte = [CurvePoint(0.2, 0.3), CurvePoint(0.8, 0.7)];
      expect(evaluateCurve(punkte, 0.0), closeTo(0.3, 1e-9));
      expect(evaluateCurve(punkte, 1.0), closeTo(0.7, 1e-9));
    });

    test('Werte bleiben immer im Bereich 0..1', () {
      const punkte = [CurvePoint(0, 0), CurvePoint(0.5, 1), CurvePoint(1, 1)];
      for (var i = 0; i <= 100; i++) {
        final wert = evaluateCurve(punkte, i / 100);
        expect(wert, inInclusiveRange(0.0, 1.0));
      }
    });

    test('unbrauchbare Punktfolgen liefern die Identität', () {
      expect(evaluateCurve(const [], 0.42), closeTo(0.42, 1e-9));
      expect(evaluateCurve(const [CurvePoint(0.5, 0.9)], 0.42), closeTo(0.42, 1e-9));
    });

    test('der Farbkanal wirkt vor dem Zusammen-Kanal', () {
      // Rot verdoppelt (0,5 → 1,0), danach halbiert der Zusammen-Kanal
      // alles wieder. Bei umgekehrter Reihenfolge käme 0,5 heraus statt
      // 0,5·2·0,5 – der Test hält die festgelegte Reihenfolge fest.
      const rot = [CurvePoint(0, 0), CurvePoint(0.5, 1), CurvePoint(1, 1)];
      const zusammen = [CurvePoint(0, 0), CurvePoint(1, 0.5)];
      final tabelle = buildCurveLut(const ToneCurve(rot: rot, zusammen: zusammen));

      const mitte = (curveLutSize - 1) ~/ 2; // Eingang ≈ 0,5
      // Rot: 0,5 → 1,0; danach Zusammen: 1,0 → 0,5.
      expect(tabelle[mitte * 3], closeTo(0.5, 0.02));
      // Grün ohne eigene Kurve: nur der Zusammen-Kanal, 0,5 → 0,25.
      expect(tabelle[mitte * 3 + 1], closeTo(0.25, 0.02));
    });

    test('istNeutral erkennt nur die echte Gerade', () {
      expect(ToneCurve.neutral.istNeutral, isTrue);
      expect(
        const ToneCurve(rot: [CurvePoint(0, 0), CurvePoint(1, 0.9)]).istNeutral,
        isFalse,
      );
      expect(
        const ToneCurve(
          zusammen: [CurvePoint(0, 0), CurvePoint(0.5, 0.5), CurvePoint(1, 1)],
        ).istNeutral,
        isFalse,
        reason: 'ein zusätzlicher Punkt auf der Geraden ändert nichts am '
            'Bild, aber die Tabelle wird trotzdem gebraucht, sobald der '
            'Nutzer ihn verschiebt',
      );
    });

    test('JSON-Rundlauf erhält die Punkte', () {
      const kurve = ToneCurve(
        zusammen: [CurvePoint(0, 0), CurvePoint(0.3, 0.45), CurvePoint(1, 1)],
        blau: [CurvePoint(0, 0.1), CurvePoint(1, 0.9)],
      );
      final zurueck = ToneCurve.decode(kurve.encode());

      expect(zurueck.zusammen, kurve.zusammen);
      expect(zurueck.blau, kurve.blau);
      expect(zurueck.rot, [const CurvePoint(0, 0), const CurvePoint(1, 1)]);
    });

    test('die neutrale Kurve kodiert zu einem leeren Objekt', () {
      // Damit eine unbenutzte Kurve in der Datenbank keinen Ballast
      // hinterlässt.
      expect(ToneCurve.neutral.encode(), '{}');
      expect(ToneCurve.decode('{}').istNeutral, isTrue);
    });
  });

  group('Farbbänder', () {
    test('die Gewichte ergeben immer zusammen eins', () {
      // Die Kernzusage der linearen Blendung: kein Pixel wird doppelt
      // angefasst, keines gar nicht. Eine Glockenkurve je Band hätte hier
      // je nach Farbton unterschiedliche Summen.
      for (var grad = 0; grad < 720; grad++) {
        final summe = bandWeights(grad.toDouble()).reduce((a, b) => a + b);
        expect(summe, closeTo(1.0, 1e-9), reason: 'bei $grad°');
      }
    });

    test('auf einem Mittelpunkt trägt genau ein Band', () {
      for (final band in ColorBand.values) {
        final gewichte = bandWeights(band.mittelpunkt);
        expect(gewichte[band.index], closeTo(1.0, 1e-9), reason: band.name);
        for (var i = 0; i < gewichte.length; i++) {
          if (i != band.index) expect(gewichte[i], closeTo(0.0, 1e-9));
        }
      }
    });

    test('zwischen zwei Mittelpunkten tragen genau zwei Bänder', () {
      final gewichte = bandWeights(15); // zwischen Rot (0°) und Orange (30°)
      expect(gewichte[ColorBand.rot.index], closeTo(0.5, 1e-9));
      expect(gewichte[ColorBand.orange.index], closeTo(0.5, 1e-9));
      expect(gewichte.where((g) => g > 0), hasLength(2));
    });

    test('der Übergang von Magenta zurück zu Rot schliesst sich', () {
      // 300° bis 360° ist das einzige Band, das über den Nullpunkt läuft.
      final gewichte = bandWeights(330);
      expect(gewichte[ColorBand.magenta.index], closeTo(0.5, 1e-9));
      expect(gewichte[ColorBand.rot.index], closeTo(0.5, 1e-9));
    });
  });

  group('Farbmischer', () {
    test('ohne Anpassung bleibt jede Farbe, wie sie war', () {
      for (final farbe in [
        [1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.2, 0.4, 0.9],
        [0.5, 0.5, 0.5],
        [0.0, 0.0, 0.0],
        [1.0, 1.0, 1.0],
      ]) {
        final aus = applyColorMixer(ColorMixer.neutral, farbe[0], farbe[1], farbe[2]);
        for (var i = 0; i < 3; i++) {
          expect(aus[i], closeTo(farbe[i], 1e-9), reason: '$farbe');
        }
      }
    });

    test('Neutralgrau bleibt grau, auch bei kräftigen Reglern', () {
      // Der Farbton eines grauen Pixels ist numerisch instabil. Ohne die
      // Sättigungssperre würde ein Farbton-Regler grauen Flächen und
      // Rauschen eine Farbe geben.
      const mixer = ColorMixer({
        ColorBand.rot: BandAnpassung(farbton: 1, saettigung: 1, helligkeit: 0.5),
        ColorBand.blau: BandAnpassung(farbton: -1, saettigung: 1),
      });
      for (final grau in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        final aus = applyColorMixer(mixer, grau, grau, grau);
        expect(aus[0], closeTo(grau, 1e-9));
        expect(aus[1], closeTo(grau, 1e-9));
        expect(aus[2], closeTo(grau, 1e-9));
      }
    });

    test('ein unangetastetes Band lässt seine Farben in Ruhe', () {
      // Rot voll aufgedreht darf Blau (240°, zwei Bänder entfernt) nicht
      // anfassen.
      const mixer = ColorMixer({
        ColorBand.rot: BandAnpassung(farbton: 1, saettigung: -1, helligkeit: 1),
      });
      final blau = applyColorMixer(mixer, 0.0, 0.0, 1.0);
      expect(blau[0], closeTo(0.0, 1e-9));
      expect(blau[1], closeTo(0.0, 1e-9));
      expect(blau[2], closeTo(1.0, 1e-9));
    });

    test('Sättigung -1 entfärbt das eigene Band vollständig', () {
      const mixer = ColorMixer({ColorBand.rot: BandAnpassung(saettigung: -1)});
      final aus = applyColorMixer(mixer, 1.0, 0.0, 0.0);
      expect(aus[0], closeTo(aus[1], 1e-6));
      expect(aus[1], closeTo(aus[2], 1e-6));
    });

    test('Helligkeit läuft nach Weiss und nach Schwarz, ohne zu kippen', () {
      final hell = applyColorMixer(
        const ColorMixer({ColorBand.rot: BandAnpassung(helligkeit: 1)}),
        1.0, 0.0, 0.0,
      );
      expect(hell.every((k) => k > 0.99), isTrue, reason: 'nach Weiss: $hell');

      final dunkel = applyColorMixer(
        const ColorMixer({ColorBand.rot: BandAnpassung(helligkeit: -1)}),
        1.0, 0.0, 0.0,
      );
      expect(dunkel.every((k) => k < 0.01), isTrue, reason: 'nach Schwarz: $dunkel');
    });

    test('jede Ausgabe bleibt im Bereich 0..1', () {
      const mixer = ColorMixer({
        ColorBand.rot: BandAnpassung(farbton: 1, saettigung: 1, helligkeit: 1),
        ColorBand.aqua: BandAnpassung(farbton: -1, saettigung: 1, helligkeit: -1),
        ColorBand.gelb: BandAnpassung(saettigung: 1, helligkeit: 1),
      });
      for (var i = 0; i <= 10; i++) {
        for (var j = 0; j <= 10; j++) {
          for (var k = 0; k <= 10; k++) {
            final aus = applyColorMixer(mixer, i / 10, j / 10, k / 10);
            for (final kanal in aus) {
              expect(kanal, inInclusiveRange(0.0, 1.0));
            }
          }
        }
      }
    });

    test('JSON-Rundlauf erhält die Bänder', () {
      const mixer = ColorMixer({
        ColorBand.gruen: BandAnpassung(saettigung: 0.4, helligkeit: -0.2),
      });
      final zurueck = ColorMixer.decode(mixer.encode());
      expect(zurueck.band(ColorBand.gruen).saettigung, 0.4);
      expect(zurueck.band(ColorBand.gruen).helligkeit, -0.2);
      expect(zurueck.band(ColorBand.gruen).farbton, 0);
      expect(zurueck.band(ColorBand.rot).istNeutral, isTrue);
      expect(ColorMixer.neutral.encode(), '{}');
    });
  });

  group('Farbwürfel', () {
    test('der neutrale Würfel bildet jede Stützstelle auf sich selbst ab', () {
      const size = 8; // kleiner Würfel, dieselbe Anordnung
      final wuerfel = buildColorCube(ColorMixer.neutral, size: size);
      expect(wuerfel, hasLength(size * size * size * 4));

      var i = 0;
      for (var b = 0; b < size; b++) {
        for (var g = 0; g < size; g++) {
          for (var r = 0; r < size; r++) {
            expect(wuerfel[i++], closeTo(r / (size - 1), 1e-6));
            expect(wuerfel[i++], closeTo(g / (size - 1), 1e-6));
            expect(wuerfel[i++], closeTo(b / (size - 1), 1e-6));
            expect(wuerfel[i++], 1.0, reason: 'Alpha muss 1 sein');
          }
        }
      }
    });

    test('Rot läuft am schnellsten, dann Grün, dann Blau', () {
      // Die Anordnung ist nicht frei wählbar – CIColorCube erwartet genau
      // diese. Ein vertauschter Index fiele sonst erst als Farbstich im
      // gerenderten Bild auf.
      const size = 4;
      final wuerfel = buildColorCube(ColorMixer.neutral, size: size);

      // Zweiter Eintrag: r=1, g=0, b=0.
      expect(wuerfel[4], closeTo(1 / 3, 1e-6));
      expect(wuerfel[5], closeTo(0.0, 1e-6));
      // Eintrag size: r=0, g=1, b=0.
      expect(wuerfel[size * 4], closeTo(0.0, 1e-6));
      expect(wuerfel[size * 4 + 1], closeTo(1 / 3, 1e-6));
      // Eintrag size²: r=0, g=0, b=1.
      expect(wuerfel[size * size * 4 + 2], closeTo(1 / 3, 1e-6));
    });

    test('die Standardgrösse ist gross genug für weiche Verläufe', () {
      expect(colorCubeSize, 32);
      final wuerfel = buildColorCube(ColorMixer.neutral);
      expect(wuerfel, hasLength(32 * 32 * 32 * 4));
    });
  });

  group('Übergabe an die native Seite', () {
    test('neutrale Werkzeuge werden gar nicht erst übertragen', () {
      final karte = DevelopAdjustments.neutral.toChannelMap();
      expect(karte.containsKey('toneCurveLut'), isFalse);
      expect(karte.containsKey('colorCube'), isFalse);
      expect(karte.containsKey('colorCubeSize'), isFalse);
    });

    test('eine gesetzte Kurve geht als fertige Tabelle hinüber', () {
      const kurve = ToneCurve(zusammen: [CurvePoint(0, 0), CurvePoint(1, 0.5)]);
      final karte = const DevelopAdjustments(toneCurve: kurve).toChannelMap();

      // Genau 256 Tripel – CIColorCurves rechnet die Länge gegen seinen
      // Wertebereich, eine andere Länge ergäbe eine falsche Gradation.
      expect(karte['toneCurveLut'], hasLength(curveLutSize * 3));
      expect(karte.containsKey('colorCube'), isFalse,
          reason: 'ein neutraler Mischer bleibt zu Hause');
    });

    test('ein gesetzter Mischer schickt Würfel UND Kantenlänge', () {
      const mischer = ColorMixer({ColorBand.gelb: BandAnpassung(farbton: 0.3)});
      final karte = const DevelopAdjustments(colorMixer: mischer).toChannelMap();

      expect(karte['colorCubeSize'], colorCubeSize);
      expect(karte['colorCube'], hasLength(colorCubeSize * colorCubeSize * colorCubeSize * 4),
          reason: 'ohne passende Länge lehnt die native Seite den Filter ab');
    });

    test('Masken tragen weder Kurve noch Mischer', () {
      // Ergibt sich von selbst daraus, dass Masken neutrale Werkzeuge
      // haben und neutrale Werkzeuge nicht übertragen werden – dieser Test
      // hält fest, dass es dafür keinen Sonderfall braucht.
      const ebene = MaskAdjustmentLayer(
        maskFilePath: 'masks/x.png',
        adjustments: DevelopAdjustments(exposure: 1.0),
      );
      final karte = ebene.toChannelMap();
      expect(karte['path'], 'masks/x.png');
      expect(karte['exposure'], 1.0);
      expect(karte.containsKey('toneCurveLut'), isFalse);
      expect(karte.containsKey('colorCube'), isFalse);
    });
  });

  group('Verpacken für den Shader', () {
    test('die Kurventabelle wird zu 256 RGBA-Bytes', () {
      final bytes = packCurveLutForTexture(buildCurveLut(ToneCurve.neutral));
      expect(bytes, hasLength(curveLutSize * 4));
      expect(bytes[0], 0);
      expect(bytes[3], 255, reason: 'Alpha');
      expect(bytes[(curveLutSize - 1) * 4], 255);
      // Mitte der Rampe.
      expect(bytes[128 * 4], closeTo(128, 1));
    });

    test('der Würfel wird zu einem Streifen aus Blau-Scheiben', () {
      const size = 4;
      final wuerfel = buildColorCube(ColorMixer.neutral, size: size);
      final bytes = packColorCubeForTexture(wuerfel, size: size);

      expect(colorCubeStripWidth(size), size * size);
      expect(bytes, hasLength(size * size * size * 4));

      // Stützstelle r=3, g=2, b=1 muss bei x = b·size + r, y = g liegen.
      const r = 3, g = 2, b = 1;
      const x = b * size + r;
      final ziel = (g * colorCubeStripWidth(size) + x) * 4;
      expect(bytes[ziel], 255, reason: 'Rot voll');
      expect(bytes[ziel + 1], closeTo(255 * 2 / 3, 1));
      expect(bytes[ziel + 2], closeTo(255 * 1 / 3, 1));
      expect(bytes[ziel + 3], 255);
    });

    test('ein angepasster Würfel landet an derselben Stelle wie der Wert', () {
      // Belegt, dass Verpacken und Berechnen dieselbe Anordnung benutzen –
      // die beiden Indexrechnungen stehen an verschiedenen Stellen und
      // könnten unbemerkt auseinanderlaufen.
      const size = 8;
      const mixer = ColorMixer({ColorBand.rot: BandAnpassung(saettigung: -1)});
      final wuerfel = buildColorCube(mixer, size: size);
      final bytes = packColorCubeForTexture(wuerfel, size: size);

      const r = 7, g = 0, b = 0; // reines Rot
      const quelle = ((b * size + g) * size + r) * 4;
      const x = b * size + r;
      final ziel = (g * colorCubeStripWidth(size) + x) * 4;

      for (var k = 0; k < 3; k++) {
        expect(bytes[ziel + k], (wuerfel[quelle + k] * 255).round());
      }
    });
  });
}
