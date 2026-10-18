import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Videos als H.264 für Browser, die das Original nicht abspielen.
///
/// **Warum.** Das iPhone filmt in HEVC, oft in HDR. Chrome unter Linux,
/// Firefox und manches Chromium spielen das nicht ab – das Video bleibt
/// schwarz oder meldet einen Fehler. Die Fassung hier spielt überall:
/// H.264 und AAC in MP4, höchstens 1920 Punkte an der langen Seite, HDR
/// auf SDR abgebildet, der Index vorn für sofortiges Abspielen.
///
/// **Erst beim ersten Abruf und im Hintergrund.** Eine Umwandlung dauert
/// bei langen Videos länger, als ein Proxy auf eine Antwort wartet.
/// Deshalb sagt [bereit] sofort, ob die Fassung schon da ist, und stösst
/// sie sonst an; der Browser fragt nach, bis sie fertig ist. Es wird
/// immer nur eine Datei auf einmal umgewandelt – der Server hat noch
/// anderes zu tun.
///
/// Die Fassungen liegen neben der Bibliothek, nicht in ihr: Die Sicherung
/// nimmt nur, was in der Datenbank steht, und ein Zwischenspeicher gehört
/// nicht aufs NAS.
class Videofassungen {
  Videofassungen({this.ffmpeg = 'ffmpeg', this.ffprobe = 'ffprobe'});

  final String ffmpeg;
  final String ffprobe;

  final _laufend = <String, Future<File?>>{};
  Future<void> _reihe = Future.value();

  /// Wo die Fassung von [id] liegt (oder liegen wird).
  static File ziel(Directory zwischenspeicher, String id) =>
      File(p.join(zwischenspeicher.path, '$id.mp4'));

  /// Die fertige Fassung – oder `null`, dann ist sie angestossen (oder
  /// gescheitert, siehe [gescheitert]).
  Future<File?> bereit(
    Directory zwischenspeicher,
    String id,
    File original,
  ) async {
    final datei = ziel(zwischenspeicher, id);
    if (await _aktuell(datei, original)) return datei;
    if (gescheitert.contains(datei.path)) return null;
    unawaited(erzeuge(zwischenspeicher, id, original));
    return null;
  }

  /// Fassungen, die sich nicht erzeugen liessen – bis zum Neustart nicht
  /// noch einmal versucht.
  final gescheitert = <String>{};

  /// Erzeugt die Fassung (oder wartet auf die schon laufende).
  Future<File?> erzeuge(Directory zwischenspeicher, String id, File original) {
    final datei = ziel(zwischenspeicher, id);
    return _laufend.putIfAbsent(datei.path, () {
      final fertig = Completer<File?>();
      _reihe = _reihe.then((_) async {
        try {
          fertig.complete(await _wandle(datei, original));
        } catch (fehler) {
          // Etwa kein ffmpeg: nicht bei jedem Abruf neu versuchen.
          gescheitert.add(datei.path);
          fertig.complete(null);
        } finally {
          _laufend.remove(datei.path);
        }
      });
      return fertig.future;
    });
  }

  Future<bool> _aktuell(File datei, File original) async =>
      await datei.exists() &&
      !(await datei.lastModified()).isBefore(await original.lastModified());

  Future<File?> _wandle(File datei, File original) async {
    if (await _aktuell(datei, original)) return datei;
    await datei.parent.create(recursive: true);
    final teil = File('${datei.path}.teil');
    final hdr = await _istHdr(original);
    // Erst auf die lange Seite begrenzen, dann – bei HDR – über lineares
    // Licht auf BT.709 abbilden; ohne das wäre ein HLG-Video vom iPhone
    // in 8 Bit blass und flau.
    const groesse =
        "scale='if(gt(iw,ih),min(1920,iw),-2)':'if(gt(iw,ih),-2,min(1920,ih))'";
    final filter = hdr
        ? '$groesse,zscale=t=linear:npl=100,format=gbrpf32le,'
              'zscale=p=bt709,tonemap=hable:desat=0,'
              'zscale=t=bt709:m=bt709:r=tv,format=yuv420p'
        : '$groesse,format=yuv420p';
    final r = await Process.run(ffmpeg, [
      '-nostdin', '-y', '-loglevel', 'error', //
      '-i', original.path,
      '-map', '0:v:0', '-map', '0:a:0?',
      // Ohne Metadaten: Der Ort steckt beim iPhone im Kopf des Videos, und
      // die Fassung geht auch über geteilte Links hinaus.
      '-map_metadata', '-1',
      '-vf', filter,
      '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23',
      '-c:a', 'aac', '-b:a', '128k',
      '-movflags', '+faststart',
      '-f', 'mp4', teil.path,
    ]);
    if (r.exitCode != 0) {
      gescheitert.add(datei.path);
      if (await teil.exists()) await teil.delete();
      return null;
    }
    await teil.rename(datei.path);
    return datei;
  }

  /// Ob das Video in HLG oder PQ vorliegt.
  Future<bool> _istHdr(File original) async {
    try {
      final r = await Process.run(ffprobe, [
        '-v', 'error', '-select_streams', 'v:0', //
        '-show_entries', 'stream=color_transfer', '-of', 'json',
        original.path,
      ]);
      if (r.exitCode != 0) return false;
      final streams = (jsonDecode('${r.stdout}') as Map)['streams'] as List?;
      final transfer = streams == null || streams.isEmpty
          ? null
          : (streams.first as Map)['color_transfer'];
      return transfer == 'arib-std-b67' || transfer == 'smpte2084';
    } catch (_) {
      return false;
    }
  }
}
