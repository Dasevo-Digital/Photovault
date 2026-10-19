import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:image/image.dart' as img;
import 'package:kern/protokoll.dart';
import 'package:kern/services/dateikennung.dart';
import 'package:kern/services/exif_gps.dart';
import 'package:kern/services/isobmff.dart';
import 'package:kern/services/video_metadaten.dart';
import 'package:path/path.dart' as p;

/// Fremde Dateien, die Gäste über einen Link hochladen (Issue #106), laufen
/// in einem eigenen Prozess ohne Netz durch die Decoder – und kommen
/// neu geschrieben heraus.
///
/// **Warum ein eigener Prozess.** Decoder sind die Stelle, an der eine
/// manipulierte Datei Schaden anrichtet: libheif und ffmpeg sind C, und
/// auch ein Dart-Decoder kann sich an einem Bild mit 50.000 × 50.000
/// Punkten verschlucken. Der Server selbst bekommt die Bytes eines Gastes
/// deshalb nie in einen Decoder; der Prüfprozess hat kein Netz, keine
/// Umgebung des Servers (keine Schlüssel, keine Tokens) und eine Frist.
///
/// **Warum neu geschrieben.** In die Bibliothek kommt nicht die Datei des
/// Gastes, sondern was der Prüfprozess daraus gemacht hat: ein JPEG aus
/// den dekodierten Bildpunkten, ein H.264-Video aus den dekodierten
/// Bildern. Mit hinüber gehen nur Aufnahmezeit, Ort und Kamera – nicht
/// Maker-Notes, Vorschaubilder oder was sonst in einer Datei stecken
/// kann. Würde nur geprüft und dann das Original übernommen, liefe es
/// beim Import doch durch dieselben Decoder, nur ohne Schutz.

/// Wie gross ein Bild höchstens sein darf: 120 Megapixel – mehr hat keine
/// Kamera, die Gäste dabeihaben.
const _hoechstensBildpunkte = 120 * 1000 * 1000;

/// Wie lang ein Video höchstens sein darf.
const _hoechstensSekunden = 60 * 60;

/// Was die Prüfung ablehnt, mit einem Grund für den Besitzer.
class _Abgewiesen implements Exception {
  _Abgewiesen(this.grund);
  final String grund;
}

/// Der Prüfprozess selbst: `gast-pruefen <datei> <ziel>`. Schreibt nach
/// `<ziel>` die saubere Datei (`sauber.jpg` oder `sauber.mp4`), eine
/// Vorschau (`vorschau.jpg`) und den Befund (`befund.json`).
///
/// Rückgabe: 0 = geprüft, 2 = abgewiesen (Grund im Befund), sonst Fehler.
Future<int> gastPruefen(List<String> argumente) async {
  if (argumente.length != 2) {
    stderr.writeln('Aufruf: gast-pruefen <datei> <zielordner>');
    return 64;
  }
  final ein = File(argumente[0]);
  final ziel = Directory(argumente[1]);
  final befund = File(p.join(ziel.path, 'befund.json'));
  try {
    final kopf = await _kopf(ein);
    final art = _art(kopf);
    final ergebnis = switch (art) {
      'video' => await _video(ein, ziel),
      null => throw _Abgewiesen('Dateiformat nicht unterstützt'),
      _ => await _bild(ein, ziel, art),
    };
    await befund.writeAsString(jsonEncode(ergebnis));
    return 0;
  } on _Abgewiesen catch (a) {
    await befund.writeAsString(jsonEncode({'grund': a.grund}));
    return 2;
  }
}

Future<Uint8List> _kopf(File datei) async {
  final r = await datei.open();
  try {
    return await r.read(64);
  } finally {
    await r.close();
  }
}

