import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:image/image.dart' as img;
import 'package:kern/protokoll.dart';
import 'package:kern/services/dateikennung.dart';
import 'package:kern/services/exif_gps.dart';
import 'package:kern/services/isobmff.dart';
import 'package:kern/services/video_metadaten.dart';
import 'package:path/path.dart' as p;

part 'gast_abschottung.dart';

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

/// Was der Prüfprozess über eine Datei sagt.
typedef Pruefergebnis = ({bool ok, Map<String, Object?> befund});

/// Startet den Prüfprozess, einen nach dem anderen.
class Gastpruefung {
  Gastpruefung({
    List<String>? aufruf,
    Future<Abschottung>? abschottung,
    this.beimStart,
    this.verbotenePfade = const [],
    this.maxSpeicherBytes = 1536 * 1024 * 1024,
    this.fristBild = const Duration(minutes: 3),
    this.fristVideo = const Duration(minutes: 60),
  }) : aufruf = aufruf ?? eigenerAufruf(),
       abschottung = abschottung ?? Abschottung.erkenne();

  /// Wie der Server sich selbst aufruft (siehe [eigenerAufruf]).
  final List<String> aufruf;
  final void Function(int pid)? beimStart;
  final List<String> verbotenePfade;
  final int maxSpeicherBytes;
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
    if (!a.ohneNetz || aufruf.any((s) => s.endsWith('.dart'))) {
      return (
        ok: false,
        befund: {'grund': 'Isolierte Prüfung nicht verfügbar'},
      );
    }
    final temp = await Directory.systemTemp.createTemp('pv_gast_isoliert_');
    Process? prozess;
    Timer? waechter;
    try {
      if ((await Process.run('chmod', ['700', temp.path])).exitCode != 0) {
        throw const FileSystemException('pv_gast_rechte');
      }
      final wurzel = await temp.resolveSymbolicLinks();
      final quelle = await ein.copy(p.join(wurzel, 'eingang'));
      final aus = Directory(p.join(wurzel, 'aus'));
      await aus.create();
      final command = [for (final f in aufruf) await _programmPfad(f)];
      final vorsatz = await a.fuer(quelle, aus, command, verbotenePfade);
      // Hart begrenzte CPU-Zeit, Dateigröße und offene Dateien werden an
      // alle Decoder-Kinder vererbt; die Wandzeit gilt für den ganzen Baum.
      final frist = video ? fristVideo : fristBild;
      final befehl = [
        ...vorsatz,
        '/bin/sh',
        '-c',
        'set -e; ulimit -t ${frist.inSeconds + 1}; ulimit -f 4194304; ulimit -n 128; exec "\$@"',
        'pruefung',
        ...command,
        'gast-pruefen',
        quelle.path,
        aus.path,
      ];
      prozess = await Process.start(
        befehl.first,
        befehl.sublist(1),
        workingDirectory: aus.path,
        includeParentEnvironment: false,
        environment: {
          'PATH': '/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin',
          'LANG': 'C.UTF-8',
          'HOME': aus.path,
          'TMPDIR': aus.path,
        },
      );
      beimStart?.call(prozess.pid);
      final fehler = BytesBuilder(copy: false);
      final stderrFertig = prozess.stderr.listen((b) {
        if (fehler.length < 16384) {
          fehler.add(b.take(16384 - fehler.length).toList());
        }
      }).asFuture<void>();
      unawaited(prozess.stdout.drain<void>());
      final kind = prozess;
      var beendet = false, prueft = false, ressourcen = false;
      Future<void> begrenze() async {
        if (prueft || beendet) return;
        prueft = true;
        try {
          final baum = await _prozessbaum(kind.pid);
          var dateiBytes = 0;
          await for (final f in aus.list(followLinks: false)) {
            if (f is File) dateiBytes += await f.length();
          }
          if (baum.values.fold<int>(0, (n, r) => n + r) > maxSpeicherBytes ||
              dateiBytes > 2 * 1024 * 1024 * 1024) {
            ressourcen = true;
            await _beendeBaum(kind);
          }
        } catch (_) {
          // Ohne Ressourcenaufsicht wird nicht weiter dekodiert.
          ressourcen = true;
          await _beendeBaum(kind);
        } finally {
          prueft = false;
        }
      }

      waechter = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => unawaited(begrenze()),
      );
      final code = await prozess.exitCode.timeout(
        frist,
        onTimeout: () async {
          await _beendeBaum(kind);
          return -1;
        },
      );
      beendet = true;
      waechter.cancel();
      // Auch ein früh beendeter Elternprozess darf keine Decoder zurücklassen.
      _toeteGruppe(kind.pid);
      await stderrFertig.timeout(const Duration(seconds: 2), onTimeout: () {});
      if (code == -1 || ressourcen) {
        return (
          ok: false,
          befund: {'grund': 'Ressourcen- oder Zeitgrenze erreicht'},
        );
      }
      final manifest = File(p.join(aus.path, 'befund.json'));
      if (await FileSystemEntity.type(manifest.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await manifest.length() > 65536) {
        protokoll(
          'Gastprüfung mit $code beendet: ${utf8.decode(fehler.takeBytes(), allowMalformed: true)}',
        );
        return (ok: false, befund: {'grund': 'Prüfung nicht möglich'});
      }
      final befund = (jsonDecode(await manifest.readAsString()) as Map)
          .cast<String, Object?>();
      if (code != 0 || befund['art'] == null) {
        return (
          ok: false,
          befund: {'grund': befund['grund'] ?? 'Datei nicht lesbar'},
        );
      }
      await ziel.create(recursive: true);
      for (final name in [
        'befund.json',
        'sauber.jpg',
        'sauber.mp4',
        'vorschau.jpg',
      ]) {
        final f = File(p.join(aus.path, name));
        if (await FileSystemEntity.type(f.path, followLinks: false) ==
            FileSystemEntityType.file) {
          await f.copy(p.join(ziel.path, name));
        }
      }
      return (ok: true, befund: befund);
    } on Object {
      if (prozess != null) await _beendeBaum(prozess);
      return (
        ok: false,
        befund: {'grund': 'Isolierte Prüfung nicht verfügbar'},
      );
    } finally {
      waechter?.cancel();
      await temp.delete(recursive: true);
    }
  }
}
