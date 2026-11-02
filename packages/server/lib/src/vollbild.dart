import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Fotos in voller Auflösung für Browser und Handy, die HEIC, DNG oder CR3
/// nicht selbst lesen (#256).
///
/// **Warum.** Der Betrachter zeigte von solchen Fotos nur die Vorschau mit
/// 2048 Punkten an der langen Seite; beim Zoomen auf dem Handy war das
/// unscharf. Ein iPhone fotografiert in HEIC, also traf es fast jedes Foto.
///
/// **Einmal gewandelt, begrenzt aufgehoben.** Ein Foto mit 48 Megapixeln zu
/// wandeln dauert Sekunden, und wer hin- und herblättert, fragt dasselbe
/// mehrmals. Die Fassungen liegen neben der Bibliothek wie die
/// Videofassungen, zusammen höchstens [grenze] Bytes; die ältesten gehen
/// zuerst. Immer nur eine Wandlung auf einmal – der Server hat noch
/// anderes zu tun.
///
/// **Ohne Angaben.** Der Wandler streift EXIF ab, also auch den Ort: Die
/// Fassung ist nur zum Ansehen.
class Vollbilder {
  Vollbilder({this.grenze = 2 * 1024 * 1024 * 1024});

  final int grenze;

  final _laufend = <String, Future<File?>>{};
  Future<void> _reihe = Future.value();

  /// Was sich nicht wandeln liess: Fassung und Stand der Quelle damals.
  /// Ohne das rechnete jeder Aufruf dieselbe vergebliche Wandlung neu
  /// (#265); ändert sich die Quelle, wird es wieder versucht.
  final _gescheitert = <String, DateTime>{};

  /// Wo die Fassung von [id] aus [quelle] liegt (oder liegen wird). Der
  /// Pfad der Quelle steckt im Namen: Wird ein Foto später restauriert,
  /// gilt die alte Fassung nicht mehr.
  static File ziel(Directory speicher, String id, String quelle) => File(
    p.join(
      speicher.path,
      '$id-${sha1.convert(utf8.encode(quelle)).toString().substring(0, 12)}.jpg',
    ),
  );

  /// Die fertige Fassung – erzeugt, wenn sie fehlt oder älter ist als
  /// [quelle]. `null`, wenn [wandle] nichts liefert.
  Future<File?> bereit(
    Directory speicher,
    String id,
    File quelle,
    Future<Uint8List?> Function() wandle,
  ) async {
    final datei = ziel(speicher, id, quelle.path);
    if (await _aktuell(datei, quelle)) return datei;
    final damals = _gescheitert[datei.path];
    if (damals != null && damals == await quelle.lastModified()) return null;
    return _laufend.putIfAbsent(datei.path, () {
      final fertig = Completer<File?>();
      _reihe = _reihe.then((_) async {
        try {
          fertig.complete(await _erzeuge(speicher, datei, quelle, wandle));
        } catch (_) {
          fertig.complete(null);
        } finally {
          _laufend.remove(datei.path);
        }
      });
      return fertig.future;
    });
  }

  Future<bool> _aktuell(File datei, File quelle) async =>
      await datei.exists() &&
      !(await datei.lastModified()).isBefore(await quelle.lastModified());

  Future<File?> _erzeuge(
    Directory speicher,
    File datei,
    File quelle,
    Future<Uint8List?> Function() wandle,
  ) async {
    // Wer hinter einer anderen Anfrage gewartet hat, findet sie fertig.
    if (await _aktuell(datei, quelle)) return datei;
    final stand = await quelle.lastModified();
    Uint8List? bytes;
    try {
      bytes = await wandle();
    } finally {
      if (bytes == null) _gescheitert[datei.path] = stand;
    }
    if (bytes == null) return null;
    _gescheitert.remove(datei.path);
    await speicher.create(recursive: true);
    final teil = File('${datei.path}.teil');
    await teil.writeAsBytes(bytes, flush: true);
    await teil.rename(datei.path);
    await _begrenze(speicher, datei);
    return datei;
  }

  /// Hält [speicher] unter [grenze]: die ältesten zuerst, bis vier Fünftel
  /// frei sind, damit nicht jede nächste Wandlung wieder aufräumt. Die
  /// Zeit wird beim Ausliefern nicht aufgefrischt – sie steckt im ETag,
  /// und der Browser soll seine Kopie behalten dürfen.
  Future<void> _begrenze(Directory speicher, File behalten) async {
    final dateien = <(File, int, DateTime)>[];
    var summe = 0;
    await for (final e in speicher.list(followLinks: false)) {
      if (e is! File || e.path == behalten.path) continue;
      try {
        final s = await e.stat();
        dateien.add((e, s.size, s.modified));
        summe += s.size;
      } on FileSystemException {
        // Zwischen Auflisten und Messen gelöscht.
      }
    }
    summe += await behalten.length();
    if (summe <= grenze) return;
    dateien.sort((a, b) => a.$3.compareTo(b.$3));
    final ziel = grenze * 4 ~/ 5;
    for (final (f, bytes, _) in dateien) {
      if (summe <= ziel) break;
      try {
        await f.delete();
        summe -= bytes;
      } on FileSystemException {
        // Gerade weg – dann eben beim nächsten Mal.
      }
    }
  }
}