/// Bildformat (`.jpg`, `.png`, …), `video` oder `null` – nach den Bytes,
/// nie nach dem Namen.
String? _art(Uint8List kopf) {
  final bild = kennungAus(kopf);
  if (const {
    '.jpg',
    '.png',
    '.gif',
    '.webp',
    '.heic',
    '.avif',
  }.contains(bild)) {
    return bild;
  }
  if (bild != null) return null;
  String text(int ab, int n) => kopf.length < ab + n
      ? ''
      : String.fromCharCodes(kopf.sublist(ab, ab + n));
  // ISO-BMFF ohne Bildmarke ist ein Film (MP4, MOV, 3GP); ältere
  // QuickTime-Dateien beginnen ohne ftyp gleich mit ihren Kästen.
  if (const {'ftyp', 'moov', 'mdat', 'wide', 'free'}.contains(text(4, 4))) {
    return 'video';
  }
  // Matroska und WebM.
  if (kopf.length >= 4 &&
      kopf[0] == 0x1A &&
      kopf[1] == 0x45 &&
      kopf[2] == 0xDF &&
      kopf[3] == 0xA3) {
    return 'video';
  }
  return null;
}

// --- Bilder -----------------------------------------------------------------

Future<Map<String, Object?>> _bild(File ein, Directory ziel, String art) async {
  final roh = await ein.readAsBytes();
  // Erst die Metadaten aus den Bytes des Gastes – package:exif liest
  // JPEG und HEIC, und nur, was unten ausdrücklich genannt ist, kommt mit.
  Map<String, IfdTag> tags = const {};
  try {
    tags = await readExifFromBytes(roh);
  } catch (_) {
    // Ohne Metadaten weiter.
  }

  img.Image bild;
  if (art == '.heic' || art == '.avif') {
    bild = await _ueberLibheif(ein, ziel);
  } else {
    final decoder = img.findDecoderForData(roh);
    final info = decoder?.startDecode(roh);
    if (decoder == null || info == null) {
      throw _Abgewiesen('Bild nicht lesbar');
    }
    if (info.width * info.height > _hoechstensBildpunkte) {
      throw _Abgewiesen('Bild zu gross');
    }
    final b = decoder.decode(roh, frame: 0);
    if (b == null) throw _Abgewiesen('Bild nicht lesbar');
    // Die Lage einrechnen: Das neue JPEG trägt keine mehr.
    bild = img.bakeOrientation(b);
  }
  final icc = bild.iccProfile;
  final sauber = img.Image.from(bild)
    ..exif = _metadaten(tags)
    ..iccProfile = _iccErlaubt(icc) ? icc : null;
  await File(
    p.join(ziel.path, 'sauber.jpg'),
  ).writeAsBytes(img.encodeJpg(sauber, quality: 92), flush: true);
  await _vorschau(bild, ziel);

  final ort = parseExifGps(tags);
  return {
    'art': 'bild',
    'endung': '.jpg',
    'breite': bild.width,
    'hoehe': bild.height,
    'aufgenommen':
        ?(_text(tags, 'EXIF DateTimeOriginal') ??
        _text(tags, 'Image DateTime')),
    if (ort != null) 'ort': {'breite': ort.latitude, 'laenge': ort.longitude},
    'kamera': ?_kamera(tags),
  };
}

/// HEIC und AVIF über libheif – im selben, abgeschotteten Prozessbaum.
Future<img.Image> _ueberLibheif(File ein, Directory ziel) async {
  final png = File(p.join(ziel.path, 'zwischen.png'));
  ProcessResult? r;
  for (final werkzeug in const ['heif-dec', 'heif-convert']) {
    try {
      r = await Process.run(werkzeug, [ein.path, png.path]);
      break;
    } on ProcessException {
      continue;
    }
  }
  if (r == null) throw _Abgewiesen('HEIC lässt sich hier nicht lesen');
  if (r.exitCode != 0 || !await png.exists()) {
    throw _Abgewiesen('Bild nicht lesbar');
  }
  try {
    final bytes = await png.readAsBytes();
    final decoder = img.PngDecoder();
    final info = decoder.startDecode(bytes);
    if (info == null) throw _Abgewiesen('Bild nicht lesbar');
    if (info.width * info.height > _hoechstensBildpunkte) {
      throw _Abgewiesen('Bild zu gross');
    }
    final b = decoder.decode(bytes, frame: 0);
    if (b == null) throw _Abgewiesen('Bild nicht lesbar');
    // libheif hat Drehung und Spiegelung des Containers schon
    // angewandt; die EXIF-Lage darf nicht noch einmal wirken.
    return b;
  } finally {
    await png.delete();
  }
}

