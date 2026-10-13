import 'dart:io' show Platform;

import '../services/model_catalog.dart';

/// Welche Art von Ergebnis aus welchen Modelldateien entsteht – für die
/// Herkunft eines Ergebnisses (Tabelle `ergebnisherkunft`, Issue #104).
enum Ergebnisart {
  clip(['clip_image_encoder.onnx']),
  gesichter(['face_detection_yunet.onnx', 'face_recognition_sface.onnx']),
  texterkennung(['ocr_det.onnx', 'ocr_rec.onnx']),
  bildbeschreibung([
    'florence_vision.onnx',
    'florence_embed.onnx',
    'florence_encoder.onnx',
    'florence_decoder.onnx',
  ]),
  spracherkennung(['whisper_encoder.onnx', 'whisper_decoder.onnx']);

  const Ergebnisart(this.dateien);

  final List<String> dateien;

  /// Die Dateien mit dem Anfang ihrer Prüfsumme aus dem Katalog – die
  /// Fassung des Modells, ohne die Datei selbst zu lesen.
  String get modell => [
    for (final d in dateien) '$d@${_pruefsumme(d)?.substring(0, 12) ?? '?'}',
  ].join(', ');

  static String? _pruefsumme(String datei) {
    for (final e in ModelCatalog.all) {
      for (final f in e.files) {
        if (f.fileName == datei) return f.sha256;
      }
    }
    return null;
  }
}

/// Wer rechnet: das Gerät und, je Modelldatei, womit.
class Rechner {
  const Rechner({required this.geraet, this.beschleunigerFuer});

  /// Der Rechner, auf dem die App läuft.
  factory Rechner.hier() => Rechner(geraet: 'Rechner (${_system()})');

  /// Der Server (siehe packages/server), mit seinem Beschleuniger je Datei.
  factory Rechner.server(String Function(String datei) beschleunigerFuer) =>
      Rechner(
        geraet: 'Server (${_system()})',
        beschleunigerFuer: beschleunigerFuer,
      );

  final String geraet;

  /// Womit eine Modelldatei rechnet; ohne Angabe die CPU.
  final String Function(String datei)? beschleunigerFuer;

  /// Womit die Modelle einer Art rechneten – verschiedene mit `+`.
  String beschleuniger(Ergebnisart art) => {
    for (final d in art.dateien) beschleunigerFuer?.call(d) ?? 'CPU',
  }.join('+');

  static String _system() => switch (Platform.operatingSystem) {
    'macos' => 'macOS',
    'windows' => 'Windows',
    'linux' => 'Linux',
    'ios' => 'iOS',
    'android' => 'Android',
    final s => s,
  };
}
