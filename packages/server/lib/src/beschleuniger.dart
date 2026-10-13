import 'dart:math' as math;
import 'dart:typed_data';

/// Womit die Modelle des Servers rechnen – aus `PV_BESCHLEUNIGER`.
///
/// | Wert              | Anbieter in ONNX Runtime                         |
/// |-------------------|--------------------------------------------------|
/// | `cpu` (Vorgabe)   | –                                                |
/// | `openvino`        | OpenVINO auf der Intel-Grafik (`GPU`)            |
/// | `openvino:NPU`    | OpenVINO auf einem anderen Gerät (`CPU`, `NPU`, `GPU.1`, `AUTO:GPU,CPU` …) |
/// | `cuda`, `cuda:1`  | CUDA auf der (ersten) NVIDIA-Karte               |
/// | `coreml`          | CoreML (macOS; zum Prüfen auf einem Mac)         |
///
/// Dazu gehört eine Bibliothek, die den Anbieter enthält: OpenVINO und CUDA
/// sind nicht im gewöhnlichen `libonnxruntime.so`. Fehlt er, rechnet der
/// Server auf der CPU und sagt es.
///
/// **Jedes Modell besteht erst eine Gegenprobe.** Seine ersten Läufe rechnen
/// auf dem Beschleuniger und auf der CPU; nur wenn die Ausgaben
/// übereinstimmen, übernimmt der Beschleuniger (siehe `FfiOnnxPlattform`).
/// Ein Beschleuniger rechnet nie schneller falsch.
class Beschleuniger {
  const Beschleuniger._(this.art, {this.geraet});

  static const cpu = Beschleuniger._('cpu');

  /// `cpu`, `openvino`, `cuda` oder `coreml`.
  final String art;

  /// Das Gerät, wo es eines zu wählen gibt.
  final String? geraet;

  bool get istCpu => art == 'cpu';

  /// Wie die Herkunft eines Ergebnisses ihn nennt: `CPU`, `OpenVINO:GPU`,
  /// `CUDA:0`, `CoreML`.
  String get name => switch (art) {
    'openvino' => 'OpenVINO:$geraet',
    'cuda' => 'CUDA:$geraet',
    'coreml' => 'CoreML',
    _ => 'CPU',
  };

  /// Liest `PV_BESCHLEUNIGER`; `null` oder leer heisst CPU.
  static Beschleuniger aus(String? text) {
    final t = (text ?? '').trim();
    if (t.isEmpty) return cpu;
    final teile = t.split(':');
    final art = teile.first.toLowerCase();
    final geraet = teile.length > 1 ? teile.sublist(1).join(':') : null;
    return switch (art) {
      'cpu' => cpu,
      'openvino' => Beschleuniger._('openvino', geraet: geraet ?? 'GPU'),
      'cuda' => Beschleuniger._(
        'cuda',
        geraet: int.tryParse(geraet ?? '0') != null
            ? geraet ?? '0'
            : throw FormatException('cuda:$geraet – erwartet eine Zahl'),
      ),
      'coreml' => const Beschleuniger._('coreml'),
      _ => throw FormatException(
        'PV_BESCHLEUNIGER=$t – bekannt sind cpu, openvino, cuda, coreml',
      ),
    };
  }

  /// Die Optionen des Anbieters. [zwischenspeicher] nimmt OpenVINO für die
  /// übersetzten Modelle: Ohne ihn übersetzt die Grafik jedes Modell bei
  /// jedem Laden neu, und das dauert Sekunden.
  ///
  /// OpenVINO rechnet auf der Grafik sonst in halber Genauigkeit (FP16);
  /// `ACCURACY` behält die des Modells – die Gegenprobe gegen die CPU soll
  /// eine Frage der Rechenwerke sein, nicht der Zahlenbreite.
  Map<String, String> optionen({String? zwischenspeicher}) => switch (art) {
    'openvino' => {
      'device_type': geraet!,
      'precision': 'ACCURACY',
      'cache_dir': ?zwischenspeicher,
    },
    'cuda' => {'device_id': geraet!},
    _ => const {},
  };

  @override
  String toString() => name;
}

/// Wann zwei Ausgaben eines Modells als gleich gelten: Kosinus der Werte als
/// Vektor (mindestens [mindestKosinus]) und grösste Abweichung, gemessen an
/// der grössten Zahl der CPU-Ausgabe (höchstens [hoechsteAbweichung]).
///
/// Ein Beschleuniger rechnet in anderer Reihenfolge und rundet anders;
/// bitgleich wird es nie. Was darüber hinausgeht, ist kein Rundungsfehler
/// mehr, sondern ein anderes Ergebnis. Gemessen mit CoreML auf einem Mac:
/// CLIP 1,0000000 (bestanden), die Gesichtserkennung 0,99912 (knapp
/// verworfen), der Erkennungsteil der Texterkennung 0,24 (CoreML rechnet
/// ihn falsch).
///
/// **Winzige Abweichungen gehen immer durch** ([vernachlaessigbar]): Auf
/// einem Bild ohne Text ist die Ausgabe der Texterkennung fast überall
/// null, und dann wiegt Rauschen von 10⁻⁷ im Kosinus schwer (OpenVINO auf
/// der CPU: 0,999788 – verworfen, obwohl nichts anders war).
const mindestKosinus = 0.9999;
const hoechsteAbweichung = 0.01;
const vernachlaessigbar = 1e-4;

/// `null`, wenn [anderer] dasselbe ist wie [cpu]; sonst, was abweicht.
String? abweichung(Float32List cpu, Float32List anderer) {
  var xx = 0.0, yy = 0.0, xy = 0.0, groesste = 0.0, abstand = 0.0;
  for (var i = 0; i < cpu.length; i++) {
    final u = cpu[i], v = anderer[i];
    if (u.isNaN != v.isNaN) return 'NaN';
    if (u.isNaN) continue;
    xx += u * u;
    yy += v * v;
    xy += u * v;
    if (u.abs() > groesste) groesste = u.abs();
    if ((u - v).abs() > abstand) abstand = (u - v).abs();
  }
  final kosinus = xx == 0 && yy == 0
      ? 1.0
      : (xx == 0 || yy == 0 ? 0.0 : xy / (math.sqrt(xx) * math.sqrt(yy)));
  final relativ = abstand / (groesste < 1 ? 1 : groesste);
  if (relativ <= vernachlaessigbar) return null;
  if (kosinus >= mindestKosinus && relativ <= hoechsteAbweichung) return null;
  return 'Kosinus ${kosinus.toStringAsFixed(6)}, '
      'Abweichung ${relativ.toStringAsExponential(2)}';
}
