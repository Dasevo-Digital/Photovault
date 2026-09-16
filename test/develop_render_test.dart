import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/develop_render.dart';
import 'package:photo_vault/services/native_image_converter.dart';

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

    final bytes = await DevelopRender.rendere(quelle,
        adjustments: const DevelopAdjustments());

    expect(bytes, isNotNull, reason: 'der Shader-Weg lieferte gar nichts');
    // JPEG rundet, deshalb eine kleine Toleranz – aber es muss dasselbe
    // Grau sein und nicht etwa Schwarz.
    expect(mittlereHelligkeit(bytes!), closeTo(128, 3));
  });

  test('Belichtung hellt auf, und zwar in der richtigen Grössenordnung', () async {
    final quelle = legeGrau('grau.png');

    final neutral = await DevelopRender.rendere(quelle,
        adjustments: const DevelopAdjustments());
    final heller = await DevelopRender.rendere(quelle,
        adjustments: const DevelopAdjustments(exposure: 1));
    final dunkler = await DevelopRender.rendere(quelle,
        adjustments: const DevelopAdjustments(exposure: -1));

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
  });

  test('das Ergebnis behält die Maße des Ausgangsbildes', () async {
    final quelle = legeGrau('gross.png', kante: 640);

    final bytes = await DevelopRender.rendere(quelle,
        adjustments: const DevelopAdjustments(contrast: 0.3), maxDimension: 320);

    final bild = img.decodeImage(bytes!)!;
    expect(bild.width, 320);
    expect(bild.height, 320);
  });

  test('eine Maske wirkt nur dort, wo sie deckt', () async {
    final quelle = legeGrau('grau.png', kante: 200);

    // Maske: linke Hälfte deckend, rechte Hälfte durchsichtig.
    final maske = img.Image(width: 200, height: 200, numChannels: 4);
    img.fill(maske, color: img.ColorRgba8(0, 0, 0, 0));
    img.fillRect(maske,
        x1: 0, y1: 0, x2: 99, y2: 199, color: img.ColorRgba8(255, 255, 255, 255));
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

    expect(links, greaterThan(rechts + 30),
        reason: 'die Maskenwirkung ist über das ganze Bild gelaufen');
    expect(rechts, closeTo(128, 6), reason: 'ausserhalb der Maske unverändert');
  });

  test('Lichter senken helle Flaechen, Schatten lassen sie in Ruhe', () async {
    // Der Regler, der bis 1.9.5 fehlte. Geprueft an einer hellen Flaeche:
    // Dort greift die Lichter-Gewichtung voll, die Schatten-Gewichtung gar
    // nicht - eine Verwechslung der beiden faellt damit auf.
    final hell = legeGrau('hell.png', wert: 230);

    final neutral = await DevelopRender.rendere(hell,
        adjustments: const DevelopAdjustments());
    final zurueck = await DevelopRender.rendere(hell,
        adjustments: const DevelopAdjustments(highlights: -1));
    final mitSchatten = await DevelopRender.rendere(hell,
        adjustments: const DevelopAdjustments(shadows: -1));

    final n = mittlereHelligkeit(neutral!);
    expect(mittlereHelligkeit(zurueck!), lessThan(n - 10),
        reason: 'Lichter -1 muss eine helle Flaeche deutlich absenken');
    expect(mittlereHelligkeit(mitSchatten!), closeTo(n, 6),
        reason: 'der Schatten-Regler darf hier fast nichts tun');
  });

  test('Lichter heben helle Flaechen auch an', () async {
    // Die Gegenrichtung. Sie ist der Grund, warum unter macOS ein eigener
    // Kern statt CIHighlightShadowAdjust benutzt wird - das kann nur
    // zuruecknehmen (siehe ImageConverter.swift, lichterKern).
    //
    // Gemessen an dieser Stelle: 220 neutral -> 244 bei Lichter +1.
    final hell = legeGrau('hell2.png', wert: 220);

    final neutral = await DevelopRender.rendere(hell,
        adjustments: const DevelopAdjustments());
    final heller = await DevelopRender.rendere(hell,
        adjustments: const DevelopAdjustments(highlights: 1));

    expect(mittlereHelligkeit(heller!),
        greaterThan(mittlereHelligkeit(neutral!) + 10));
  });

  test('Mitteltoene bleiben unberuehrt', () {
    // Die Eigenschaft, die einen Lichter-Regler von der Belichtung
    // unterscheidet: Bei mittlerem Grau ist die Gewichtung null, in beide
    // Richtungen. Gemessen: 128 bleibt 128 bei -1 wie bei +1.
    return () async {
      final grau = legeGrau('mitte.png', wert: 128);
      for (final wert in [-1.0, 1.0]) {
        final raus = await DevelopRender.rendere(grau,
            adjustments: DevelopAdjustments(highlights: wert));
        expect(mittlereHelligkeit(raus!), closeTo(128, 2),
            reason: 'Lichter $wert darf Mitteltoene nicht anfassen');
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
    img.fillRect(bild, x1: 0, y1: 0, x2: 63, y2: 127,
        color: img.ColorRgb8(0, 0, 0));
    final quelle = File(p.join(temp.path, 'extrem.png'))
      ..writeAsBytesSync(img.encodePng(bild));

    final bytes = await DevelopRender.rendere(quelle,
        adjustments: const DevelopAdjustments());
    final raus = img.decodeImage(bytes!)!;

    // In der Mitte je Haelfte nachsehen - die Kante selbst ist durch die
    // JPEG-Kompression weich.
    final schwarz = raus.getPixel(20, 64);
    final weiss = raus.getPixel(108, 64);
    expect(schwarz.r, lessThan(40), reason: 'Schwarz muss schwarz bleiben');
    expect(schwarz.b, lessThan(80),
        reason: 'blau eingefaerbt heisst: die Warnung ist im Renderpfad an');
    expect(weiss.r, greaterThan(215), reason: 'Weiss muss weiss bleiben');
    expect(weiss.g, greaterThan(215),
        reason: 'nur rot heisst: die Warnung ist im Renderpfad an');
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
    final raus = await DevelopRender.rendere(datei,
        adjustments: const DevelopAdjustments(), maxDimension: 800);
    expect(raus, isNotNull);
    final gerendert = img.decodeJpg(raus!)!;
    expect(gerendert.width, 800,
        reason: 'sonst wurde in Originalgroesse gerechnet');
    expect(gerendert.height, 800, reason: 'quadratisch bleibt quadratisch');
  });

  test('ein kleines Bild wird NICHT hochgerechnet', () async {
    // Die Gegenrichtung. Hochrechnen braechte keine Bildinformation,
    // kostete aber Speicher - und aus einem 256er Bild wuerde ein 800er,
    // das nur weicher aussieht.
    final datei = legeGrau('klein.png', kante: 256);
    final raus = await DevelopRender.rendere(datei,
        adjustments: const DevelopAdjustments(), maxDimension: 800);
    expect(raus, isNotNull);
    expect(img.decodeJpg(raus!)!.width, 256);
  });

  test('sagt, welche Regler dieser Weg nicht umsetzt', () {
    // Ein Regler, der sich bewegen lässt und nichts tut, ist die
    // unangenehmste Art von Fehler – deshalb benennt der Dienst sie, statt
    // sie zu nähern.
    expect(DevelopRender.ohneWirkung, contains(Entwicklungsregler.schaerfe));
    expect(DevelopRender.ohneWirkung, contains(Entwicklungsregler.vignettierung));

    expect(DevelopRender.gesetztOhneWirkung(const DevelopAdjustments()), isEmpty);
    expect(
        DevelopRender.gesetztOhneWirkung(
            const DevelopAdjustments(exposure: 1, contrast: 0.5)),
        isEmpty,
        reason: 'diese beiden setzt der Shader sehr wohl um');
    expect(
        DevelopRender.gesetztOhneWirkung(
            const DevelopAdjustments(sharpness: 0.5, vignette: -0.3)),
        [Entwicklungsregler.schaerfe, Entwicklungsregler.vignettierung]);
  });
}
