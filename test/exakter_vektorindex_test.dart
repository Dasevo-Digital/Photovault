import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/services/clip_service.dart';
import 'package:kern/services/exakter_vektorindex.dart';
import 'package:kern/services/bildsuche.dart';

void main() {
  for (final cluster in [false, true]) {
    test('exakte Treffer, Filter und Gleichstände: cluster=$cluster', () {
      final random = Random(42), n = 6000, d = 64;
      final map = <String, Float32List>{
        for (var i = 0; i < n; i++)
          '$i': Float32List.fromList([
            for (var j = 0; j < d; j++)
              (cluster ? (j == i % 16 ? 4.0 : 0.0) : 0.0) +
                  random.nextDouble() * 0.1,
          ]),
      };
      map['duplikat'] = map['0']!;
      final watch = Stopwatch()..start();
      final index = ExakterVektorindex(map);
      final bau = watch.elapsedMilliseconds;
      var volle = 0, indexzeit = 0, geprueft = 0;
      for (var i = 0; i < 12; i++) {
        final q = map['${i * 200}']!;
        final erlaubt = {
          for (var k = 0; k < n; k++)
            if (k % 3 != 0) '$k',
          'duplikat',
        };
        final teil = {
          for (final e in map.entries)
            if (erlaubt.contains(e.key)) e.key: e.value,
        };
        watch.reset();
        final exakt = ClipService.rankBySimilarity(q, teil, topK: 30);
        volle += watch.elapsedMicroseconds;
        watch.reset();
        final fund = index.suche(q, erlaubt: erlaubt.contains, topK: 30);
        indexzeit += watch.elapsedMicroseconds;
        geprueft += index.letzteGepruefteVektoren;
        expect(fund.map((e) => e.key), exakt.map((e) => e.key));
        expect(fund.map((e) => e.value), exakt.map((e) => e.value));
      }
      // Messwerte sind keine Laufzeitschranke: langsame Prüfrechner ändern Recall nicht.
      // ignore: avoid_print
      print(
        'INDEX cluster=$cluster buildMs=$bau exactUs=$volle indexUs=$indexzeit evaluated=$geprueft full=${n * 12} recall=1',
      );
    });
  }
  test(
    'kleine/gemischte Vektoren fallen exakt zurück; anderer Vorrat verwirft Index',
    () {
      final map = {
        'a': Float32List.fromList([1, 0]),
        'b': Float32List.fromList([0, 1, 2]),
      };
      final index = ExakterVektorindex(map);
      expect(
        index
            .suche(Float32List.fromList([1, 0]), erlaubt: (_) => true)
            .first
            .key,
        'a',
      );
      expect(index.letzterRueckfall, isTrue);
      final neu = {
        'c': Float32List.fromList([1, 0]),
      };
      expect(
        rangfolgeDerBildsuche(Float32List.fromList([1, 0]), neu, {
          'c',
        }, index: index),
        ['c'],
      );
    },
  );
  test(
    'Videos werden nach Filterung zusammengeführt und leere Auswahl bleibt leer',
    () {
      final map = {
        for (var i = 0; i < 2200; i++) 'x$i': Float32List.fromList([1, 0]),
        'video#0': Float32List.fromList([2, 0]),
        'video#1': Float32List.fromList([3, 0]),
      };
      final index = ExakterVektorindex(map), q = Float32List.fromList([1, 0]);
      expect(rangfolgeDerBildsuche(q, map, {'video', 'x1'}, index: index), [
        'video',
        'x1',
      ]);
      expect(rangfolgeDerBildsuche(q, map, {}, index: index), isEmpty);
    },
  );
  test(
    'ungültige Modellwerte bleiben im Rückfall, andere Modelle werden nicht angehängt',
    () {
      final map = {
        'a': Float32List.fromList([double.nan, 0]),
      };
      final i = ExakterVektorindex(map);
      i.bindeQuelle({
        'a': Float32List.fromList([double.nan, 0]),
      });
      expect(
        () => i.bindeQuelle({
          'a': Float32List.fromList([1, 0]),
        }),
        throwsArgumentError,
      );
      i.suche(Float32List.fromList([1, 0]), erlaubt: (_) => true);
      expect(i.letzterRueckfall, isTrue);
    },
  );
}