String? _text(Map<String, IfdTag> tags, String name) {
  final t = tags[name]?.printable.trim();
  return t == null || t.isEmpty ? null : t;
}

String? _kamera(Map<String, IfdTag> tags) {
  final teile = [?_text(tags, 'Image Make'), ?_text(tags, 'Image Model')];
  return teile.isEmpty ? null : teile.join(' ');
}

/// Das EXIF des neuen JPEG: Aufnahmezeit, Zeitzone, Ort und Kamera –
/// sonst nichts.
img.ExifData _metadaten(Map<String, IfdTag> tags) {
  final exif = img.ExifData();
  final ascii = <(String, String, img.IfdDirectory)>[
    ('Image Make', 'Make', exif.imageIfd),
    ('Image Model', 'Model', exif.imageIfd),
    ('EXIF DateTimeOriginal', 'DateTimeOriginal', exif.exifIfd),
    ('EXIF DateTimeDigitized', 'DateTimeDigitized', exif.exifIfd),
    ('EXIF OffsetTimeOriginal', 'OffsetTimeOriginal', exif.exifIfd),
    ('EXIF SubSecTimeOriginal', 'SubSecTimeOriginal', exif.exifIfd),
  ];
  for (final (von, nach, ifd) in ascii) {
    final w = _text(tags, von);
    // Kurz und lesbar – ein ASCII-Feld mit Megabytes ist kein Datum.
    if (w != null && w.length <= 64) ifd[nach] = w;
  }
  final ort = parseExifGps(tags);
  if (ort != null) {
    img.IfdValueRational grad(double wert) {
      final a = wert.abs();
      final g = a.floor();
      final m = ((a - g) * 60).floor();
      final s = ((a - g) * 60 - m) * 60;
      // Grad, Minuten, Sekunden – package:image gibt den Bruch selbst
      // nicht heraus, nur Werte, die ihn tragen.
      return img.IfdValueRational(g, 1)
        ..value.addAll(img.IfdValueRational(m, 1).value)
        ..value.addAll(img.IfdValueRational((s * 10000).round(), 10000).value);
    }

    final gps = exif.gpsIfd;
    gps[1] = img.IfdValueAscii(ort.latitude < 0 ? 'S' : 'N');
    gps[2] = grad(ort.latitude);
    gps[3] = img.IfdValueAscii(ort.longitude < 0 ? 'W' : 'E');
    gps[4] = grad(ort.longitude);
  }
  return exif;
}

/// Ein Farbprofil kommt nur mit, wenn es klein und ein gewöhnliches
/// RGB-Profil ist (etwa Display P3 vom iPhone) – sonst sähen die Farben
/// eines iPhone-Fotos blasser aus. Alles andere bleibt draussen.
bool _iccErlaubt(img.IccProfile? icc) {
  if (icc == null) return false;
  final d = icc.decompressed();
  if (d.length < 132 || d.length > 8 * 1024) return false;
  String text(int ab) => String.fromCharCodes(d.sublist(ab, ab + 4));
  return text(36) == 'acsp' && text(16) == 'RGB ' && text(20) == 'XYZ ';
}

Future<void> _vorschau(img.Image bild, Directory ziel) async {
  final klein = bild.width >= bild.height
      ? img.copyResize(bild, width: bild.width > 512 ? 512 : bild.width)
      : img.copyResize(bild, height: bild.height > 512 ? 512 : bild.height);
  await File(
    p.join(ziel.path, 'vorschau.jpg'),
  ).writeAsBytes(img.encodeJpg(klein..exif = img.ExifData(), quality: 80));
}

