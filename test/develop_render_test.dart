import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:kern/services/develop_color.dart';
import 'package:photo_vault/services/develop_render.dart';
import 'package:photo_vault/services/native_image_converter.dart';

import 'hilfen/entwickeln_tafel.dart';

/// Der Shader war bisher nur für die Live-Vorschau da; das gespeicherte
/// Ergebnis kam vom nativen Renderpfad. Wo es den nicht gibt – Linux,
/// Windows – wirkten die Entwickeln-Regler auf gar nichts (siehe
/// docs/plan_linux.md, Phase 3).
///
/// Diese Tests laufen auf JEDER Plattform: Sie rufen den Shader-Weg direkt
/// auf, nicht über die Plattform-Weiche. So fällt eine Änderung am Shader
/// auch auf dem Entwicklungsrechner auf und nicht erst auf der Zielmaschine.
void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('pv_develop_'));
  tearDown(() => temp.deleteSync(recursive: true));

  /// Eine gleichmässig mittelgraue Fläche – daran lässt sich jede
  /// Helligkeitsänderung als eine Zahl ablesen.
  File legeGrau(String name, {int wert = 128, int kante = 256}) {
    final bild = img.Image(width: kante, height: kante);
    img.fill(bild, color: img.ColorRgb8(wert, wert, wert));
    return File(p.join(temp.path, name))..writeAsBytesSync(img.encodePng(bild));
  }

  double mittlereHelligkeit(Uint8List jpeg) {
    final bild = img.decodeImage(jpeg)!;
    var summe = 0.0;
    var n = 0;
    for (var x = 0; x < bild.width; x += 4) {
      for (var y = 0; y < bild.height; y += 4) {
        summe += bild.getPixel(x, y).luminance;
        n++;
      }
    }
    return summe / n;
  }

  test('neutrale Einstellungen lassen das Bild, wie es ist', () async {
    final quelle = legeGrau('grau.png');

    final bytes = await DevelopRender.rendere(
      quelle,
      adjustments: const DevelopAdjustments(),
    );

    expect(bytes, isNotNull, reason: 'der Shader-Weg lieferte gar nichts');
    // JPEG rundet, deshalb eine kleine Toleranz – aber es muss dasselbe
    // Grau sein und nicht etwa Schwarz.
    expect(mittlereHelligkeit(bytes!), closeTo(128, 3));
  });

  test(
    'Belichtung hellt auf, und zwar in der richtigen Grössenordnung',
    () async {
      final quelle = legeGrau('grau.png');

      final neutral = await DevelopRender.rendere(
        quelle,
        adjustments: const DevelopAdjustments(),
      );
      final heller = await DevelopRender.rendere(
        quelle,
        adjustments: const DevelopAdjustments(exposure: 1),
      );
      final dunkler = await DevelopRender.rendere(
        quelle,
        adjustments: const DevelopAdjustments(exposure: -1),
      );

      final n = mittlereHelligkeit(neutral!);
      final h = mittlereHelligkeit(heller!);
      final d = mittlereHelligkeit(dunkler!);

      expect(h, greaterThan(n + 20), reason: '+1 EV muss sichtbar aufhellen');
      expect(d, lessThan(n - 20), reason: '-1 EV muss sichtbar abdunkeln');
      // +1 EV verdoppelt die Lichtmenge; nach der sRGB-Kennlinie landet
      // mittleres Grau (128) dabei etwa bei 180. Die Grenzen sind weit
      // genug, um Rundung zu erlauben, und eng genug, um eine Rechnung in
      // der falschen Farbraum-Domäne auffallen zu lassen.
      expect(h, inInclusiveRange(165, 195));
    },
  );

  test('das Ergebnis behält die Maße des Ausgangsbildes', () async {
    final quelle = legeGrau('gross.png', kante: 640);

    final bytes = await DevelopRender.rendere(
      quelle,
      adjustments: const DevelopAdjustments(contrast: 0.3),
      maxDimension: 320,
    );

    final bild = img.decodeImage(bytes!)!;
    expect(bild.width, 320);
    expect(bild.height, 320);
  });

  // Flutter tastet Bildabtaster ohne Angabe beim nächsten Pixel ab. Der
  // Farbwürfel ist aber auf Interpolation gebaut; ohne sie zerlegte ein
  // Farbmischer bis 3.29 diesen Verlauf in 56 Stufen mit Sprüngen bis 14.
  test('ein Farbmischer lässt einen Verlauf stetig', () async {
    final verlauf = img.Image(width: 512, height: 8);
    for (var x = 0; x < 512; x++) {
      for (var y = 0; y < 8; y++) {
        verlauf.setPixelRgb(
          x,
          y,
          40 + x * 180 ~/ 512,
          40 + x * 140 ~/ 512,
          40 + x * 100 ~/ 512,
        );
      }
    }
    final quelle = File(p.join(temp.path, 'verlauf.png'))
      ..writeAsBytesSync(img.encodePng(verlauf));
    final bild = img.decodeJpg(
      (await DevelopRender.rendere(
        quelle,
        adjustments: const DevelopAdjustments(
          colorMixer: ColorMixer({
            ColorBand.orange: BandAnpassung(saettigung: 0.5),
          }),
        ),
        quality: 100,
      ))!,
    )!;
    var groessterSprung = 0;
    for (var x = 1; x < 512; x++) {
      final sprung = (bild.getPixel(x, 4).r - bild.getPixel(x - 1, 4).r)
          .abs()
          .toInt();
      if (sprung > groessterSprung) groessterSprung = sprung;
    }
    expect(groessterSprung, lessThanOrEqualTo(4));
  });

  group('Schärfe, Rauschminderung, Klarheit, Vignette', () {
    late File tafel;
    setUp(() {
      tafel = File(p.join(temp.path, 'tafel.png'))
        ..writeAsBytesSync(img.encodePng(entwickelnTafel()));
    });

    Future<img.Image> rendere(
      DevelopAdjustments a, {
      List<MaskAdjustmentLayer> masks = const [],
    }) async => img.decodeJpg(
      (await DevelopRender.rendere(
        tafel,
        adjustments: a,
        masks: masks,
        quality: 100,
      ))!,
    )!;

    // Die Sollwerte hat Core Image gerechnet (test/fixtures/README.md). Dass
    // der GPU-Weg sie trifft, ist der eigentliche Nachweis: Die Formeln
    // sind an Core Image gemessen, nicht von Apple beschrieben. Hier
    // rechnet der Software-Renderer des Testprozesses; den echten
    // GPU-Renderer prüft integration_test/nachbarregler_test.dart.
    test('liegen nahe an Core Image', () async {
      final neutral = await rendere(const DevelopAdjustments());
      final faelle = <String, (DevelopAdjustments, List<MaskAdjustmentLayer>)>{
        for (final e in entwickelnFaelle.entries) e.key: (e.value, const []),
      };
      final maske = File(p.join(temp.path, 'maske.png'))
        ..writeAsBytesSync(img.encodePng(entwickelnTafelMaske()));
      faelle['maske'] = (
        maskenfallGlobal,
        [
          MaskAdjustmentLayer(
            maskFilePath: maske.path,
            adjustments: maskenfallMaske,
          ),
        ],
      );
      for (final MapEntry(key: name, value: (werte, masks)) in faelle.entries) {
        final soll = img.decodeJpg(
          File('test/fixtures/entwickeln_referenz/$name.jpg').readAsBytesSync(),
        )!;
        final d = abweichung(await rendere(werte, masks: masks), soll);
        final ohne = abweichung(neutral, soll);
        expect(
          d.mittel,
          lessThan(math.min(2.0, ohne.mittel * 0.35)),
          reason:
              '$name: mittlere Abweichung ${d.mittel.toStringAsFixed(2)} '
              '(ohne Filter ${ohne.mittel.toStringAsFixed(2)})',
        );
      }
    });

    test(
      'Vignette: positiv dunkelt die Ecken ab, negativ hellt sie auf',
      () async {
        final grau = legeGrau('grau.png');
        Future<img.Image> mit(double v) async => img.decodeJpg(
          (await DevelopRender.rendere(
            grau,
            adjustments: DevelopAdjustments(vignette: v),
            quality: 100,
          ))!,
        )!;
        final dunkel = await mit(0.6);
        final hell = await mit(-0.6);
        expect(dunkel.getPixel(2, 2).luminance, lessThan(110));
        expect(hell.getPixel(2, 2).luminance, greaterThan(150));
        // Die Mitte bleibt, wie sie war.
        expect(dunkel.getPixel(128, 128).luminance, closeTo(128, 2));
        expect(hell.getPixel(128, 128).luminance, closeTo(128, 2));
      },
    );

    // Bis 3.29 schärfte negative Klarheit unter macOS ebenfalls (CIMix
    // in vertauschter Richtung). Gemessen wird der Kontrast im
    // grossflächigen Muster der unteren Tafelhälfte.
    test(
      'Klarheit: positiv hebt, negativ senkt den Kontrast über Flächen',
      () async {
        // Schwingungsweite des Musters entlang zweier Spalten, an denen es
        // voll ausschlägt. Die Streuung über die ganze Fläche taugte nicht:
        // Sie hängt am Verlauf, und den lässt die Klarheit fast in Ruhe.
        // Der Radius wächst mit dem Bild; bei 400 Punkten Kante sind es 5,
        // und auf das Muster (120 × 90) wirkt die Klarheit mit gut 10 %.
        double kontrast(img.Image b) {
          var summe = 0.0;
          for (final x in [30, 330]) {
            final spalte = [
              for (var y = 140; y < 240; y++)
                b.getPixel(x, y).luminance.toDouble(),
            ];
            summe += spalte.reduce(math.max) - spalte.reduce(math.min);
          }
          return summe / 2;
        }

        final neutral = kontrast(await rendere(const DevelopAdjustments()));
        expect(
          kontrast(await rendere(const DevelopAdjustments(clarity: 0.8))),
          greaterThan(neutral * 1.08),
        );
        expect(
          kontrast(await rendere(const DevelopAdjustments(clarity: -0.8))),
          lessThan(neutral * 0.98),
        );
      },
    );

    // So speichert die App Masken: deckend, Graustufen, weiß = ausgewählt.
    // Bis 3.29 las der Linux- und Windows-Weg den Alphakanal – der ist hier
    // überall voll, und die Maske wirkte auf das ganze Bild.
    test('eine deckende Graustufenmaske wirkt nur, wo sie weiß ist', () async {
      final quelle = legeGrau('grau.png', kante: 200);
      final maske = img.Image(width: 200, height: 200);
      img.fill(maske, color: img.ColorRgb8(0, 0, 0));
      img.fillRect(
        maske,
        x1: 0,
        y1: 0,
        x2: 99,
        y2: 199,
        color: img.ColorRgb8(255, 255, 255),
      );
      final maskeDatei = File(p.join(temp.path, 'maske_grau.png'))
        ..writeAsBytesSync(img.encodePng(maske));
      final bild = img.decodeJpg(
        (await DevelopRender.rendere(
          quelle,
          adjustments: const DevelopAdjustments(),
          masks: [
            MaskAdjustmentLayer(
              maskFilePath: maskeDatei.path,
              adjustments: const DevelopAdjustments(exposure: 1.5),
            ),
          ],
        ))!,
      )!;
      expect(bild.getPixel(40, 100).luminance, greaterThan(158));
      expect(bild.getPixel(160, 100).luminance, closeTo(128, 6));
    });

    // Bis 3.29 rechnete jede Maske auf dem Original: Innerhalb der Maske
    // fehlten die globalen Regler. Eine Maske, die nur schärft, nahm dort
    // die Belichtung des ganzen Bildes zurück.
    test('eine Maske wirkt auf das schon entwickelte Bild', () async {
      final quelle = legeGrau('grau.png', kante: 200);
      final maske = img.Image(width: 200, height: 200);
      img.fill(maske, color: img.ColorRgb8(255, 255, 255));
      final maskeDatei = File(p.join(temp.path, 'maske_voll.png'))
        ..writeAsBytesSync(img.encodePng(maske));
      final bild = img.decodeJpg(
        (await DevelopRender.rendere(
          quelle,
          adjustments: const DevelopAdjustments(exposure: 1),
          masks: [
            MaskAdjustmentLayer(
              maskFilePath: maskeDatei.path,
              adjustments: const DevelopAdjustments(sharpness: 0.5),
            ),
          ],
        ))!,
      )!;
      // Grau 128 eine Blende heller: linear 0,216 → 0,431, sRGB rund 175.
      expect(bild.getPixel(100, 100).luminance, closeTo(175, 4));
    });
  });

  test('eine Maske wirkt nur dort, wo sie deckt', () async {
    final quelle = legeGrau('grau.png', kante: 200);

    // Maske: linke Hälfte deckend, rechte Hälfte durchsichtig.
    final maske = img.Image(width: 200, height: 200, numChannels: 4);
    img.fill(maske, color: img.ColorRgba8(0, 0, 0, 0));
    img.fillRect(
      maske,
      x1: 0,
      y1: 0,
      x2: 99,
      y2: 199,
      color: img.ColorRgba8(255, 255, 255, 255),
    );
    final maskeDatei = File(p.join(temp.path, 'maske.png'))
      ..writeAsBytesSync(img.encodePng(maske));

    final bytes = await DevelopRender.rendere(
      quelle,
      adjustments: const DevelopAdjustments(),
      masks: [
        MaskAdjustmentLayer(
          maskFilePath: maskeDatei.path,
          adjustments: const DevelopAdjustments(exposure: 1.5),
        ),
      ],
    );

    final bild = img.decodeImage(bytes!)!;
    final links = bild.getPixel(40, 100).luminance;
    final rechts = bild.getPixel(160, 100).luminance;

    expect(
      links,
      greaterThan(rechts + 30),
      reason: 'die Maskenwirkung ist über das ganze Bild gelaufen',
    );
    expect(rechts, closeTo(128, 6), reason: 'ausserhalb der Maske unverändert');
  });

  test('Lichter senken helle Flaechen, Schatten lassen sie in Ruhe', () async {
    // Der Regler, der bis 1.9.5 fehlte. Geprueft an einer hellen Flaeche:
    // Dort greift die Lichter-Gewichtung voll, die Schatten-Gewichtung gar
    // nicht - eine Verwechslung der beiden faellt damit auf.
    final hell = legeGrau('hell.png', wert: 230);

    final neutral = await DevelopRender.rendere(
      hell,
      adjustments: const DevelopAdjustments(),
    );
    final zurueck = await DevelopRender.rendere(
      hell,
      adjustments: const DevelopAdjustments(highlights: -1),
    );
    final mitSchatten = await DevelopRender.rendere(
      hell,
      adjustments: const DevelopAdjustments(shadows: -1),
    );

    final n = mittlereHelligkeit(neutral!);
    expect(
      mittlereHelligkeit(zurueck!),
      lessThan(n - 10),
      reason: 'Lichter -1 muss eine helle Flaeche deutlich absenken',
    );
    expect(
      mittlereHelligkeit(mitSchatten!),
      closeTo(n, 6),
      reason: 'der Schatten-Regler darf hier fast nichts tun',
    );
  });

  test('Lichter heben helle Flaechen auch an', () async {
    // Die Gegenrichtung. Sie ist der Grund, warum unter macOS ein eigener
    // Kern statt CIHighlightShadowAdjust benutzt wird - das kann nur
    // zuruecknehmen (siehe ImageConverter.swift, lichterKern).
    //
    // Gemessen an dieser Stelle: 220 neutral -> 244 bei Lichter +1.
    final hell = legeGrau('hell2.png', wert: 220);

    final neutral = await DevelopRender.rendere(
      hell,
      adjustments: const DevelopAdjustments(),
    );
    final heller = await DevelopRender.rendere(
      hell,
      adjustments: const DevelopAdjustments(highlights: 1),
    );

    expect(
      mittlereHelligkeit(heller!),
      greaterThan(mittlereHelligkeit(neutral!) + 10),
    );
  });

  test('Mitteltoene bleiben unberuehrt', () {
    // Die Eigenschaft, die einen Lichter-Regler von der Belichtung
    // unterscheidet: Bei mittlerem Grau ist die Gewichtung null, in beide
    // Richtungen. Gemessen: 128 bleibt 128 bei -1 wie bei +1.
    return () async {
      final grau = legeGrau('mitte.png', wert: 128);
      for (final wert in [-1.0, 1.0]) {
        final raus = await DevelopRender.rendere(
          grau,
          adjustments: DevelopAdjustments(highlights: wert),
        );
        expect(
          mittlereHelligkeit(raus!),
          closeTo(128, 2),
          reason: 'Lichter $wert darf Mitteltoene nicht anfassen',
        );
      }
    }();
  });

  test('das Endergebnis traegt KEINE Beschneidungsmarken', () async {
    // Der wichtigste Test dieser Datei. Derselbe Shader zeichnet die
    // Vorschau und rendert unter Linux und Windows die Endergebnisse.
    // Stuende die Warnung im Renderpfad an, traege jede exportierte Datei
    // rote und blaue Flaechen - und zwar genau dort, wo das Bild am
    // ehesten hinschaut.
    //
    // Geprueft an einem Bild, das garantiert beschneidet: reines Weiss
    // neben reinem Schwarz. Waere die Warnung an, muesste hier alles rot
    // bzw. blau sein.
    final bild = img.Image(width: 128, height: 128);
    img.fill(bild, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(
      bild,
      x1: 0,
      y1: 0,
      x2: 63,
      y2: 127,
      color: img.ColorRgb8(0, 0, 0),
    );
    final quelle = File(p.join(temp.path, 'extrem.png'))
      ..writeAsBytesSync(img.encodePng(bild));

    final bytes = await DevelopRender.rendere(
      quelle,
      adjustments: const DevelopAdjustments(),
    );
    final raus = img.decodeImage(bytes!)!;

    // In der Mitte je Haelfte nachsehen - die Kante selbst ist durch die
    // JPEG-Kompression weich.
    final schwarz = raus.getPixel(20, 64);
    final weiss = raus.getPixel(108, 64);
    expect(schwarz.r, lessThan(40), reason: 'Schwarz muss schwarz bleiben');
    expect(
      schwarz.b,
      lessThan(80),
      reason: 'blau eingefaerbt heisst: die Warnung ist im Renderpfad an',
    );
    expect(weiss.r, greaterThan(215), reason: 'Weiss muss weiss bleiben');
    expect(
      weiss.g,
      greaterThan(215),
      reason: 'nur rot heisst: die Warnung ist im Renderpfad an',
    );
  });

  test('ein grosses Bild kommt in Zielgroesse heraus', () async {
    // Der Zweig, den die 256er Bilder oben nie betreten: Ist das Foto
    // groesser als die Zielkante, muss verkleinert werden.
    //
    // Und genau dort steckte ein Fehler, den keiner dieser Tests sehen
    // konnte: Um die Groesse zu erfahren, wurde das Bild ZUERST ganz
    // dekodiert und nachgemessen - an einem 24-Megapixel-Foto 348 ms und
    // 96 MB, fuer zwei Zahlen, die im Dateikopf stehen. Die kleinen
    // Testbilder gingen an dem Zweig vorbei.
    final datei = legeGrau('gross.png', kante: 2000);
    final raus = await DevelopRender.rendere(
      datei,
      adjustments: const DevelopAdjustments(),
      maxDimension: 800,
    );
    expect(raus, isNotNull);
    final gerendert = img.decodeJpg(raus!)!;
    expect(
      gerendert.width,
      800,
      reason: 'sonst wurde in Originalgroesse gerechnet',
    );
    expect(gerendert.height, 800, reason: 'quadratisch bleibt quadratisch');
  });

  test('ein kleines Bild wird NICHT hochgerechnet', () async {
    // Die Gegenrichtung. Hochrechnen braechte keine Bildinformation,
    // kostete aber Speicher - und aus einem 256er Bild wuerde ein 800er,
    // das nur weicher aussieht.
    final datei = legeGrau('klein.png', kante: 256);
    final raus = await DevelopRender.rendere(
      datei,
      adjustments: const DevelopAdjustments(),
      maxDimension: 800,
    );
    expect(raus, isNotNull);
    expect(img.decodeJpg(raus!)!.width, 256);
  });

  test('setzt jeden angebotenen Desktop-Regler um', () {
    expect(DevelopRender.ohneWirkung, isEmpty);
    expect(
      DevelopRender.gesetztOhneWirkung(
        const DevelopAdjustments(sharpness: 0.5, vignette: -0.3),
      ),
      isEmpty,
    );
  });
}
