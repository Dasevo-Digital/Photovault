/// Was Whisper hört: das Log-Mel-Spektrogramm eines 30-Sekunden-Stücks.
///
/// Nachgerechnet wie `whisper.audio.log_mel_spectrogram` im Original –
/// Hann-Fenster über 400 Abtastwerte, alle 160 ein Rahmen, gespiegelter
/// Rand, 80 Mel-Bänder nach Slaney, Logarithmus, dann auf 8 Dekaden unter
/// dem Höchstwert begrenzt. Jede Abweichung davon hört das Modell als
/// anderen Klang. Abgeglichen mit `test/fixtures/whisper/referenz.json`,
/// erzeugt aus dem Original (numpy, `mel_filters.npz` aus dem
/// Whisper-Repository).
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Abtastrate, die Whisper erwartet.
const whisperAbtastrate = 16000;

/// Fensterlänge und Schritt der Kurzzeit-Fourier-Transformation.
const whisperFenster = 400;
const whisperSchritt = 160;

/// Zahl der Mel-Bänder (whisper-small; erst large-v3 hat 128).
const whisperMelBaender = 80;

/// Ein Stück: 30 Sekunden, 3000 Rahmen.
const whisperStueck = 30 * whisperAbtastrate;
const whisperRahmen = 3000;

const _bins = whisperFenster ~/ 2 + 1;

/// Die Mel-Filterbank wie `librosa.filters.mel(sr=16000, n_fft=400,
/// n_mels=80)`: Slaney-Skala (linear bis 1 kHz, darüber logarithmisch)
/// und Slaney-Norm (jedes Dreieck auf gleiche Fläche).
///
/// Gerechnet statt als Tabelle mitgeliefert: Die Formel ist kurz, die
/// Tabelle hätte 16.080 Zahlen. Abgeglichen mit der Tabelle des
/// Originals.
List<Float64List> whisperMelFilter() {
  const fSp = 200.0 / 3;
  const minLogHz = 1000.0;
  const minLogMel = minLogHz / fSp;
  final logstep = math.log(6.4) / 27.0;

  double hzZuMel(double f) =>
      f >= minLogHz ? minLogMel + math.log(f / minLogHz) / logstep : f / fSp;
  double melZuHz(double m) =>
      m >= minLogMel ? minLogHz * math.exp(logstep * (m - minLogMel)) : fSp * m;

  final fftFrequenzen = [
    for (var i = 0; i < _bins; i++) i * (whisperAbtastrate / 2) / (_bins - 1),
  ];
  final melMin = hzZuMel(0);
  final melMax = hzZuMel(whisperAbtastrate / 2);
  final melF = [
    for (var i = 0; i < whisperMelBaender + 2; i++)
      melZuHz(melMin + (melMax - melMin) * i / (whisperMelBaender + 1)),
  ];
  return [
    for (var m = 0; m < whisperMelBaender; m++)
      () {
        final zeile = Float64List(_bins);
        final unten = melF[m + 1] - melF[m];
        final oben = melF[m + 2] - melF[m + 1];
        final norm = 2.0 / (melF[m + 2] - melF[m]);
        for (var k = 0; k < _bins; k++) {
          final steigend = (fftFrequenzen[k] - melF[m]) / unten;
          final fallend = (melF[m + 2] - fftFrequenzen[k]) / oben;
          zeile[k] = math.max(0, math.min(steigend, fallend)) * norm;
        }
        return zeile;
      }(),
  ];
}

/// Eine Fourier-Transformation der Länge 400 = 2⁴ · 5², mit gemischter
/// Basis (Cooley-Tukey). Eine direkte Rechnung bräuchte je Stück
/// 3000 · 201 · 400 Multiplikationen; so sind es rund zwanzigmal weniger.
class WhisperFft {
  WhisperFft(this.n) : _cos = Float64List(n), _sin = Float64List(n) {
    for (var i = 0; i < n; i++) {
      _cos[i] = math.cos(-2 * math.pi * i / n);
      _sin[i] = math.sin(-2 * math.pi * i / n);
    }
  }

  final int n;
  final Float64List _cos;
  final Float64List _sin;

  /// Transformiert [re] und [im] (Länge [n]) nach [ausRe] und [ausIm].
  void transformiere(
    Float64List re,
    Float64List im,
    Float64List ausRe,
    Float64List ausIm,
  ) => _fft(re, im, 0, 1, n, ausRe, ausIm, 0);

  static int _kleinsterTeiler(int n) {
    for (final p in const [4, 2, 3, 5]) {
      if (n % p == 0) return p;
    }
    for (var p = 7; p * p <= n; p += 2) {
      if (n % p == 0) return p;
    }
    return n;
  }