// --- Videos -----------------------------------------------------------------

Future<Map<String, Object?>> _video(File ein, Directory ziel) async {
  final probe = await _ffprobe(ein);
  final strom = probe.$1;
  if (strom == null) throw _Abgewiesen('Video nicht lesbar');
  if ((probe.$2 ?? 0) > _hoechstensSekunden) {
    throw _Abgewiesen('Video länger als eine Stunde');
  }
  final transfer = strom['color_transfer'];
  final hdr = transfer == 'arib-std-b67' || transfer == 'smpte2084';
  // Wie die Fassung zum Abspielen (videofassung.dart), aber in voller
  // Grösse bis 4K und mit Zeit und Ort – das hier wird die Aufnahme.
  const groesse =
      "scale='if(gt(iw,ih),min(3840,iw),-2)':'if(gt(iw,ih),-2,min(3840,ih))'";
  final filter = hdr
      ? '$groesse,zscale=t=linear:npl=100,format=gbrpf32le,'
            'zscale=p=bt709,tonemap=hable:desat=0,'
            'zscale=t=bt709:m=bt709:r=tv,format=yuv420p'
      : '$groesse,format=yuv420p';
  final sauber = File(p.join(ziel.path, 'sauber.mp4'));
  // Zeit, Ort und Kamera liest der Dart-Leser des Kerns, und nur sie
  // werden ausdrücklich in das neue Video geschrieben – wie beim Foto.
  // (`-map_metadata 0` nähme alles mit und legte obendrein zwei
  // Zeitangaben zu einer zusammen, die keiner mehr lesen kann.)
  final meta = await leseVideoMetadaten(ein);
  final moov = await kastenAusDatei(ein, 'moov');
  final mitZone = moov == null
      ? null
      : appleSchluesselwert(moov, 'com.apple.quicktime.creationdate');
  final ort = meta.ort;
  String zahl(double w, int stellen) =>
      '${w < 0 ? '-' : '+'}${w.abs().toStringAsFixed(4).padLeft(stellen + 5, '0')}';
  final iso6709 = ort == null
      ? null
      : '${zahl(ort.breite, 2)}${zahl(ort.laenge, 3)}/';
  String? kurz(String? t) => t == null || t.length > 64 ? null : t;
  final angaben = <String, String>{
    if (meta.zeit case final z?)
      'creation_time': z.herkunft == Zeitherkunft.mitZone
          ? z.zeitpunkt.toUtc().toIso8601String()
          // Ohne Zone liest der Kern die Uhrzeit vor Ort – so kommt sie
          // auch wieder hinein, sonst verschöbe sie sich um die Zone.
          : '${_wanduhr(z.zeitpunkt)}Z',
    if (mitZone != null &&
        RegExp(
          r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d([+-]\d{4}|Z)$',
        ).hasMatch(mitZone))
      'com.apple.quicktime.creationdate': mitZone,
    if (iso6709 != null) ...{
      'location': iso6709,
      'com.apple.quicktime.location.ISO6709': iso6709,
    },
    'com.apple.quicktime.make': ?kurz(meta.hersteller),
    'com.apple.quicktime.model': ?kurz(meta.geraet),
  };
  final r = await Process.run('ffmpeg', [
    '-nostdin', '-y', '-loglevel', 'error', //
    '-i', ein.path,
    '-map', '0:v:0', '-map', '0:a:0?',
    '-map_metadata', '-1',
    for (final e in angaben.entries) ...['-metadata', '${e.key}=${e.value}'],
    '-vf', filter,
    '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20',
    '-c:a', 'aac', '-b:a', '160k',
    '-movflags', '+faststart+use_metadata_tags',
    '-f', 'mp4', sauber.path,
  ]);
  if (r.exitCode != 0 || !await sauber.exists()) {
    throw _Abgewiesen('Video nicht lesbar');
  }
  // Ab hier nur noch die eigene Datei.
  final neu = await _ffprobe(sauber);
  final dauer = neu.$2 ?? probe.$2;
  final v = await Process.run('ffmpeg', [
    '-nostdin', '-y', '-loglevel', 'error', //
    '-ss', (dauer != null && dauer > 1) ? '0.5' : '0',
    '-i', sauber.path,
    '-frames:v', '1',
    '-vf',
    "scale='if(gt(iw,ih),min(512,iw),-2)':'if(gt(iw,ih),-2,min(512,ih))'",
    '-map_metadata', '-1',
    p.join(ziel.path, 'vorschau.jpg'),
  ]);
  if (v.exitCode != 0) protokoll('Gastvideo: keine Vorschau – ${v.stderr}');
  return {
    'art': 'video',
    'endung': '.mp4',
    if (neu.$1?['width'] case final int b) 'breite': b,
    if (neu.$1?['height'] case final int h) 'hoehe': h,
    'dauer': ?dauer,
    'aufgenommen': ?meta.zeit?.zeitpunkt.toIso8601String(),
    if (ort != null) 'ort': {'breite': ort.breite, 'laenge': ort.laenge},
    if ([?meta.hersteller, ?meta.geraet] case final k when k.isNotEmpty)
      'kamera': k.join(' '),
  };
}

