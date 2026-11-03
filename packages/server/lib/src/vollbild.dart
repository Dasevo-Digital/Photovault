import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'fassungen_aufraeumen.dart';

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
  Vollbilder({
    this.grenze = 2 * 1024 * 1024 * 1024,
    this.frist = const Duration(minutes: 5),
  });

  final int grenze;

  /// Wie lange eine Wandlung die Reihe aufhalten darf (#263). Hing ein
  /// Werkzeug an einer kaputten Datei, wartete jede weitere Vollansicht
  /// dahinter, bis der Server neu startete. Die Werkzeuge haben eine eigene
  /// Grenze (DesktopImageTools.wandlungsgrenze); diese hier fängt auch, was
  /// davor oder danach hängt. Danach gilt das Foto als gescheitert wie
  /// jedes andere, bis sich die Quelle ändert.
  final Duration frist;

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
      // In einem eigenen Future: Der von [wandle] kann zur Laufzeit ein
      // Future<Uint8List> sein, und dessen timeout nähme kein null an.
      bytes = await Future<Uint8List?>(
        wandle,
      ).timeout(frist, onTimeout: () => null);
    } finally {
      if (bytes == null) _gescheitert[datei.path] = stand;
    }
    if (bytes == null) return null;
    _gescheitert.remove(datei.path);
    await speicher.create(recursive: true);
    final teil = File('${datei.path}.teil');
    await teil.writeAsBytes(bytes, flush: true);
    await teil.rename(datei.path);
    await begrenzeZwischenspeicher(speicher, grenze, behalten: datei);
    return datei;
  }
}
