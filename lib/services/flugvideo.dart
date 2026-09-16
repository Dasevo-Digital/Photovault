/// **Den Überflug als Video – zum Weitergeben.**
///
/// Ein Überflug, den nur die App zeigen kann, endet in der App. Wer eine
/// Wanderung jemandem zeigen will, der kein PhotoVault hat, braucht eine
/// Datei. Genau das ist bei Strava und Relive der Grund, warum überhaupt
/// jemand einen Flyover erzeugt.
///
/// **Zwei Wege, und die Plattform entscheidet.**
///
///   * **macOS: AVFoundation**, siehe [NativerVideoschreiber]. Kein
///     fremdes Programm, Kodierung über VideoToolbox in Hardware.
///   * **Linux und Windows: ffmpeg**, das dort im Paket liegt. Rohe
///     Bildpunkte über `stdin`, nicht tausend PNG-Dateien: Die Bilder
///     entstehen ohnehin; sie einzeln auf die Platte zu schreiben und von
///     dort wieder einzulesen wäre bei dreissig Sekunden in 1920 × 1080
///     ein Umweg über rund neunhundert Dateien und mehrere Gigabyte
///     Zwischenablage.
///
/// **Warum unter macOS nicht auch ffmpeg.** Es lag bis 3.5.0 an einem
/// selbst installierten ffmpeg, und das konnte nie funktionieren – aus
/// zwei Gründen, die unabhängig voneinander schon je für sich reichen:
/// Der Sandkasten darf kein fremdes Programm starten (`posix_spawn` auf
/// `/opt/homebrew/bin/ffmpeg` scheitert mit EPERM, obwohl `stat()`
/// gelingt), und was der Finder startet, hat Homebrew gar nicht erst im
/// `PATH`. Der Rat „installieren Sie ffmpeg" war damit falsch, und zwar
/// doppelt.
///
/// **Gemessen** (`tool/flugvideo_nativ_probe.sh` bzw.
/// `tool/flugvideo_probe_test.dart`), je 90 Bilder in 1920 × 1080:
///
/// ```
/// AVFoundation (M-Mac)      0,3 s   1290 kB
/// ffmpeg (TestKubuntu)      4,4 s    516 kB
/// ```
///
/// Die Datei ist beim nativen Weg grösser, weil VideoToolbox auf eine
/// feste Datenrate kodiert statt auf eine Qualitätsstufe; 12 Mbit/s bei
/// 1080p30 sind dieselbe Grössenordnung, in der ffmpeg mit `-crf 20`
/// landet.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'platform/desktop_image_tools.dart';
import 'platform/nativer_videoschreiber.dart';

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

/// Wo ffmpeg liegt – oder `null`. Unter macOS immer `null`, siehe oben.
Future<String?> ffmpegPfad() => DesktopImageTools.aufruf('ffmpeg');

/// Ob ein Videoexport überhaupt möglich ist.
///
/// **Nicht mehr „gibt es ffmpeg".** Genau diese Frage war der Fehler: Sie
/// beantwortete unter macOS für immer „nein" und schickte den Benutzer
/// zu Homebrew, wo nichts zu holen war.
Future<bool> videoausgabeMoeglich() async =>
    await NativerVideoschreiber.verfuegbar() || await ffmpegPfad() != null;

/// Ein Ziel, in das Bilder wandern – nativ oder über ffmpeg.
abstract class _Videoziel {
  /// Hängt ein Bild an. Wirft, wenn es nicht ankommt.
  Future<void> bild(Uint8List rgba);

  /// Schliesst ab. `null` heisst gut, sonst steht dort der Grund.
  Future<String?> beende();

  /// Bricht ab und lässt **keine** halbe Datei zurück: Die sieht aus wie
  /// eine fertige und lässt sich nicht abspielen.
  Future<void> verwirf();
}

class _NativesZiel implements _Videoziel {
  @override
  Future<void> bild(Uint8List rgba) => NativerVideoschreiber.bild(rgba);

  @override
  Future<String?> beende() async {
    try {
      await NativerVideoschreiber.fertig();
      return null;
    } on PlatformException catch (e) {
      return e.message ?? '$e';
    }
  }

  @override
  Future<void> verwirf() => NativerVideoschreiber.verwirf();
}

class _FfmpegZiel implements _Videoziel {
  _FfmpegZiel(this._prozess, this._ziel) {
    // **Die Fehlerausgabe muss mitgelesen werden, auch wenn sie niemanden
    // interessiert.** Ein Prozess, dessen `stderr` niemand leert, bleibt
    // stehen, sobald die Puffergrösse des Betriebssystems erreicht ist –
    // und ffmpeg schreibt bei jedem Bild eine Zeile.
    _fehlerstrom = _prozess.stderr
        .transform(const SystemEncoding().decoder)
        .listen(_meldungen.write);
  }

  final Process _prozess;
  final File _ziel;
  final StringBuffer _meldungen = StringBuffer();
  late final StreamSubscription<void> _fehlerstrom;

  @override
  Future<void> bild(Uint8List rgba) async {
    _prozess.stdin.add(rgba);
    // Nach jedem Bild leeren: Sonst sammelt Dart die Bilder im eigenen
    // Puffer, und aus dem Strom wird wieder ein Gigabyte im Speicher –
    // genau das, was der Weg über `stdin` vermeiden soll.
    await _prozess.stdin.flush();
  }