  void _fft(
    Float64List re,
    Float64List im,
    int anfang,
    int abstand,
    int laenge,
    Float64List ausRe,
    Float64List ausIm,
    int ausAnfang,
  ) {
    if (laenge == 1) {
      ausRe[ausAnfang] = re[anfang];
      ausIm[ausAnfang] = im[anfang];
      return;
    }
    final p = _kleinsterTeiler(laenge);
    final m = laenge ~/ p;
    for (var r = 0; r < p; r++) {
      _fft(
        re,
        im,
        anfang + r * abstand,
        abstand * p,
        m,
        ausRe,
        ausIm,
        ausAnfang + r * m,
      );
    }
    // Die p Teilergebnisse an Stelle k zu den p Ergebnissen k + q·m
    // zusammensetzen – an denselben Plätzen, deshalb über einen kleinen
    // Zwischenspeicher.
    final schritt = n ~/ laenge;
    final tRe = Float64List(p);
    final tIm = Float64List(p);
    for (var k = 0; k < m; k++) {
      for (var r = 0; r < p; r++) {
        final i = ausAnfang + r * m + k;
        final w = (r * k * schritt) % n;
        final c = _cos[w], s = _sin[w];
        tRe[r] = ausRe[i] * c - ausIm[i] * s;
        tIm[r] = ausRe[i] * s + ausIm[i] * c;
      }
      for (var q = 0; q < p; q++) {
        var sr = 0.0, si = 0.0;
        for (var r = 0; r < p; r++) {
          final w = (r * q * m * schritt) % n;
          final c = _cos[w], s = _sin[w];
          sr += tRe[r] * c - tIm[r] * s;
          si += tRe[r] * s + tIm[r] * c;
        }
        ausRe[ausAnfang + q * m + k] = sr;
        ausIm[ausAnfang + q * m + k] = si;
      }
    }
  }
}

/// Das Log-Mel-Spektrogramm eines Stücks von genau [whisperStueck]
/// Abtastwerten (kürzere vorher mit Stille auffüllen): 80 Zeilen zu je
/// 3000 Rahmen, Zeile für Zeile hintereinander – so, wie der Encoder es
/// als `[1, 80, 3000]` erwartet.
Float32List whisperLogMel(Float32List audio, {List<Float64List>? filter}) {
  assert(audio.length == whisperStueck);
  final fb = filter ?? whisperMelFilter();
  const rand = whisperFenster ~/ 2;
  final n = audio.length;
  // Gespiegelter Rand wie numpy `reflect`: ohne den Randwert selbst.
  double wert(int i) {
    if (i < rand) return audio[rand - i];
    if (i >= rand + n) return audio[n - 2 - (i - rand - n)];
    return audio[i - rand];
  }

  final fenster = Float64List(whisperFenster);
  for (var i = 0; i < whisperFenster; i++) {
    // Periodisches Hann-Fenster, wie `torch.hann_window(400)`.
    fenster[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / whisperFenster);
  }
  final fft = WhisperFft(whisperFenster);
  final re = Float64List(whisperFenster);
  final im = Float64List(whisperFenster);
  final ausRe = Float64List(whisperFenster);
  final ausIm = Float64List(whisperFenster);
  final leistung = Float64List(_bins);
  final mel = Float64List(whisperMelBaender * whisperRahmen);
  var hoechster = double.negativeInfinity;

  // Der letzte der 3001 Rahmen fällt weg, wie im Original.
  for (var f = 0; f < whisperRahmen; f++) {
    final start = f * whisperSchritt;
    for (var i = 0; i < whisperFenster; i++) {
      re[i] = wert(start + i) * fenster[i];
      im[i] = 0;
    }
    fft.transformiere(re, im, ausRe, ausIm);
    for (var k = 0; k < _bins; k++) {
      leistung[k] = ausRe[k] * ausRe[k] + ausIm[k] * ausIm[k];
    }
    for (var m = 0; m < whisperMelBaender; m++) {
      final zeile = fb[m];
      var summe = 0.0;
      for (var k = 0; k < _bins; k++) {
        final g = zeile[k];
        if (g != 0) summe += g * leistung[k];
      }
      final l = math.log(math.max(summe, 1e-10)) / math.ln10;
      mel[m * whisperRahmen + f] = l;
      if (l > hoechster) hoechster = l;
    }
  }
  final untergrenze = hoechster - 8.0;
  final aus = Float32List(mel.length);
  for (var i = 0; i < mel.length; i++) {
    aus[i] = (math.max(mel[i], untergrenze) + 4.0) / 4.0;
  }
  return aus;
}