String _wanduhr(DateTime t) {
  String z(int n, [int stellen = 2]) => n.toString().padLeft(stellen, '0');
  return '${z(t.year, 4)}-${z(t.month)}-${z(t.day)}'
      'T${z(t.hour)}:${z(t.minute)}:${z(t.second)}';
}

/// Der erste Videostrom und die Dauer.
Future<(Map<String, Object?>?, double?)> _ffprobe(File datei) async {
  try {
    final r = await Process.run('ffprobe', [
      '-v', 'error', '-select_streams', 'v:0', //
      '-show_entries', 'stream=width,height,color_transfer:format=duration',
      '-of', 'json', datei.path,
    ]);
    if (r.exitCode != 0) return (null, null);
    final j = jsonDecode('${r.stdout}') as Map;
    final stroeme = j['streams'] as List?;
    final dauer = double.tryParse('${(j['format'] as Map?)?['duration']}');
    return (
      stroeme == null || stroeme.isEmpty
          ? null
          : (stroeme.first as Map).cast<String, Object?>(),
      dauer,
    );
  } catch (_) {
    return (null, null);
  }
}

// --- Im Server ----------------------------------------------------------------

/// Wie der Prüfprozess abgeschottet wird – das Beste, was das System
/// hergibt.
class Abschottung {
  const Abschottung(this.vorsatz, {required this.ohneNetz});

  /// Was vor den Aufruf gesetzt wird.
  final List<String> vorsatz;

  /// Ob der Prozess wirklich kein Netz hat.
  final bool ohneNetz;

  static const _mac = '(version 1)(allow default)(deny network*)';

  /// Linux: ein eigener Netz-Namensraum (`unshare -rn`), in dem es nur
  /// ein abgeschaltetes Loopback gibt. macOS: `sandbox-exec` mit einem
  /// Profil, das jedes Netz verbietet. Geht beides nicht – etwa in einem
  /// Container ohne Benutzer-Namensräume –, bleibt der eigene Prozess
  /// ohne die Umgebung des Servers; das meldet der Server beim Start.
  static Future<Abschottung> erkenne() async {
    Future<bool> geht(String befehl, List<String> argumente) async {
      try {
        return (await Process.run(befehl, argumente)).exitCode == 0;
      } catch (_) {
        return false;
      }
    }

    if (Platform.isLinux && await geht('unshare', ['-rn', 'true'])) {
      return const Abschottung(['unshare', '-rn', '--'], ohneNetz: true);
    }
    if (Platform.isMacOS &&
        await geht('/usr/bin/sandbox-exec', ['-p', _mac, '/usr/bin/true'])) {
      return const Abschottung([
        '/usr/bin/sandbox-exec',
        '-p',
        _mac,
      ], ohneNetz: true);
    }
    return const Abschottung([], ohneNetz: false);
  }
}

