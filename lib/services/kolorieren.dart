import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

import 'modellthreads.dart';

/// **Alte Schwarzweiss-Fotos einfärben** (DDColor, siehe
/// ModelCatalog.kolorieren).
///
/// Das Modell sagt nur die **Farbe** voraus, nicht die Helligkeit: Es
/// bekommt ein Graubild in 512 × 512 und liefert die beiden Farbkanäle
/// a und b des Lab-Farbraums in derselben Grösse. Die Helligkeit L kommt
/// aus dem Original in voller Auflösung. Deshalb bleibt ein eingefärbtes
/// Foto genauso scharf wie das graue – nur die Farbe ist weich, und das
/// fällt dem Auge nicht auf.
///
/// **Der Vertrag, nachgemessen:** Eingabe `input` [1,3,512,512] als RGB in
/// 0..1, ohne ImageNet-Normierung; Ausgabe `output` [1,2,512,512] mit a
/// und b in Lab-Einheiten (etwa −130..170 gemessen). In Python an einem
/// entfärbten Bild geprüft: 0,7 s je Durchgang auf der CPU.
class KolorierService {
  KolorierService._(this._session);

  final OrtSession _session;

  /// Die Datei im Modellordner.
  static const datei = 'ddcolor-tiny-fp16.onnx';

  /// Kantenlänge, die das Modell fest verlangt.
  static const modellGroesse = 512;

  static bool isAvailable(String modelsDir) =>
      File('$modelsDir/$datei').existsSync();

  static Future<KolorierService> load(String modelsDir) async {
    final session = await OnnxRuntime().createSession(
      '$modelsDir/$datei',
      options: modelloptionen(providers: [OrtProvider.CPU]),
    );
    return KolorierService._(session);
  }

  /// Färbt [quelle] ein und gibt das Ergebnis in derselben Grösse zurück.
  Future<img.Image> faerbe(img.Image quelle) async {
    final eingabe = await OrtValue.fromList(koloriereingabe(quelle), [
      1,
      3,
      modellGroesse,
      modellGroesse,
    ]);
    final lebend = <OrtValue>{eingabe};
    try {
      final ausgaben = await _session.run({'input': eingabe});
      lebend.addAll(ausgaben.values);
      final roh = await ausgaben['output']!.asFlattenedList();
      final ab = Float32List(roh.length);
      for (var i = 0; i < roh.length; i++) {
        ab[i] = (roh[i] as num).toDouble();
      }
      return eingefaerbt(quelle, ab);
    } finally {
      for (final v in lebend) {
        try {
          await v.dispose();
        } catch (_) {
          // Bereits freigegeben – bestmöglich.
        }
      }
    }
  }

  Future<void> dispose() async => _session.close();
}

/// Das Graubild für das Modell: [quelle] auf 512 × 512, jeder Bildpunkt
/// auf seine Helligkeit gebracht und als RGB in 0..1, Kanal für Kanal.
///
/// „Helligkeit" heisst hier L aus Lab, zurück nach sRGB mit a = b = 0 –
/// genau das, womit das Modell trainiert wurde. Ein schlichter
/// Mittelwert aus R, G und B wäre ein anderes Grau.
Float32List koloriereingabe(img.Image quelle) {
  const n = KolorierService.modellGroesse;
  final klein = img.copyResize(
    quelle,
    width: n,
    height: n,
    interpolation: img.Interpolation.linear,
  );
  final chw = Float32List(3 * n * n);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final p = klein.getPixel(x, y);
      final grau = _srgbAusLinear(
        _luminanz(p.r / 255.0, p.g / 255.0, p.b / 255.0),
      );
      final i = y * n + x;
      chw[i] = grau;
      chw[n * n + i] = grau;
      chw[2 * n * n + i] = grau;
    }
  }
  return chw;
}

/// Setzt die Farbe [ab] (2 × 512 × 512, a zuerst) auf die Helligkeit von
/// [quelle] in deren voller Auflösung.
img.Image eingefaerbt(img.Image quelle, Float32List ab) {
  const n = KolorierService.modellGroesse;
  final b = quelle.width, h = quelle.height;
  final ergebnis = img.Image(width: b, height: h);
  final sx = n / b, sy = n / h;
  for (var y = 0; y < h; y++) {
    // Bilinear: Die Farbe ist niedrig aufgelöst, ein Treppenmuster an
    // Farbgrenzen wäre sichtbar.
    final fy = math.max(0.0, math.min(n - 1.0, (y + 0.5) * sy - 0.5));
    final y0 = fy.floor(), y1 = math.min(y0 + 1, n - 1);
    final wy = fy - y0;
    for (var x = 0; x < b; x++) {
      final fx = math.max(0.0, math.min(n - 1.0, (x + 0.5) * sx - 0.5));
      final x0 = fx.floor(), x1 = math.min(x0 + 1, n - 1);
      final wx = fx - x0;
      double kanal(int k) {
        final o = k * n * n;
        final oben = ab[o + y0 * n + x0] * (1 - wx) + ab[o + y0 * n + x1] * wx;
        final unten = ab[o + y1 * n + x0] * (1 - wx) + ab[o + y1 * n + x1] * wx;
        return oben * (1 - wy) + unten * wy;
      }

      final p = quelle.getPixel(x, y);
      final l = _lAusLuminanz(_luminanz(p.r / 255.0, p.g / 255.0, p.b / 255.0));
      final (r, g, bl) = _labNachSrgb(l, kanal(0), kanal(1));
      ergebnis.setPixelRgb(
        x,
        y,
        (r * 255).round().clamp(0, 255),
        (g * 255).round().clamp(0, 255),
        (bl * 255).round().clamp(0, 255),
      );
    }
  }
  return ergebnis;
}

// --- Farbraum: sRGB <-> CIE Lab (D65), wie OpenCV mit Gleitkommazahlen ---

double _linear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _srgbAusLinear(double c) {
  final v = c <= 0.0031308
      ? 12.92 * c
      : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;
  return v.clamp(0.0, 1.0);
}

/// Relative Helligkeit Y aus sRGB in 0..1.
double _luminanz(double r, double g, double b) =>
    0.2126729 * _linear(r) + 0.7151522 * _linear(g) + 0.0721750 * _linear(b);

double _f(double t) =>
    t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;

double _fInvers(double t) => t > 0.206893 ? t * t * t : (t - 16 / 116) / 7.787;

double _lAusLuminanz(double y) => 116 * _f(y) - 16;

(double, double, double) _labNachSrgb(double l, double a, double b) {
  final fy = (l + 16) / 116;
  final fx = fy + a / 500;
  final fz = fy - b / 200;
  final x = 0.950456 * _fInvers(fx);
  final y = _fInvers(fy);
  final z = 1.088754 * _fInvers(fz);
  final r = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z;
  final g = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z;
  final bl = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z;
  return (_srgbAusLinear(r), _srgbAusLinear(g), _srgbAusLinear(bl));
}
