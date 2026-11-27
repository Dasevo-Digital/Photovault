import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:kern/services/wasserzeichen.dart';

/// Wie der Text eines Wasserzeichens aussieht (#497): die Systemschrift,
/// halbfett, weiss mit einem weichen dunklen Schatten.
///
/// Weiss mit Schatten, weil das Zeichen auf jedem Foto lesbar bleiben
/// soll, ohne dass jemand eine Farbe wählt: Auf hellem Himmel trägt der
/// Schatten die Buchstaben, auf dunklem Grund das Weiss. Dieselbe Angabe
/// zeichnet die Vorschau im Editor, damit sie zeigt, was herauskommt.
TextStyle wasserzeichenTextstil(double schriftgroesse) => TextStyle(
  color: const Color(0xFFFFFFFF),
  fontSize: schriftgroesse,
  fontWeight: FontWeight.w600,
  height: 1.15,
  shadows: [
    Shadow(
      color: const Color(0x99000000),
      blurRadius: schriftgroesse * 0.08,
      offset: Offset(0, schriftgroesse * 0.03),
    ),
  ],
);

/// Platz um den Text für den Schatten, als Anteil der Schriftgrösse.
const _schattenraum = 0.15;

/// Breiter wird kein Textbild: Grafikkarten zeichnen Flächen bis 16384
/// Pixel, und mehr als die Hälfte eines Exports in voller Auflösung ist
/// selbst für eine sehr grosse Vorgabe genug. Braucht ein Bild mehr (ein
/// Panorama mit bis zu 30000 Pixeln Breite), wird das Zeichen beim
/// Einrechnen vergrössert.
const wasserzeichentextHoechstensBreite = 8000;

TextPainter _setzer(String text, double schriftgroesse) => TextPainter(
  text: TextSpan(text: text, style: wasserzeichenTextstil(schriftgroesse)),
  textDirection: TextDirection.ltr,
  maxLines: 1,
)..layout();

/// Breite durch Höhe des Textbilds, das [zeichneWasserzeichentext] für
/// [text] liefert – für die Vorschau, die das Zeichen an dieselbe Stelle
/// setzen soll wie der Export.
double wasserzeichentextVerhaeltnis(String text) {
  const mess = 100.0;
  final setzer = _setzer(text, mess);
  try {
    return (setzer.width + 2 * _schattenraum * mess) /
        (setzer.height + 2 * _schattenraum * mess);
  } finally {
    setzer.dispose();
  }
}

/// Zeichnet [text] als PNG mit Transparenz, [breite] Pixel breit (samt
/// dem Platz für den Schatten) – für einen Link, dessen Zeichen der Server
/// einrechnet.
///
/// Eingerechnet wird im Kern (`kern/services/wasserzeichen.dart`), der
/// keinen Text zeichnen kann.
Future<Uint8List> zeichneWasserzeichentext(
  String text, {
  required int breite,
}) async {
  final bild = await _zeichne(text, breite);
  try {
    final daten = await bild.toByteData(format: ui.ImageByteFormat.png);
    return daten!.buffer.asUint8List();
  } finally {
    bild.dispose();
  }
}

/// [zeichneWasserzeichentext] als Pixel, fertig zum Einrechnen – für den
/// Export und das Fotobuch, die das Zeichen selbst einrechnen.
///
/// Der Export zeichnet den Text für jedes Bild in genau der Breite, die
/// das Zeichen dort bekommt: So wird beim Einrechnen nichts skaliert, und
/// die Kanten bleiben so scharf, wie die Schrift sie setzt. Ohne den Umweg
/// über ein PNG: Das kostete je Foto ein Kodieren und ein Dekodieren, und
/// das gelesene PNG unterläge der Grenze für Fremdes
/// ([Wasserzeichen.hoechstensBildKante]) – ein Text auf einem Panorama ist
/// breiter. Über [wasserzeichentextHoechstensBreite] hinaus wird das
/// Zeichen beim Einrechnen vergrössert.
Future<Zeichenpixel> zeichneWasserzeichentextPixel(
  String text, {
  required int breite,
}) async {
  final bild = await _zeichne(text, breite);
  try {
    final daten = await bild.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    return Zeichenpixel.ausGerade(
      bild.width,
      bild.height,
      daten!.buffer.asUint8List(daten.offsetInBytes, daten.lengthInBytes),
    );
  } finally {
    bild.dispose();
  }
}

Future<ui.Image> _zeichne(String text, int breite) async {
  const mess = 100.0;
  final probe = _setzer(text, mess);
  final jeGroesse = probe.width / mess + 2 * _schattenraum;
  probe.dispose();
  final ziel = breite.clamp(1, wasserzeichentextHoechstensBreite);
  final schriftgroesse = (jeGroesse <= 0 ? mess : ziel / jeGroesse).clamp(
    4.0,
    1200.0,
  );
  final setzer = _setzer(text, schriftgroesse);
  final rand = _schattenraum * schriftgroesse;
  final w = math.max(1, (setzer.width + 2 * rand).ceil());
  final h = math.max(1, (setzer.height + 2 * rand).ceil());
  final aufnahme = ui.PictureRecorder();
  setzer.paint(Canvas(aufnahme), Offset(rand, rand));
  setzer.dispose();
  final bild = aufnahme.endRecording();
  try {
    return await bild.toImage(w, h);
  } finally {
    bild.dispose();
  }
}
