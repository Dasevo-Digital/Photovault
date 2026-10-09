/// **Musik unter ein fertiges Video legen.**
///
/// Die Diashow wird stumm geschrieben (siehe `diashow.dart`); die Musik
/// kommt in einem zweiten Schritt dazu. So bleibt der Bildteil, wie er
/// ist – auf beiden Wegen dieselbe Kodierung –, und die Tonspur braucht
/// nur das fertige Video und die Musikdatei.
///
/// Was mit der Musik geschieht, ist auf beiden Wegen dasselbe:
///
/// * **Auf die Länge des Videos gebracht.** Ist das Stück kürzer, beginnt
///   es von vorn; ist es länger, endet es mit dem Video.
/// * **Ein- und ausgeblendet** – eine Sekunde am Anfang, drei am Ende.
///   Ein Stück, das mitten im Takt abbricht, klingt nach einem Fehler.
///
/// Unter macOS über AVFoundation (der Sandkasten startet kein ffmpeg,
/// siehe `nativer_videoschreiber.dart`), sonst über das mitgelieferte
/// ffmpeg.
library;

import 'dart:io';

import 'package:flutter/services.dart';

import 'flugvideo.dart';
import 'platform/nativer_videoschreiber.dart';

/// Einblenden am Anfang, Ausblenden am Ende.
const tonEinblenden = Duration(seconds: 1);
const tonAusblenden = Duration(seconds: 3);

/// Die Endungen, die die Auswahl anbietet – was beide Wege lesen.
const tonEndungen = ['mp3', 'm4a', 'aac', 'wav', 'aif', 'aiff', 'flac'];

/// Die Aufrufzeile für ffmpeg.
///
/// `-stream_loop -1` wiederholt die Musik ohne Ende, `-t` schneidet auf
/// die Länge des Videos. Das Bild wird nur kopiert (`-c:v copy`), nicht
/// neu kodiert: Es ist schon fertig, und ein zweites Kodieren kostete
/// Zeit und Schärfe.
List<String> ffmpegTonargumente({
  required String video,
  required String musik,
  required String ziel,
  required Duration dauer,
}) {
  final sekunden = dauer.inMilliseconds / 1000;
  final aus = tonAusblenden.inMilliseconds / 1000;
  final ein = tonEinblenden.inMilliseconds / 1000;
  // Ein Video, kürzer als das Ausblenden, blendet über die ganze Länge.
  final ausAb = (sekunden - aus).clamp(0, sekunden);
  final ausDauer = sekunden - ausAb;
  return [
    '-y',
    '-i',
    video,
    '-stream_loop',
    '-1',
    '-i',
    musik,
    '-map',
    '0:v:0',
    '-map',
    '1:a:0',
    '-c:v',
    'copy',
    '-c:a',
    'aac',
    '-b:a',
    '192k',
    '-af',
    'afade=t=in:st=0:d=${ein.toStringAsFixed(3)},'
        'afade=t=out:st=${ausAb.toStringAsFixed(3)}:'
        'd=${ausDauer.toStringAsFixed(3)}',
    '-t',
    sekunden.toStringAsFixed(3),
    '-movflags',
    '+faststart',
    ziel,
  ];
}

/// Legt [musik] unter [video] und schreibt das Ergebnis nach [ziel].
/// [video] bleibt liegen; aufräumen muss der Aufrufer.
Future<Videoergebnis> unterlegeMusik({
  required File video,
  required File musik,
  required File ziel,
  required Duration dauer,
}) async {
  if (await NativerVideoschreiber.verfuegbar()) {
    try {
      await NativerVideoschreiber.mitTon(
        video: video.path,
        ton: musik.path,
        ziel: ziel.path,
        einblenden: tonEinblenden.inMilliseconds / 1000,
        ausblenden: tonAusblenden.inMilliseconds / 1000,
      );
      return (ausgang: Videoausgang.fertig, meldung: null);
    } on PlatformException catch (e) {
      return (ausgang: Videoausgang.fehler, meldung: e.message ?? '$e');
    } on MissingPluginException {
      return (ausgang: Videoausgang.keinWerkzeug, meldung: null);
    }
  }
  final werkzeug = await ffmpegPfad();
  if (werkzeug == null) {
    return (ausgang: Videoausgang.keinWerkzeug, meldung: null);
  }
  final r = await Process.run(
    werkzeug,
    ffmpegTonargumente(
      video: video.path,
      musik: musik.path,
      ziel: ziel.path,
      dauer: dauer,
    ),
  );
  if (r.exitCode != 0) {
    final zeilen = '${r.stderr}'.trim().split('\n');
    return (ausgang: Videoausgang.fehler, meldung: zeilen.last);
  }
  return (ausgang: Videoausgang.fertig, meldung: null);
}
