import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/services/jpeg_icc.dart';
import 'package:kern/services/wasserzeichen.dart';

/// Das Einrechnen des Wasserzeichens im Kern (#497) – dieselbe Rechnung für
/// Export, Fotobuch und die Bilder geteilter Links.
void main() {
  img.Image grau(int breite, int hoehe, [int wert = 100]) =>
      img.Image(width: breite, height: hoehe)
        ..clear(img.ColorRgb8(wert, wert, wert));

  /// Ein deckend rotes Zeichen.
  img.Image rot(int breite, int hoehe) =>
      img.Image(width: breite, height: hoehe, numChannels: 4)
        ..clear(img.ColorRgba8(255, 0, 0, 255));

  Uint8List png(img.Image bild) => Uint8List.fromList(img.encodePng(bild));

  group('wo das Zeichen steht', () {
    ({int x, int y, int breite, int hoehe})? rechteck(
      Wasserzeichen w, {
      int bildBreite = 1000,
      int bildHoehe = 500,
      int zeichenBreite = 200,
      int zeichenHoehe = 100,
    }) => wasserzeichenRechteck(
      bildBreite: bildBreite,
      bildHoehe: bildHoehe,
      zeichenBreite: zeichenBreite,
      zeichenHoehe: zeichenHoehe,
      wasserzeichen: w,
    );

    test('Vorgabe: unten rechts, 20 % der Breite, 3 % Rand', () {
      const w = Wasserzeichen(text: 'x');
      expect(w.lage, Wasserzeichenlage.untenRechts);
      // 200 × 100 Pixel, Rand 30: rechts bei 1000 − 30, unten bei 500 − 30.
      expect(rechteck(w), (x: 770, y: 370, breite: 200, hoehe: 100));
    });

    test('alle neun Ankerpunkte', () {
      final erwartet = {
        Wasserzeichenlage.obenLinks: (30, 30),
        Wasserzeichenlage.oben: (400, 30),
        Wasserzeichenlage.obenRechts: (770, 30),
        Wasserzeichenlage.links: (30, 200),
        Wasserzeichenlage.mitte: (400, 200),
        Wasserzeichenlage.rechts: (770, 200),
        Wasserzeichenlage.untenLinks: (30, 370),
        Wasserzeichenlage.unten: (400, 370),
        Wasserzeichenlage.untenRechts: (770, 370),
      };
      for (final MapEntry(key: lage, value: (x, y)) in erwartet.entries) {
        final r = rechteck(Wasserzeichen(text: 'x', lage: lage))!;
        expect((r.x, r.y), (x, y), reason: lage.name);
      }
    });

    test('Grösse und Rand sind Anteile der Bildbreite', () {
      final r = rechteck(
        const Wasserzeichen(text: 'x', groesse: 0.5, rand: 0.1),
        bildBreite: 400,
        bildHoehe: 400,
      )!;
      // 200 breit, halb so hoch; Rand 40.
      expect(r, (x: 160, y: 260, breite: 200, hoehe: 100));
      // Ohne Rand sitzt es bündig in der Ecke.
      expect(
        rechteck(
          const Wasserzeichen(text: 'x', rand: 0),
          bildBreite: 400,
          bildHoehe: 400,
        ),
        (x: 320, y: 360, breite: 80, hoehe: 40),
      );
    });

    test('ein zu hohes Zeichen wird kleiner, nicht beschnitten', () {
      // Ein hohes Logo (1 : 4) mit 60 % der Breite auf einem Querformat.
      final r = rechteck(
        const Wasserzeichen(text: 'x', groesse: 0.6, rand: 0.02),
        bildBreite: 1000,
        bildHoehe: 300,
        zeichenBreite: 100,
        zeichenHoehe: 400,
      )!;
      // Platz in der Höhe: 300 − 2 · 20 = 260.
      expect(r.hoehe, 260);
      expect(r.breite, 65);
      expect(r.y + r.hoehe, 300 - 20);
      expect(r.x + r.breite, 1000 - 20);
    });

    test('Werte ausserhalb der Grenzen gelten als die Grenze', () {
      final r = rechteck(
        const Wasserzeichen(text: 'x', groesse: 5, rand: 3),
        bildBreite: 1000,
        bildHoehe: 1000,
      )!;
      expect(r.breite, (1000 * Wasserzeichen.groesseMax).round());
      expect(1000 - r.x - r.breite, (1000 * Wasserzeichen.randMax).round());
    });

    test('sehr kleine Bilder: Rand höchstens ein Viertel, sonst nichts', () {
      // 10 × 10: Rand 3 % = 0, Zeichen 2 × 1 Pixel.
      expect(
        rechteck(const Wasserzeichen(text: 'x'), bildBreite: 10, bildHoehe: 10),
        (x: 8, y: 9, breite: 2, hoehe: 1),
      );
      // 4 × 4 mit 15 % Rand: der Rand bleibt bei einem Viertel der Seite.
      final r = rechteck(
        const Wasserzeichen(text: 'x', groesse: 0.6, rand: 0.15),
        bildBreite: 4,
        bildHoehe: 4,
      );
      expect(r, isNotNull);
      expect(r!.x, greaterThanOrEqualTo(1));
      // 1 × 1: Für ein Zeichen bleibt kein Pixel – kein Absturz, nichts.
      expect(
        rechteck(const Wasserzeichen(text: 'x'), bildBreite: 1, bildHoehe: 1),
        isNull,
      );
      expect(
        rechteck(const Wasserzeichen(text: 'x'), zeichenBreite: 0),
        isNull,
      );
    });

    test('sehr grosse Bilder', () {
      final r = rechteck(
        const Wasserzeichen(text: 'x'),
        bildBreite: 12000,
        bildHoehe: 8000,
        zeichenBreite: 1600,
        zeichenHoehe: 400,
      )!;
      expect(r, (x: 9240, y: 7040, breite: 2400, hoehe: 600));
    });
  });

  group('einrechnen', () {
    test('deckend und halb durchsichtig, nur im Rechteck', () {
      final bild = grau(100, 50);
      rechneWasserzeichenEin(
        bild,
        rot(20, 10),
        const Wasserzeichen(text: 'x', rand: 0, deckkraft: 1),
      );
      // Rechteck: x 80…99, y 40…49.
      expect(bild.getPixel(90, 45).r, 255);
      expect(bild.getPixel(90, 45).g, 0);
      expect(bild.getPixel(79, 45).r, 100, reason: 'links daneben');
      expect(bild.getPixel(90, 39).r, 100, reason: 'darüber');

      final halb = grau(100, 50);
      rechneWasserzeichenEin(
        halb,
        rot(20, 10),
        const Wasserzeichen(text: 'x', rand: 0, deckkraft: 0.5),
      );
      // 100 · 0,5 + 255 · 0,5 = 177,5; Grün 100 · 0,5 = 50.
      expect(halb.getPixel(90, 45).r, inInclusiveRange(177, 178));
      expect(halb.getPixel(90, 45).g, 50);
    });

    test('die Deckung des Zeichens zählt mit', () {
      final zeichen = img.Image(width: 20, height: 10, numChannels: 4)
        ..clear(img.ColorRgba8(255, 255, 255, 128));
      final bild = grau(100, 50, 0);
      rechneWasserzeichenEin(
        bild,
        zeichen,
        const Wasserzeichen(text: 'x', rand: 0, deckkraft: 1),
      );
      // Weiss mit halber Deckung auf Schwarz.
      expect(bild.getPixel(90, 45).r, inInclusiveRange(127, 129));
      // Ganz durchsichtig: nichts.
      final leer = img.Image(width: 20, height: 10, numChannels: 4)
        ..clear(img.ColorRgba8(255, 255, 255, 0));
      final unberuehrt = grau(100, 50, 0);
      rechneWasserzeichenEin(
        unberuehrt,
        leer,
        const Wasserzeichen(text: 'x', rand: 0, deckkraft: 1),
      );
      expect(unberuehrt.getPixel(90, 45).r, 0);
    });

    test('verkleinert ohne dunklen Saum an durchsichtigen Kanten', () {
      // Ein weisses Logo, dessen durchsichtiger Teil (wie üblich) schwarz
      // gespeichert ist – abwechselnd Spalten. Verkleinert auf die Hälfte
      // liegt in jedem Pixel ein halb deckendes Weiss. Ohne Vormultiplizieren
      // mischte sich das unsichtbare Schwarz hinein, und auf weissem Grund
      // erschiene Grau.
      final zeichen = img.Image(width: 40, height: 20, numChannels: 4);
      for (final p in zeichen) {
        p
          ..r = p.x.isEven ? 255 : 0
          ..g = p.x.isEven ? 255 : 0
          ..b = p.x.isEven ? 255 : 0
          ..a = p.x.isEven ? 255 : 0;
      }
      final bild = grau(100, 50, 255);
      rechneWasserzeichenEin(
        bild,
        zeichen,
        const Wasserzeichen(text: 'x', rand: 0, deckkraft: 1),
      );
      expect(bild.getPixel(90, 45).r, greaterThanOrEqualTo(254));
    });

    test('die Farbe durchsichtiger Stellen färbt nicht ab', () {
      // Umgekehrt: ein schwarzes Logo, dessen durchsichtiger Teil weiss
      // gespeichert ist. Verkleinert ist jedes Pixel halb schwarz, halb
      // nichts – auf Weiss also mittleres Grau. Ginge die unsichtbare
      // Farbe mit ein, bliebe es weiss.
      final zeichen = img.Image(width: 40, height: 20, numChannels: 4);
      for (final p in zeichen) {
        final deckend = p.x.isEven;
        p
          ..r = deckend ? 0 : 255
          ..g = deckend ? 0 : 255
          ..b = deckend ? 0 : 255
          ..a = deckend ? 255 : 0;
      }
      final bild = grau(100, 50, 255);
      rechneWasserzeichenEin(
        bild,
        zeichen,
        const Wasserzeichen(text: 'x', rand: 0, deckkraft: 1),
      );
      expect(bild.getPixel(90, 45).r, inInclusiveRange(125, 130));
    });

    test('ein winziges Bild bleibt, wie es ist', () {
      final bild = grau(1, 1);
      rechneWasserzeichenEin(bild, rot(20, 10), const Wasserzeichen(text: 'x'));
      expect(bild.getPixel(0, 0).r, 100);
    });

    test('ein grosses Bild – nur das Rechteck wird angefasst', () {
      final bild = grau(6000, 4000);
      rechneWasserzeichenEin(
        bild,
        rot(400, 100),
        const Wasserzeichen(text: 'x'),
      );
      // 1200 × 300 Pixel, Rand 180; Deckkraft der Vorgabe 60 %:
      // 100 · 0,4 + 255 · 0,6 = 193.
      expect(
        bild.getPixel(6000 - 181, 4000 - 181).r,
        inInclusiveRange(192, 194),
      );
      expect(bild.getPixel(6000 - 179, 4000 - 179).r, 100);
      expect(bild.getPixel(6000 - 180 - 1201, 4000 - 181).r, 100);
    });
  });

  group('als JPEG', () {
    Uint8List jpeg(img.Image bild) => Uint8List.fromList(img.encodeJpg(bild));

    test('Farbprofil bleibt, das Zeichen sitzt unten rechts', () {
      final profil = Uint8List.fromList(List.generate(300, (i) => i % 251));
      final rein = JpegIcc.schreiben(jpeg(grau(200, 100)), profil);
      final raus = jpegMitWasserzeichen((
        jpeg: rein,
        zeichen: png(rot(40, 20)),
        wasserzeichen: const Wasserzeichen(text: 'x', rand: 0, deckkraft: 1),
        qualitaet: 95,
      ));
      expect(JpegIcc.lesen(raus), profil);
      final bild = img.decodeJpg(raus)!;
      expect(bild.getPixel(180, 90).r, greaterThan(200));
      expect(bild.getPixel(180, 90).g, lessThan(60));
      expect(bild.getPixel(20, 10).r, inInclusiveRange(95, 105));
    });

    test('eine Drehung in den EXIF-Angaben wird vorher eingerechnet', () {
      // Gespeichert hochkant (100 × 200), angezeigt um 90° gedreht – also
      // quer. „Unten rechts“ meint die Ecke, die der Betrachter sieht.
      final bild = grau(100, 200)..exif.imageIfd.orientation = 6;
      final raus = jpegMitWasserzeichen((
        jpeg: jpeg(bild),
        zeichen: png(rot(40, 20)),
        wasserzeichen: const Wasserzeichen(text: 'x', rand: 0, deckkraft: 1),
        qualitaet: 95,
      ));
      final gelesen = img.decodeJpg(raus)!;
      expect((gelesen.width, gelesen.height), (200, 100));
      expect(gelesen.exif.imageIfd.orientation ?? 1, 1);
      expect(gelesen.getPixel(190, 95).r, greaterThan(200));
      expect(gelesen.getPixel(10, 5).r, inInclusiveRange(95, 105));
    });

    test('ein unlesbares Zeichen ist ein Fehler, kein Bild ohne Zeichen', () {
      expect(
        () => jpegMitWasserzeichen((
          jpeg: jpeg(grau(20, 20)),
          zeichen: Uint8List.fromList([1, 2, 3]),
          wasserzeichen: const Wasserzeichen(text: 'x'),
          qualitaet: 90,
        )),
        throwsFormatException,
      );
    });
  });

  group('Einstellungen als JSON', () {
    test('hin und zurück', () {
      final logo = png(rot(4, 2));
      final w = Wasserzeichen(
        art: Wasserzeichenart.bild,
        text: '© 2026',
        bild: logo,
        lage: Wasserzeichenlage.obenLinks,
        groesse: 0.35,
        deckkraft: 0.8,
        rand: 0.05,
      );
      final zurueck = Wasserzeichen.ausKodiert(w.kodiert())!;
      expect(zurueck.art, Wasserzeichenart.bild);
      expect(zurueck.text, '© 2026');
      expect(zurueck.bild, logo);
      expect(zurueck.lage, Wasserzeichenlage.obenLinks);
      expect(
        (zurueck.groesse, zurueck.deckkraft, zurueck.rand),
        (0.35, 0.8, 0.05),
      );
      expect(zurueck.kennung, w.kennung);
      expect(
        w.kopieMit(groesse: 0.36).kennung,
        isNot(w.kennung),
        reason: 'eine andere Grösse ist ein anderes Bild',
      );
    });

    test('nachsichtig: fehlende Werte, Grenzen, unbekannte Lage', () {
      final w = Wasserzeichen.ausJson({
        'art': 'text',
        'text': 'x' * 500,
        'lage': 'irgendwo',
        'groesse': 9,
        'deckkraft': -1,
      })!;
      expect(w.text.length, Wasserzeichen.hoechstensText);
      expect(w.lage, Wasserzeichenlage.untenRechts);
      expect(w.groesse, Wasserzeichen.groesseMax);
      expect(w.deckkraft, Wasserzeichen.deckkraftMin);
      expect(w.rand, Wasserzeichen.vorgabeRand);
    });

    test('nichts Einrechenbares heisst: kein Wasserzeichen', () {
      expect(Wasserzeichen.ausKodiert(null), isNull);
      expect(Wasserzeichen.ausKodiert(''), isNull);
      expect(Wasserzeichen.ausKodiert('{kaputt'), isNull);
      expect(Wasserzeichen.ausKodiert('[]'), isNull);
      expect(Wasserzeichen.ausJson({'art': 'text', 'text': ''}), isNull);
      expect(Wasserzeichen.ausJson({'art': 'bild'}), isNull);
      expect(Wasserzeichen.ausJson({'art': 'video', 'text': 'x'}), isNull);
      expect(
        Wasserzeichen.ausJson({'art': 'bild', 'bild': '%%%kein base64'}),
        isNull,
      );
      // Ein Text mit gezeichnetem Bild (so kommt es vom Link) gilt.
      expect(
        Wasserzeichen.ausJson({
          'art': 'text',
          'text': 'x',
          'bild': base64Encode(png(rot(2, 1))),
        })?.bild,
        isNotNull,
      );
    });
  });

  group('das PNG des Zeichens', () {
    test('Masse aus dem Kopf; nur PNG', () {
      expect(Wasserzeichenbild.masse(png(rot(7, 3))), (breite: 7, hoehe: 3));
      final jpg = Uint8List.fromList(img.encodeJpg(grau(7, 3)));
      expect(Wasserzeichenbild.masse(jpg), isNull);
      expect(Wasserzeichenbild.gueltig(jpg), isFalse);
      expect(Wasserzeichenbild.bereiteVor(jpg), isNull);
      expect(Wasserzeichenbild.gueltig(png(rot(7, 3))), isTrue);
    });

    test('ein PNG, das riesig zu sein behauptet, wird nicht dekodiert', () {
      // Der Kopf sagt 60000 × 60000 – dekodiert wären das 14 Gigabyte.
      final echt = png(rot(2, 2));
      final bombe = Uint8List.fromList(echt);
      void setze(int ab, int wert) {
        bombe[ab] = (wert >> 24) & 0xFF;
        bombe[ab + 1] = (wert >> 16) & 0xFF;
        bombe[ab + 2] = (wert >> 8) & 0xFF;
        bombe[ab + 3] = wert & 0xFF;
      }

      setze(16, 60000);
      setze(20, 60000);
      expect(Wasserzeichenbild.gueltig(bombe), isFalse);
      expect(Wasserzeichenbild.bereiteVor(bombe), isNull);
    });

    test('ein grosses Logo wird verkleinert, ein kleines bleibt', () {
      final klein = png(rot(300, 100));
      expect(Wasserzeichenbild.bereiteVor(klein), klein);
      final gross = img.Image(width: 3200, height: 800, numChannels: 4);
      for (final p in gross) {
        // Links deckend weiss, rechts durchsichtig (schwarz gespeichert).
        // Die Grenze liegt mitten in einem Pixel des verkleinerten Bildes.
        final weiss = p.x <= 1600;
        p
          ..r = weiss ? 255 : 0
          ..g = weiss ? 255 : 0
          ..b = weiss ? 255 : 0
          ..a = weiss ? 255 : 0;
      }
      final fertig = Wasserzeichenbild.bereiteVor(png(gross))!;
      final m = Wasserzeichenbild.masse(fertig)!;
      expect(m, (breite: Wasserzeichenbild.hoechstensKante, hoehe: 400));
      final bild = img.decodePng(fertig)!;
      // An der Kante halb deckend, aber weiss – kein grauer Saum.
      final kante = bild.getPixel(800, 200);
      expect(kante.a, inInclusiveRange(100, 160));
      expect(kante.r, greaterThanOrEqualTo(250));
      expect(bild.getPixel(100, 100).a, 255);
      expect(bild.getPixel(1500, 100).a, 0);
    });
  });
}
