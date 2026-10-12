import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/whisper_mel.dart';

/// Das Mel-Spektrogramm, mit dem Whisper hört – gegen Werte aus dem
/// Original (numpy, `mel_filters.npz` des Whisper-Repositorys), siehe
/// test/fixtures/README.md.
void main() {
  final referenz =
      jsonDecode(File('test/fixtures/whisper/referenz.json').readAsStringSync())
          as Map<String, dynamic>;

  test('die FFT der Länge 400 rechnet wie die direkte Formel', () {
    final zufall = math.Random(7);
    final re = Float64List.fromList(
      List.generate(400, (_) => zufall.nextDouble() - 0.5),
    );
    final im = Float64List.fromList(
      List.generate(400, (_) => zufall.nextDouble() - 0.5),
    );
    final ausRe = Float64List(400);
    final ausIm = Float64List(400);
    WhisperFft(400).transformiere(re, im, ausRe, ausIm);
    var fehler = 0.0;
    for (var k = 0; k < 400; k++) {
      var sr = 0.0, si = 0.0;
      for (var t = 0; t < 400; t++) {
        final w = -2 * math.pi * k * t / 400;
        sr += re[t] * math.cos(w) - im[t] * math.sin(w);
        si += re[t] * math.sin(w) + im[t] * math.cos(w);
      }
      fehler = math.max(fehler, (sr - ausRe[k]).abs() + (si - ausIm[k]).abs());
    }
    expect(fehler, lessThan(1e-9));
  });

  test('die Filterbank ist die des Originals', () {
    final filter = whisperMelFilter();
    final zeilen = referenz['filter'] as List;
    expect(filter, hasLength(80));
    for (final (m, z) in zeilen.indexed) {
      final von = z['von'] as int;
      final werte = (z['werte'] as List).cast<num>();
      for (var k = 0; k < 201; k++) {
        final soll = k >= von && k < von + werte.length
            ? werte[k - von].toDouble()
            : 0.0;
        expect(filter[m][k], closeTo(soll, 1e-6), reason: 'Band $m, Bin $k');
      }
    }
  });

  test('das Log-Mel-Spektrogramm trifft das Original', () {
    // Ein Ton, der von 200 auf 3000 Hz gleitet, dazu 440 Hz, zwei
    // Sekunden, der Rest des Stücks Stille – wie die Referenz.
    final audio = Float32List(whisperStueck);
    for (var i = 0; i < 2 * whisperAbtastrate; i++) {
      final t = i / whisperAbtastrate;
      audio[i] =
          0.3 * math.sin(2 * math.pi * (200 * t + 700 * t * t)) +
          0.1 * math.sin(2 * math.pi * 440 * t);
    }
    final mel = whisperLogMel(audio);
    expect(mel, hasLength(80 * 3000));
    final proben = referenz['logmel'] as Map<String, dynamic>;
    final rahmen = (proben['rahmen'] as List).cast<int>();
    final werte = proben['werte'] as List;
    var fehler = 0.0;
    for (final (i, f) in rahmen.indexed) {
      final soll = (werte[i] as List).cast<num>();
      for (var m = 0; m < 80; m++) {
        fehler = math.max(fehler, (mel[m * 3000 + f] - soll[m]).abs());
      }
    }
    expect(fehler, lessThan(1e-4));
    final summe = mel.fold<double>(0, (a, b) => a + b);
    expect(summe, closeTo((referenz['summe'] as num).toDouble(), 1.0));
  });
}
