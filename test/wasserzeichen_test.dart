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
        zeichen: Wasserzeichenbild.pixel(png(rot(40, 20)))!,
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
        zeichen: Zeichenpixel.aus(rot(40, 20)),
        wasserzeichen: const Wasserzeichen(text: 'x', rand: 0, deckkraft: 1),
        qualitaet: 95,
      ));
      final gelesen = img.decodeJpg(raus)!;
      expect((gelesen.width, gelesen.height), (200, 100));
      expect(gelesen.exif.imageIfd.orientation ?? 1, 1);
      expect(gelesen.getPixel(190, 95).r, greaterThan(200));
      expect(gelesen.getPixel(10, 5).r, inInclusiveRange(95, 105));
    });

    test('ein unlesbares Zeichen gibt keine Pixel, ein unlesbares Foto ist '
        'ein Fehler', () {
      expect(Wasserzeichenbild.pixel(Uint8List.fromList([1, 2, 3])), isNull);
      expect(
        () => jpegMitWasserzeichen((
          jpeg: Uint8List.fromList([0xFF, 0xD8, 1, 2, 3]),
          zeichen: Zeichenpixel.aus(rot(4, 2)),
          wasserzeichen: const Wasserzeichen(text: 'x'),
          qualitaet: 90,
        )),
        throwsFormatException,
      );
    });

    test('ein Zeichen breiter als 4096 Pixel (Text auf einem Panorama)', () {
      // Die Grenze für Fremdes gilt nicht für Pixel, die das Gerät selbst
      // gezeichnet hat: 50 % von 9000 px sind 4500.
      final raus = jpegMitWasserzeichen((
        jpeg: jpeg(grau(9000, 60)),
        zeichen: Zeichenpixel.aus(rot(4500, 20)),
        wasserzeichen: const Wasserzeichen(
          text: 'x',
          groesse: 0.5,
          rand: 0,
          deckkraft: 1,
        ),
        qualitaet: 90,
      ));
      final bild = img.decodeJpg(raus)!;
      expect(bild.getPixel(8000, 55).r, greaterThan(200));
      expect(bild.getPixel(8000, 55).g, lessThan(60));
      expect(bild.getPixel(1000, 55).r, inInclusiveRange(95, 105));
    });
  });

  group('Graustufen (#497)', () {
    test('ein graues Logo bleibt grau, statt rot zu werden', () {
      // Ein Kanal: Das Bildpaket liefert dort Grün und Blau als 0.
      final logo = img.Image(width: 20, height: 10, numChannels: 1)
        ..clear(img.ColorUint8.rgb(200, 200, 200));
      expect(logo.getPixel(0, 0).g, 0, reason: 'so liest das Bildpaket');
      final bild = rechneWasserzeichenEin(
        grau(100, 50, 0),
        img.decodePng(png(logo))!,
        const Wasserzeichen(text: 'x', rand: 0, deckkraft: 1),
      );
      final p = bild.getPixel(90, 45);
      expect((p.r, p.g, p.b), (200, 200, 200));
    });

    test('in ein Graustufenfoto kommt ein farbiges Logo farbig', () {
      final bild = img.Image(width: 100, height: 50, numChannels: 1)
        ..clear(img.ColorUint8.rgb(100, 100, 100));
      final raus = rechneWasserzeichenEin(
        bild,
        rot(20, 10),
        const Wasserzeichen(text: 'x', rand: 0, deckkraft: 1),
      );
      expect(raus.numChannels, 3);
      final p = raus.getPixel(90, 45);
      expect((p.r, p.g, p.b), (255, 0, 0));
      final q = raus.getPixel(10, 10);
      expect((q.r, q.g, q.b), (100, 100, 100));
    });
  });

  group('vorbereitete Pixel', () {
    test('aus gewöhnlichen Farben vormultipliziert', () {
      final z = Zeichenpixel.ausGerade(
        1,
        2,
        Uint8List.fromList([255, 255, 255, 128, 200, 100, 0, 0]),
      );
      expect(z.rgba, [128, 128, 128, 128, 0, 0, 0, 0]);
    });

    test('umgerechnet ohne die Deckung', () {
      final z = Zeichenpixel.ausGerade(
        2,
        1,
        Uint8List.fromList([200, 100, 50, 128, 10, 20, 30, 255]),
      );
      final gesehen = <int>[];
      final neu = z.umgerechnet((rgb) {
        gesehen.addAll(rgb);
        return Uint8List.fromList([for (final v in rgb) 255 - v]);
      });
      // Die Werte ohne Deckung, auf ±1 genau zurückgerechnet.
      for (final (i, soll) in [200, 100, 50, 10, 20, 30].indexed) {
        expect((gesehen[i] - soll).abs(), lessThanOrEqualTo(1));
      }
      expect(neu.rgba[3], 128);
      expect((neu.rgba[0] - (55 * 128 / 255).round()).abs(), lessThan(2));
      expect(neu.rgba.sublist(4), [245, 235, 225, 255]);
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

    test('ein zweiter Kopf kommt nicht an der Prüfung vorbei', () {
      // Der erste Kopf sagt 2 × 2, ein zweiter 16000 × 16000 – das
      // Bildpaket nimmt den zweiten und belegte beim Dekodieren ein
      // Gigabyte.
      final teile = _abschnitte(png(rot(2, 2)));
      final bombe = _png([
        teile.first,
        _abschnitt('IHDR', [..._u32(16000), ..._u32(16000), 8, 6, 0, 0, 0]),
        ...teile.skip(1),
      ]);
      expect(img.PngDecoder().startDecode(bombe)?.width, 16000);
      expect(Wasserzeichenbild.masse(bombe), isNull);
      expect(Wasserzeichenbild.gueltig(bombe), isFalse);
      expect(Wasserzeichenbild.lies(bombe), isNull);
      expect(Wasserzeichenbild.bereiteVor(bombe), isNull);
      expect(
        Wasserzeichenbild.normalisiert(
          bombe,
          hoechstensBreite: 100,
          hoechstensHoehe: 100,
        ),
        isNull,
      );
    });

    test('eine Animation (APNG) wird nicht gelesen', () {
      final animation = rot(4, 4)
        ..addFrame(
          img.Image(width: 4, height: 4, numChannels: 4)
            ..clear(img.ColorRgba8(0, 0, 255, 255)),
        );
      final apng = png(animation);
      expect(String.fromCharCodes(apng), contains('acTL'));
      expect(Wasserzeichenbild.masse(apng), isNull);
      expect(Wasserzeichenbild.gueltig(apng), isFalse);
      expect(Wasserzeichenbild.bereiteVor(apng), isNull);
    });

    test('der Dekoder sieht nur geprüfte Abschnitte', () {
      // bKGD liest das Bildpaket nicht in seiner Länge: Ist der Abschnitt
      // länger, liest es danach mitten in ihm weiter – dort liesse sich ein
      // Kopf verstecken, den die Prüfung nie sähe.
      final teile = _abschnitte(png(rot(2, 2)));
      final versteckt = _png([
        teile.first,
        _abschnitt('bKGD', List.filled(40, 0)),
        ...teile.skip(1),
      ]);
      expect(img.decodePng(versteckt), isNull, reason: 'aus dem Tritt');
      final gelesen = Wasserzeichenbild.lies(versteckt)!;
      expect((gelesen.width, gelesen.height), (2, 2));
      expect(gelesen.getPixel(1, 1).r, 255);
    });

    test('wie der Server ein Zeichen speichert', () {
      // Graustufen mit 16 Bit, 3000 × 60, mit einem Textabschnitt.
      final grau16 = img.Image(
        width: 3000,
        height: 60,
        numChannels: 2,
        format: img.Format.uint16,
      );
      for (final p in grau16) {
        p
          ..r = 40000
          ..a = 65535;
      }
      final teile = _abschnitte(png(grau16));
      final eingang = _png([
        teile.first,
        _abschnitt('tEXt', 'Kommentar\u0000geheim'.codeUnits),
        ...teile.skip(1),
      ]);
      final gespeichert = Wasserzeichenbild.normalisiert(
        eingang,
        hoechstensBreite: 640,
        hoechstensHoehe: 2560,
      )!;
      expect(Wasserzeichenbild.masse(gespeichert), (breite: 640, hoehe: 13));
      expect(
        [for (final (n, _) in _benannt(gespeichert)) n],
        ['IHDR', 'IDAT', 'IEND'],
      );
      final bild = img.decodePng(gespeichert)!;
      expect((bild.numChannels, bild.format), (4, img.Format.uint8));
      final p = bild.getPixel(300, 6);
      expect((p.r, p.g, p.b, p.a), (156, 156, 156, 255));
      // Ein kleines bleibt so gross, wird aber neu geschrieben.
      final klein = Wasserzeichenbild.normalisiert(
        eingang,
        hoechstensBreite: 4000,
        hoechstensHoehe: 2560,
      )!;
      expect(Wasserzeichenbild.masse(klein), (breite: 3000, hoehe: 60));
      expect(String.fromCharCodes(klein), isNot(contains('geheim')));
      // Und nur, was sich lesen lässt.
      expect(
        Wasserzeichenbild.normalisiert(
          Uint8List.fromList([1, 2, 3]),
          hoechstensBreite: 10,
          hoechstensHoehe: 10,
        ),
        isNull,
      );
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

List<int> _u32(int v) => [
  (v >> 24) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 8) & 0xFF,
  v & 0xFF,
];

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c ^= b;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB88320 : c >> 1;
    }
  }
  return c ^ 0xFFFFFFFF;
}

/// Ein PNG-Abschnitt samt Länge und Prüfsumme.
Uint8List _abschnitt(String name, List<int> daten) => Uint8List.fromList([
  ..._u32(daten.length),
  ...name.codeUnits,
  ...daten,
  ..._u32(_crc32([...name.codeUnits, ...daten])),
]);

/// Die Abschnitte eines PNG, wie sie in der Datei stehen, mit Namen.
List<(String, Uint8List)> _benannt(Uint8List png) {
  final aus = <(String, Uint8List)>[];
  var pos = 8;
  while (pos < png.length) {
    final laenge = ByteData.sublistView(png, pos, pos + 4).getUint32(0);
    final name = String.fromCharCodes(png, pos + 4, pos + 8);
    aus.add((name, Uint8List.sublistView(png, pos, pos + 12 + laenge)));
    pos += 12 + laenge;
  }
  return aus;
}

List<Uint8List> _abschnitte(Uint8List png) => [
  for (final (_, a) in _benannt(png)) a,
];

Uint8List _png(List<Uint8List> abschnitte) => Uint8List.fromList([
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  for (final a in abschnitte) ...a,
]);
