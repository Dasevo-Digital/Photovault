import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/services/entwicklungswerte.dart';
import 'package:kern/services/weissabgleich.dart';
import 'package:zierbild/entwickeln_rechnung.dart';
import 'package:zierbild/entwickeln_shader.dart';

/// **Der Weissabgleich am Dart-Renderer** (Shader, wie unter Linux, Windows,
/// auf dem Handy und in der Vorschau am Mac), #466.
///
/// Die Bilder unter test/fixtures/weissabgleich_alt/ hat der Shader **vor**
/// der Umstellung gerechnet (Stand c6aca54a, „höher ist kühler“), aus der
/// Tafel unten und mit den Werten im Dateinamen. Rechnet der heutige
/// Shader mit den umgerechneten Werten, muss Punkt für Punkt dasselbe Bild
/// herauskommen – so sehen bereits entwickelte Fotos nach dem Aufstufen
/// aus wie vorher.
const _breite = 32, _hoehe = 16;

Uint8List _tafel() {
  final b = Uint8List(_breite * _hoehe * 4);
  for (var y = 0; y < _hoehe; y++) {
    for (var x = 0; x < _breite; x++) {
      final i = (y * _breite + x) * 4;
      b[i] = (x * 8 + 4) & 255;
      b[i + 1] = (y * 16 + 8) & 255;
      b[i + 2] = (x * 5 + y * 11 + 3) % 256;
      b[i + 3] = 255;
    }
  }
  return b;
}

/// Die gespeicherten Werte, mit denen die Bilder entstanden sind – in der
/// früheren Bedeutung.
final _faelle = <String, DevelopAdjustments>{
  for (final k in [
    1500.0,
    2000.0,
    2600.0,
    3200.0,
    3520.8333333333335,
    4000.0,
    5000.0,
    6000.0,
    6500.0,
    7000.0,
    9000.0,
    12000.0,
    15000.0,
  ])
    'k${k.toStringAsFixed(2)}_t0': DevelopAdjustments(temperature: k, tint: 0),
  'k3000.00_t40': const DevelopAdjustments(temperature: 3000, tint: 40),
  'k8000.00_t-40': const DevelopAdjustments(temperature: 8000, tint: -40),
  'k4500.00_mix': const DevelopAdjustments(
    temperature: 4500,
    tint: 10,
    exposure: 0.4,
    contrast: 0.2,
    shadows: 0.1,
  ),
};

DevelopAdjustments _umgerechnet(DevelopAdjustments a) => DevelopAdjustments(
  temperature: temperaturAusFruehererBedeutung(a.temperature!),
  tint: a.tint,
  exposure: a.exposure,
  contrast: a.contrast,
  shadows: a.shadows,
);

Future<Uint8List> _rechne(
  Entwicklungsvorschau v,
  ui.Image basis,
  DevelopAdjustments a,
) async {
  final bild = await v.rechne(basis, a);
  try {
    return (await bild.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
  } finally {
    bild.dispose();
  }
}

void main() {
  late Entwicklungsvorschau vorschau;
  late ui.Image tafel;

  setUpAll(() async {
    vorschau = (await Entwicklungsvorschau.lade())!;
    tafel = await texturVonBytes(_tafel(), _breite, _hoehe);
  });
  tearDownAll(() {
    vorschau.dispose();
    tafel.dispose();
  });

  test('umgerechnete Werte ergeben Punkt für Punkt das frühere Bild', () async {
    var groessteAbweichung = 0;
    for (final e in _faelle.entries) {
      final alt = img.decodePng(
        File('test/fixtures/weissabgleich_alt/${e.key}.png').readAsBytesSync(),
      )!;
      final neu = await _rechne(vorschau, tafel, _umgerechnet(e.value));
      for (var y = 0; y < _hoehe; y++) {
        for (var x = 0; x < _breite; x++) {
          final p = alt.getPixel(x, y);
          final i = (y * _breite + x) * 4;
          for (final (k, w) in [(0, p.r), (1, p.g), (2, p.b)]) {
            final d = (neu[i + k] - w.toInt()).abs();
            if (d > groessteAbweichung) groessteAbweichung = d;
            // Eine Stufe Rundung in Float32 auf der GPU ist erlaubt, mehr
            // nicht.
            expect(d, lessThanOrEqualTo(1), reason: '${e.key} ($x, $y)');
          }
        }
      }
    }
    // Damit der Vergleich nicht zufällig an gleichen Bildern besteht: Die
    // Fälle unterscheiden sich wirklich.
    final kalt = img.decodePng(
      File('test/fixtures/weissabgleich_alt/k2000.00_t0.png').readAsBytesSync(),
    )!;
    final neutral = img.decodePng(
      File('test/fixtures/weissabgleich_alt/k6500.00_t0.png').readAsBytesSync(),
    )!;
    expect(kalt.getPixel(16, 8).r, greaterThan(neutral.getPixel(16, 8).r + 20));
    // Am Entwicklungsrechner gemessen: 0 – bitgleich.
    expect(groessteAbweichung, lessThanOrEqualTo(1));
  });

  test(
    'ohne Umrechnung sähe ein früher entwickeltes Foto anders aus',
    () async {
      // Gegenprobe: Die alte Zahl unverändert in den neuen Shader – genau das
      // verhindert die Migration.
      final alt = img.decodePng(
        File(
          'test/fixtures/weissabgleich_alt/k4000.00_t0.png',
        ).readAsBytesSync(),
      )!;
      final neu = await _rechne(
        vorschau,
        tafel,
        const DevelopAdjustments(temperature: 4000, tint: 0),
      );
      final i = (8 * _breite + 16) * 4;
      final p = alt.getPixel(16, 8);
      expect((neu[i] - p.r.toInt()).abs(), greaterThan(20));
    },
  );

  test('niedrige Kelvin-Zahl blau, hohe gelb', () async {
    final grau = Uint8List(8 * 8 * 4);
    for (var i = 0; i < grau.length; i += 4) {
      grau
        ..[i] = 128
        ..[i + 1] = 128
        ..[i + 2] = 128
        ..[i + 3] = 255;
    }
    final basis = await texturVonBytes(grau, 8, 8);
    addTearDown(basis.dispose);
    Future<(int, int)> rotBlau(double k) async {
      final p = await _rechne(
        vorschau,
        basis,
        DevelopAdjustments(temperature: k, tint: 0),
      );
      return (p[0], p[2]);
    }

    final (r3000, b3000) = await rotBlau(3000);
    expect(b3000, greaterThan(r3000 + 15), reason: '3000 K wird blau');
    final (r10000, b10000) = await rotBlau(10000);
    expect(r10000, greaterThan(b10000 + 15), reason: '10000 K wird gelb');
    final (r6500, b6500) = await rotBlau(6500);
    expect((r6500 - 128).abs(), lessThanOrEqualTo(1));
    expect((b6500 - 128).abs(), lessThanOrEqualTo(1));
  });
}