  @override
  Future<String?> beende() async {
    await _prozess.stdin.close();
    final code = await _prozess.exitCode;
    await _fehlerstrom.cancel();
    if (code == 0) return null;
    // Nur die letzten Zeilen: ffmpeg schreibt bei dreissig Sekunden
    // neunhundert Fortschrittszeilen, und der Grund steht am Ende.
    return _letzteZeilen(_meldungen.toString(), 6);
  }

  @override
  Future<void> verwirf() async {
    _prozess.kill();
    await _fehlerstrom.cancel();
    try {
      if (_ziel.existsSync()) await _ziel.delete();
    } catch (_) {
      // Nicht löschen zu können ist kein Grund, den Abbruch zu einem
      // Fehler zu machen.
    }
  }
}

/// Schreibt den Flug als MP4.
///
/// [maleBild] wird je Bild gerufen und bekommt den Fortschritt von 0 bis
/// 1. [vorBild] darf vorher noch etwas holen – der Landschaftsflug lädt
/// dort die Kacheln nach, die in genau diesem Bild stehen.
/// [fortschritt] meldet, wie weit der Lauf ist – für die Anzeige.
/// [abbruch] wird vor jedem Bild gefragt; sagt es `true`, hört der Lauf
/// auf und die halbfertige Datei wird **gelöscht**.
///
/// [ffmpeg] und [nativ] sind die beiden Prüfnähte: Ein gesetztes [ffmpeg]
/// erzwingt den Prozessweg mit genau diesem Programm (so prüft
/// `flugvideo_test.dart` die Schalter an einem gestellten ffmpeg),
/// [nativ] erzwingt den Weg über AVFoundation. Ohne beides entscheidet
/// die Plattform.
Future<Videoergebnis> schreibeFlugvideo({
  required File ziel,
  required int breite,
  required int hoehe,
  required Duration dauer,
  required void Function(ui.Canvas leinwand, ui.Size flaeche, double t)
      maleBild,
  Future<void> Function(double t)? vorBild,
  int bilderJeSekunde = videoBilderJeSekunde,
  void Function(double anteil)? fortschritt,
  bool Function()? abbruch,
  String? ffmpeg,
  bool? nativ,
}) async {
  // **Gerade Kantenlängen.** `yuv420p` tastet die Farbe halb so fein ab
  // wie die Helligkeit; eine ungerade Kante lässt sich nicht halbieren,
  // und ffmpeg bricht mit „width not divisible by 2" ab.
  final b = breite - (breite % 2);
  final h = hoehe - (hoehe % 2);
  final bilder = (dauer.inMilliseconds * bilderJeSekunde / 1000).round();
  if (b < 2 || h < 2 || bilder < 1) {
    // Kein Satz für die Oberfläche: Eine Grösse oder Dauer von null ist
    // ein Programmierfehler, kein Zustand, in den jemand gerät. Und die
    // Prüfung steht **vor** allem anderen, damit kein Prozess und keine
    // Datei entsteht, die gleich wieder wegzuräumen wären.
    return (ausgang: Videoausgang.fehler, meldung: 'size=${b}x$h frames=$bilder');
  }

  final ueberNativ =
      nativ ?? (ffmpeg == null && await NativerVideoschreiber.verfuegbar());

  final _Videoziel ausgabe;
  if (ueberNativ) {
    try {
      await NativerVideoschreiber.beginne(
        ziel: ziel.path,
        breite: b,
        hoehe: h,
        bilderJeSekunde: bilderJeSekunde,
      );
    } on PlatformException catch (e) {
      return (ausgang: Videoausgang.fehler, meldung: e.message ?? '$e');
    } on MissingPluginException {
      return (ausgang: Videoausgang.keinWerkzeug, meldung: null);
    }
    ausgabe = _NativesZiel();
  } else {
    final werkzeug = ffmpeg ?? await ffmpegPfad();
    if (werkzeug == null) {
      return (ausgang: Videoausgang.keinWerkzeug, meldung: null);
    }
    // **Der Start selbst kann werfen.** Ein Pfad, der zwischen Suche und
    // Aufruf verschwindet – ein deinstalliertes Homebrew, ein
    // ausgehängtes Laufwerk – lässt `Process.start` mit einer
    // `ProcessException` abbrechen, und die fiel bis hierher durch bis in
    // die Oberfläche. Gefunden hat es der Test mit einem Pfad, den es
    // absichtlich nicht gibt.
    final Process prozess;
    try {
      prozess = await Process.start(werkzeug, [
        '-y',
        '-f', 'rawvideo',
        '-pixel_format', 'rgba',
        '-video_size', '${b}x$h',
        '-framerate', '$bilderJeSekunde',
        '-i', '-',
        '-c:v', 'libx264',
        '-preset', 'medium',
        // 20 ist sichtbar verlustfrei und ergibt bei dreissig Sekunden in
        // 1920 x 1080 rund 15 MB - klein genug zum Verschicken.
        '-crf', '20',
        '-pix_fmt', 'yuv420p',
        // Der Index nach vorn: Ohne das faengt ein Abspieler im Netz erst
        // an, wenn die ganze Datei da ist.
        '-movflags', '+faststart',
        ziel.path,
      ]);
    } catch (e) {
      return (ausgang: Videoausgang.fehler, meldung: '$e');
    }
    ausgabe = _FfmpegZiel(prozess, ziel);
  }

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

String _letzteZeilen(String text, int wieviele) {
  final zeilen = text
      .split(RegExp(r'[\r\n]+'))
      .where((z) => z.trim().isNotEmpty)
      .toList();
  if (zeilen.length <= wieviele) return zeilen.join('\n');
  return zeilen.sublist(zeilen.length - wieviele).join('\n');
}
