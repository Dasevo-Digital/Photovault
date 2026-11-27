import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kern/services/zusammenfuegen/fehler.dart';
import 'package:kern/services/zusammenfuegen/panorama.dart';
import 'package:kern/services/zusammenfuegen/raster.dart';

import 'hilfen/synthetische_bilder.dart';

/// Panoramen aus einem Schwenk (#498), an künstlichen Aufnahmen einer
/// Lochkamera, die sich um bekannte Winkel dreht.
void main() {
  const breite = 320, hoehe = 240;
  const f = 280.0;
  // Vier Aufnahmen, je 28° gedreht (gut die Hälfte überlappt), leicht
  // verschieden geneigt – und absichtlich durcheinander.
  const gier = [56.0, 0.0, 84.0, 28.0];
  const nick = [1.0, 0.0, 2.0, 0.5];
  final schwenk = [
    for (var i = 0; i < 4; i++)
      schwenkaufnahme(breite, hoehe, f, gier[i], nickGrad: nick[i]),
  ];
  final f35 = f / math.sqrt(breite * breite + hoehe * hoehe) * 43.27;
  // Ohne Zuschnitt: der Schwenk von 84° plus der Bildwinkel einer Aufnahme.
  final sollBreite = f * (84 * math.pi / 180 + 2 * math.atan(breite / 2 / f));

  test('setzt einen Schwenk in beliebiger Reihenfolge zusammen: Breite und '
      'Lage der Aufnahmen stimmen', () {
    final e = fuegePanorama(
      4,
      (i) => schwenk[i],
      brennweiten35: List.filled(4, f35),
      optionen: const PanoramaOptionen(zuschneiden: false),
    );
    expect(e.verwendet, [0, 1, 2, 3]);
    expect(e.brennweite, closeTo(f / breite, 0.005));
    expect(e.bild.breite, closeTo(sollBreite, sollBreite * 0.02));
    // Die Bildmitten liegen 28° auseinander, in der Reihenfolge der
    // Drehung – in Punkten des Ergebnisses höchstens zwei daneben.
    final mitten = [
      for (final i in [1, 3, 0, 2]) e.mitten[i]!,
    ];
    for (var k = 1; k < 4; k++) {
      final abstand = (mitten[k] - mitten[k - 1]) * f;
      expect(abstand, closeTo(28 * math.pi / 180 * f, 2), reason: '$k');
    }
  });

  test('schätzt die Brennweite ohne Aufnahmeangaben', () {
    final e = fuegePanorama(
      4,
      (i) => schwenk[i],
      optionen: const PanoramaOptionen(zuschneiden: false),
    );
    expect(e.brennweite, closeTo(f / breite, f / breite * 0.03));
    expect(e.bild.breite, closeTo(sollBreite, sollBreite * 0.04));
  });

  test('zugeschnitten ist jeder Rand gedeckt, ohne Zuschnitt bleiben '
      'schwarze Ecken', () {
    bool schwarz(Farbbild b, int x, int y) {
      final o = (y * b.breite + x) * 3;
      return b.rgb[o] + b.rgb[o + 1] + b.rgb[o + 2] == 0;
    }

    int schwarzeRandpunkte(Farbbild b) {
      var n = 0;
      for (var x = 0; x < b.breite; x++) {
        if (schwarz(b, x, 0)) n++;
        if (schwarz(b, x, b.hoehe - 1)) n++;
      }
      for (var y = 0; y < b.hoehe; y++) {
        if (schwarz(b, 0, y)) n++;
        if (schwarz(b, b.breite - 1, y)) n++;
      }
      return n;
    }

    final zu = fuegePanorama(
      4,
      (i) => schwenk[i],
      brennweiten35: List.filled(4, f35),
    );
    final offen = fuegePanorama(
      4,
      (i) => schwenk[i],
      brennweiten35: List.filled(4, f35),
      optionen: const PanoramaOptionen(zuschneiden: false),
    );
    expect(schwarzeRandpunkte(zu.bild), 0);
    expect(schwarzeRandpunkte(offen.bild), greaterThan(50));
    expect(zu.bild.breite, lessThan(offen.bild.breite));
    expect(zu.bild.hoehe, lessThan(offen.bild.hoehe));
    expect(zu.bild.breite, greaterThan(offen.bild.breite * 0.9));
  });

  test('gleicht eine dunklere Aufnahme an ihre Nachbarn an – Gegenprobe '
      'ohne Ausgleich', () {
    List<double> baender(Farbbild b) {
      final g = Graubild.aus(b);
      return [
        for (var k = 0; k < 8; k++)
          () {
            var s = 0.0;
            var n = 0;
            for (var y = 0; y < b.hoehe; y++) {
              for (
                var x = k * b.breite ~/ 8;
                x < (k + 1) * b.breite ~/ 8;
                x++
              ) {
                s += g.werte[y * b.breite + x];
                n++;
              }
            }
            return s / n;
          }(),
      ];
    }

    // Die Aufnahme ganz rechts (84°) ist 30 % dunkler belichtet.
    final dunkler = [
      for (var i = 0; i < 4; i++)
        schwenkaufnahme(
          breite,
          hoehe,
          f,
          gier[i],
          nickGrad: nick[i],
          helligkeit: i == 2 ? 0.7 : 1,
        ),
    ];
    Farbbild pano(List<Farbbild> q, {bool ausgleichen = true}) => fuegePanorama(
      4,
      (i) => q[i],
      brennweiten35: List.filled(4, f35),
      optionen: PanoramaOptionen(belichtungAusgleichen: ausgleichen),
    ).bild;
    final gleich = baender(pano(schwenk));
    double streuung(List<double> b) {
      // Das Verhältnis je Band zum gleich belichteten Panorama: Ist die
      // dunklere Aufnahme ausgeglichen, ist es überall dasselbe.
      final v = [for (var k = 0; k < 8; k++) b[k] / gleich[k]];
      final m = v.reduce((a, b) => a + b) / v.length;
      return v.map((x) => (x - m).abs()).reduce(math.max) / m;
    }

    expect(streuung(baender(pano(dunkler))), lessThan(0.03));
    expect(
      streuung(baender(pano(dunkler, ausgleichen: false))),
      greaterThan(0.08),
    );
  });

  test('Fotos ohne Überlappung: verständlicher Fehler; ein fremdes Foto '
      'bleibt draussen', () {
    final fremd = schwenkaufnahme(breite, hoehe, f, 0, saat: 5);
    expect(
      () => fuegePanorama(2, (i) => [schwenk[1], fremd][i]),
      throwsA(
        isA<Zusammenfuegefehler>().having(
          (e) => e.grund,
          'grund',
          Fuegegrund.keineUeberlappung,
        ),
      ),
    );
    final teil = fuegePanorama(
      4,
      (i) => [schwenk[0], schwenk[1], fremd, schwenk[3]][i],
      brennweiten35: List.filled(4, f35),
    );
    expect(teil.verwendet, [0, 1, 3]);
  });

  test('hält die Grenze der Ausgabegrösse ein', () {
    final e = fuegePanorama(
      4,
      (i) => schwenk[i],
      brennweiten35: List.filled(4, f35),
      optionen: const PanoramaOptionen(
        zuschneiden: false,
        hoechstensPixel: 40000,
      ),
    );
    expect(e.bild.pixel, lessThanOrEqualTo(40000));
    expect(e.bild.breite / e.bild.hoehe, greaterThan(2.3));
    expect(
      () => fuegePanorama(1, (i) => schwenk[i]),
      throwsA(isA<Zusammenfuegefehler>()),
    );
  });
}
