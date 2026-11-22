import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:kern/db/database.dart';

import 'fassungen_aufraeumen.dart';

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
/// nicht aufs NAS. Zusammen höchstens [grenze] Bytes, die ältesten gehen
/// zuerst – bis 3.52 wuchs der Ordner ohne Ende (#261).
class Videofassungen {
  Videofassungen({
    this.ffmpeg = 'ffmpeg',
    this.ffprobe = 'ffprobe',
    this.grenze = 10 * 1024 * 1024 * 1024,
  });

  final String ffmpeg;
  final String ffprobe;
  final int grenze;

  final _laufend = <String, Future<File?>>{};
  Future<void> _reihe = Future.value();

  /// Der Stand der Umwandlung, im Namen jeder Fassung (#395). Steigt er,
  /// passt der Name einer älteren Fassung nicht mehr: Sie entsteht neu,
  /// und das Aufräumen nimmt die alte mit. Ohne ihn galt eine Fassung als
  /// aktuell, solange das Original nicht neuer war – auch eine ohne die
  /// Obergrenze von 8 Mbit/s, die über eine langsame Leitung so schlecht
  /// anlief wie das Original.
  ///
  /// 2: höchstens 8 Mbit/s (3.67.4, #393).
  static const stand = 2;

  /// Wo die Fassung von [id] liegt (oder liegen wird).
  static File ziel(Directory zwischenspeicher, String id) =>
      File(p.join(zwischenspeicher.path, '$id.s$stand.mp4'));

  /// Die fertige Fassung – oder `null`, dann ist sie angestossen (oder
  /// gescheitert, siehe [gescheitert]).
  ///
  /// [gast]: Der Abruf kommt über einen geteilten Link. Solche Abrufe
  /// stossen höchstens [hoechstensFuerGaeste] Umwandlungen zugleich an;
  /// darüber bleibt es bei `null`, und der Besucher fragt später wieder.
  /// Die Reihe gehört allen Konten: Ein Besucher, der jedes Video eines
  /// grossen Albums abrief, stellte vorher Stunden an Umwandlungen vor die
  /// Videos, die die Besitzer selbst gerade ansehen wollten.
  Future<File?> bereit(
    Directory zwischenspeicher,
    String id,
    File original, {
    bool gast = false,
  }) async {
    final datei = ziel(zwischenspeicher, id);
    if (await _aktuell(datei, original)) return datei;
    if (gescheitert.contains(datei.path)) return null;
    if (gast && !_laufend.containsKey(datei.path)) {
      if (_fuerGaeste.length >= hoechstensFuerGaeste) return null;
      _fuerGaeste.add(datei.path);
      unawaited(
        erzeuge(
          zwischenspeicher,
          id,
          original,
        ).whenComplete(() => _fuerGaeste.remove(datei.path)),
      );
      return null;
    }
    unawaited(erzeuge(zwischenspeicher, id, original));
    return null;
  }

  /// Wie viele Umwandlungen Abrufe über geteilte Links höchstens zugleich
  /// in der Reihe haben (siehe [bereit]).
  static const hoechstensFuerGaeste = 2;
  final _fuerGaeste = <String>{};

  /// Fassungen, die sich nicht erzeugen liessen – bis zum Neustart nicht
  /// noch einmal versucht.
  final gescheitert = <String>{};

  /// Ab welcher Datenrate ein Original als schwer gilt – wie in der
  /// Handy-App: Ein iPhone filmt 4K mit HDR und rund 50 Mbit/s, mehr, als
  /// der Upload daheim oder ein Mobilnetz verlässlich liefert (#393).
  static const schwerAbBitProSekunde = 20 * 1000 * 1000;

  /// Wie alt eine Aufnahme höchstens ist, damit sie schon nach dem Import
  /// eine Fassung bekommt ([vormerken]). Angesehen wird vor allem, was
  /// gerade aufgenommen wurde; ein Archiv alter Videos verdrängte sonst
  /// die Fassungen, die schon jemand abgespielt hat.
  static const vorratFrisch = Duration(days: 30);

