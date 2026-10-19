/// Das Flugvideo – Bild für Bild gezeichnet, die Plattform schreibt es.
///
/// Gezeichnet wird hier, für Rechner und Handy gleich: Die Landschaft
/// malt jedes Bild auf eine Leinwand abseits des Bildschirms. Wohin die
/// Bilder gehen, entscheidet die App über einen [Videoschreiber] – am Mac
/// AVFoundation, unter Linux und Windows ffmpeg, am iPhone wieder
/// AVFoundation.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show PlatformException;

/// Wie ein Lauf ausgegangen ist.
enum Videoausgang {
  fertig,

  /// Weder der native Schreiber noch ffmpeg – dann geht es hier nicht.
  keinWerkzeug,

  /// Der Aufrufer hat abgebrochen.
  abgebrochen,

  /// Der Kodierer hat sich beschwert. Was er gesagt hat, steht in
  /// [Videoergebnis.meldung].
  fehler,
}

typedef Videoergebnis = ({Videoausgang ausgang, String? meldung});

/// Wie viele Bilder je Sekunde.
///
/// **Dreissig und nicht sechzig.** Ein Überflug ist eine gleichmässige
/// Bewegung ohne schnelle Wechsel; sechzig Bilder verdoppeln Rechenzeit
/// und Dateigrösse und sind daneben nicht zu unterscheiden. Fünfundzwanzig
/// wären europäisches Fernsehen, dreissig ist das, was Telefone
/// aufnehmen und was jede Plattform ohne Umrechnung annimmt.
const int videoBilderJeSekunde = 30;

/// Wohin die Bilder eines laufenden Videos gehen.
abstract interface class Videoziel {
  Future<void> bild(Uint8List rgba);

  /// Schliesst die Datei ab. `null`, wenn alles gut ging, sonst der Grund.
  Future<String?> beende();

  /// Bricht ab und räumt die halbe Datei weg.
  Future<void> verwirf();
}

/// Was eine App an Videoausgabe anbietet.
abstract interface class Videoschreiber {
  /// Ob hier überhaupt ein Video geschrieben werden kann.
  Future<bool> moeglich();

  /// Schreibt den Flug nach [ziel]: [dauer] lang, [breite] mal [hoehe].
  Future<Videoergebnis> schreibe({
    required File ziel,
    required int breite,
    required int hoehe,
    required Duration dauer,
    required void Function(ui.Canvas leinwand, ui.Size flaeche, double t)
    maleBild,
    Future<void> Function(double t)? vorBild,
    void Function(double anteil)? fortschritt,
    bool Function()? abbruch,
  });
}

/// Malt [bilder] Bilder in [breite] mal [hoehe] und gibt sie an [ausgabe].
///
/// [breite] und [hoehe] sind schon gerade (siehe `schreibeFlugvideo` am
/// Rechner): `yuv420p` tastet die Farbe halb so fein ab wie die
/// Helligkeit, und eine ungerade Kante lässt sich nicht halbieren.
Future<Videoergebnis> schreibeBilderfolge({
  required Videoziel ausgabe,
  required int breite,
  required int hoehe,
  required int bilder,
  required void Function(ui.Canvas leinwand, ui.Size flaeche, double t)
  maleBild,
  Future<void> Function(double t)? vorBild,
  void Function(double anteil)? fortschritt,
  bool Function()? abbruch,
}) async {
  final b = breite;
  final h = hoehe;
  try {
    for (var i = 0; i < bilder; i++) {
      if (abbruch?.call() ?? false) {
        await ausgabe.verwirf();
        return (ausgang: Videoausgang.abgebrochen, meldung: null);
      }
      final t = bilder == 1 ? 0.0 : i / (bilder - 1);
      // **Vor dem Malen, nicht danach.** Was hier nachgeladen wird,
      // gehört in genau dieses Bild; ein Video hat kein „ein Bild
      // später".
      await vorBild?.call(t);
      final sammler = ui.PictureRecorder();
      maleBild(ui.Canvas(sammler), ui.Size(b.toDouble(), h.toDouble()), t);
      final aufnahme = sammler.endRecording();
      ui.Image bild;
      try {
        bild = await aufnahme.toImage(b, h);
      } finally {
        aufnahme.dispose();
      }
      try {
        final roh = await bild.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (roh == null) continue;
        await ausgabe.bild(roh.buffer.asUint8List());
      } finally {
        bild.dispose();
      }
      fortschritt?.call((i + 1) / bilder);
    }
  } catch (e) {
    await ausgabe.verwirf();
    return (
      ausgang: Videoausgang.fehler,
      meldung: e is PlatformException ? (e.message ?? '$e') : '$e',
    );
  }

  final grund = await ausgabe.beende();
  if (grund != null) {
    return (ausgang: Videoausgang.fehler, meldung: grund);
  }
  return (ausgang: Videoausgang.fertig, meldung: null);
}