/// Was der Prüfprozess über eine Datei sagt.
typedef Pruefergebnis = ({bool ok, Map<String, Object?> befund});

/// Startet den Prüfprozess, einen nach dem anderen.
class Gastpruefung {
  Gastpruefung({
    List<String>? aufruf,
    Future<Abschottung>? abschottung,
    this.fristBild = const Duration(minutes: 3),
    this.fristVideo = const Duration(minutes: 60),
  }) : aufruf = aufruf ?? eigenerAufruf(),
       abschottung = abschottung ?? Abschottung.erkenne();

  /// Wie der Server sich selbst aufruft (siehe [eigenerAufruf]).
  final List<String> aufruf;
  final Future<Abschottung> abschottung;
  final Duration fristBild;
  final Duration fristVideo;

  Future<void> _vorige = Future<void>.value();

  /// Der Server als Programm: das übersetzte Programm selbst, unter
  /// `dart run` die VM mit dem Skript.
  static List<String> eigenerAufruf() {
    final skript = Platform.script;
    return [
      Platform.resolvedExecutable,
      if (skript.scheme == 'file' && skript.path.endsWith('.dart'))
        skript.toFilePath(),
    ];
  }

  /// Prüft [ein] und legt das Ergebnis in [ziel] ab.
  Future<Pruefergebnis> pruefe(File ein, Directory ziel, {bool video = false}) {
    final lauf = _vorige.then((_) => _pruefe(ein, ziel, video));
    _vorige = lauf.then((_) {}, onError: (_) {});
    return lauf;
  }

  Future<Pruefergebnis> _pruefe(File ein, Directory ziel, bool video) async {
    final a = await abschottung;
    await ziel.create(recursive: true);
    final befehl = [
      ...a.vorsatz,
      ...aufruf,
      'gast-pruefen',
      ein.path,
      ziel.path,
    ];
    final Process prozess;
    try {
      prozess = await Process.start(
        befehl.first,
        befehl.sublist(1),
        workingDirectory: ziel.path,
        // Nichts vom Server: keine Schlüssel, keine Tokens, keine Pfade.
        includeParentEnvironment: false,
        environment: {
          'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
          'LANG': 'C.UTF-8',
          'HOME': ziel.path,
        },
      );
    } on ProcessException catch (e) {
      protokoll('Gastprüfung liess sich nicht starten: $e');
      return (ok: false, befund: {'grund': 'Prüfung nicht möglich'});
    }
    final fehler = StringBuffer();
    prozess.stderr.transform(utf8.decoder).listen(fehler.write);
    prozess.stdout.drain<void>();
    final frist = video ? fristVideo : fristBild;
    final code = await prozess.exitCode.timeout(
      frist,
      onTimeout: () {
        prozess.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    if (code == -1) {
      return (ok: false, befund: {'grund': 'Prüfung dauerte zu lange'});
    }
    Map<String, Object?> befund = const {};
    try {
      final j = jsonDecode(
        await File(p.join(ziel.path, 'befund.json')).readAsString(),
      );
      if (j is Map) befund = j.cast<String, Object?>();
    } catch (_) {
      // Unten als Fehler gemeldet.
    }
    if (code == 0 && befund['art'] != null) return (ok: true, befund: befund);
    if (code != 2 && fehler.isNotEmpty) {
      protokoll('Gastprüfung mit $code beendet: ${fehler.toString().trim()}');
    }
    return (
      ok: false,
      befund: {'grund': befund['grund'] ?? 'Datei nicht lesbar'},
    );
  }
}