  /// Ob [a] schon nach dem Import eine Fassung bekommen soll (#394): ein
  /// frisches, schweres Video, nicht gesperrt und nicht im Papierkorb.
  static bool lohntVorrat(AssetData a, {required DateTime jetzt}) {
    final dauer = a.durationSeconds;
    if (a.type != 'VIDEO' || a.isLocked || a.isTrashed) return false;
    if (dauer == null || dauer <= 0 || a.fileSizeBytes <= 0) return false;
    if (jetzt.difference(a.fileCreatedAt) > vorratFrisch) return false;
    return a.fileSizeBytes * 8 / dauer > schwerAbBitProSekunde;
  }

  /// Was schon vor dem ersten Abruf entstehen soll, in der Reihenfolge des
  /// Vormerkens.
  final _vorrat = <String, (Directory, String, File)>{};
  Future<void>? _vorratLauf;

  /// Bis der Vorrat abgearbeitet ist – für Tests.
  Future<void> get vorratAbgearbeitet => _vorratLauf ?? Future.value();

  /// Höchstens so viele Fassungen warten im Vorrat.
  static const vorratGrenze = 20;

  /// Merkt die Fassung von [id] vor, damit sie schon vor dem ersten Abruf
  /// entsteht (#394). Bis 3.67.5 entstand sie erst, wenn jemand das Video
  /// öffnete, und Handy und Browser warteten beim ersten Mal minutenlang
  /// auf die Umwandlung – auch ein kurzes Vorbeiwischen im Betrachter
  /// stiess sie an.
  ///
  /// Angefragte Fassungen gehen vor: Der Vorrat wartet, bis keine mehr
  /// ansteht, und wandelt dann eine nach der anderen. Er belegt höchstens
  /// die Hälfte von [grenze]; was schon jemand abgespielt hat, verdrängt
  /// er nicht.
  void vormerken(Directory zwischenspeicher, String id, File original) {
    final datei = ziel(zwischenspeicher, id);
    if (gescheitert.contains(datei.path) ||
        _laufend.containsKey(datei.path) ||
        _vorrat.length >= vorratGrenze) {
      return;
    }
    _vorrat[datei.path] = (zwischenspeicher, id, original);
    _vorratLauf ??= _arbeiteVorrat();
  }

  /// Läuft, bis der Vorrat leer ist. Das `finally` folgt dem letzten
  /// Durchgang ohne Pause; was danach vorgemerkt wird, startet neu.
  Future<void> _arbeiteVorrat() async {
    try {
      while (_vorrat.isNotEmpty) {
        while (_laufend.isNotEmpty) {
          await Future.wait(_laufend.values.toList());
        }
        final schluessel = _vorrat.keys.first;
        final (speicher, id, original) = _vorrat.remove(schluessel)!;
        try {
          if (await _aktuell(ziel(speicher, id), original)) continue;
          if (await _belegt(speicher) > grenze ~/ 2) continue;
          await erzeuge(speicher, id, original);
        } catch (_) {
          // Etwa das Original inzwischen gelöscht: dann eben beim Abruf.
        }
      }
    } finally {
      _vorratLauf = null;
    }
  }

  static Future<int> _belegt(Directory speicher) async {
    if (!await speicher.exists()) return 0;
    var summe = 0;
    await for (final e in speicher.list(followLinks: false)) {
      if (e is File) {
        try {
          summe += await e.length();
        } on FileSystemException {
          // Zwischen Auflisten und Messen gelöscht.
        }
      }
    }
    return summe;
  }

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
      // Höchstens 8 Mbit/s: Die Fassung muss auch über den Upload daheim
      // oder ein Mobilnetz anlaufen. Ohne Grenze kam ein 4K-Video vom
      // iPhone mit Laub und Wasser auf 24 Mbit/s (#393).
      '-maxrate', '8M', '-bufsize', '16M',
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
    await begrenzeZwischenspeicher(datei.parent, grenze, behalten: datei);
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
