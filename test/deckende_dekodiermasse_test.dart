/// **Kacheln zeigen ihre Fotos unverzerrt.**
///
/// `cacheWidth` und `cacheHeight` zusammen heissen für Flutter: dekodiere
/// auf genau diese Masse – das Seitenverhältnis bleibt dabei nicht
/// erhalten. Genau so stand es in drei Kacheln der App, und aus jedem
/// Kreis wurde eine Ellipse. Siehe [deckendeDekodiermasse].
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/bilddekodierung.dart';

void main() {
  group('Nur eine Kante', () {
    test('quadratische Kachel, Querformat: die Höhe bindet', () {
      // 400x300 in ein Quadrat: Die Höhe ist die knappe Kante, denn nach
      // dem Zuschnitt muss sie die Kachel noch füllen.
      final m = deckendeDekodiermasse(
          kachelBreite: 160,
          kachelHoehe: 160,
          bildBreite: 400,
          bildHoehe: 300,
          pixelverhaeltnis: 2);
      expect(m.breite, isNull);
      expect(m.hoehe, 320);
    });

    test('quadratische Kachel, Hochformat: die Breite bindet', () {
      final m = deckendeDekodiermasse(
          kachelBreite: 160,
          kachelHoehe: 160,
          bildBreite: 225,
          bildHoehe: 400,
          pixelverhaeltnis: 2);
      expect(m.breite, 320);
      expect(m.hoehe, isNull);
    });

    test('nie beide zugleich – das ist der ganze Punkt', () {
      for (final (b, h) in [(400, 300), (225, 400), (400, 400), (1, 4000)]) {
        for (final (kb, kh) in [(160.0, 160.0), (300.0, 100.0), (90.0, 240.0)]) {
          final m = deckendeDekodiermasse(
              kachelBreite: kb,
              kachelHoehe: kh,
              bildBreite: b,
              bildHoehe: h,
              pixelverhaeltnis: 2);
          expect(m.breite == null || m.hoehe == null, isTrue,
              reason: 'Bild ${b}x$h in Kachel ${kb}x$kh');
        }
      }
    });

    test('die gewählte Kante deckt die Kachel wirklich ab', () {
      // Die Gegenprobe zur Rechnung: Die NICHT begrenzte Kante muss sich
      // aus dem Verhältnis mindestens so gross ergeben, wie die Kachel
      // sie braucht - sonst wäre das Bild an einer Seite zu klein und
      // müsste hochskaliert werden.
      for (final (b, h) in [(400, 300), (225, 400), (4000, 3000), (300, 300)]) {
        for (final (kb, kh) in [(160.0, 160.0), (220.0, 90.0), (90.0, 220.0)]) {
          const dpr = 2.0;
          final m = deckendeDekodiermasse(
              kachelBreite: kb,
              kachelHoehe: kh,
              bildBreite: b,
              bildHoehe: h,
              pixelverhaeltnis: dpr);
          final breite = m.breite ?? (m.hoehe! * b / h);
          final hoehe = m.hoehe ?? (m.breite! * h / b);
          expect(breite, greaterThanOrEqualTo(kb * dpr - 0.001),
              reason: '${b}x$h in ${kb}x$kh: zu schmal');
          expect(hoehe, greaterThanOrEqualTo(kh * dpr - 0.001),
              reason: '${b}x$h in ${kb}x$kh: zu niedrig');
        }
      }
    });

    test('ohne Masse wird gar nichts begrenzt', () {
      for (final (b, h) in [(null, null), (400, null), (null, 300), (0, 0)]) {
        final m = deckendeDekodiermasse(
            kachelBreite: 160,
            kachelHoehe: 160,
            bildBreite: b,
            bildHoehe: h,
            pixelverhaeltnis: 2);
        expect(m.breite, isNull);
        expect(m.hoehe, isNull);
      }
    });

    test('eine unendliche Kachelkante zählt nicht mit', () {
      final m = deckendeDekodiermasse(
          kachelBreite: 160,
          kachelHoehe: double.infinity,
          bildBreite: 400,
          bildHoehe: 300,
          pixelverhaeltnis: 1);
      expect(m.breite, 160);
      expect(m.hoehe, isNull);
    });

    test('gerundet wird über die Stufen', () {
      final m = deckendeDekodiermasse(
          kachelBreite: 100,
          kachelHoehe: 100,
          bildBreite: 400,
          bildHoehe: 300,
          pixelverhaeltnis: 1);
      expect(m.hoehe! % dekodierstufe, 0);
    });
  });

  test('keine Kachel setzt mehr beide Kanten', () {
    // Gegenprobe am Quelltext: Die drei Stellen, die es taten, waren
    // Zeitleiste, Kartenmarker und Filmstreifen - und keine davon fiel
    // je auf, weil `BoxFit.cover` das gestauchte Bild brav einpasst.
    final treffer = <String>[];
    for (final datei in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final quelle = datei.readAsStringSync();
      // Beide Angaben unmittelbar nacheinander - so sieht der Fehler aus.
      final regel = RegExp(r'cacheWidth:[^;]{0,200}?cacheHeight:', dotAll: true);
      for (final m in regel.allMatches(quelle)) {
        // Über [deckendeDekodiermasse] ist es richtig: Dort ist genau
        // eine der beiden Angaben belegt.
        if (m.group(0)!.contains('masse.')) continue;
        treffer.add(datei.path);
      }
    }
    expect(treffer, isEmpty,
        reason: 'setzt cacheWidth und cacheHeight zugleich und staucht damit');
  });
}
