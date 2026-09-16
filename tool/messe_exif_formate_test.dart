// ignore_for_file: avoid_print

import 'dart:io';

import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Bei welchen Formaten liefert `package:exif` ueberhaupt etwas?
///
/// Die Frage entscheidet eine Optimierung: Der Datumsnachtrag zieht jede
/// Bilddatei vollstaendig in den Speicher, um sie `readExifFromBytes`
/// vorzulegen. Bei 909 CR3 mit je rund 31 MB sind das 28 GB fuer ein
/// sicheres Nichts – **wenn** CR3 dort wirklich nichts liefert. Bei
/// TIFF-basierten Formaten wie DNG oder NEF waere derselbe Schluss falsch.
///
///     PV_LIB=/pfad/zur/library flutter test tool/messe_exif_formate_test.dart
void main() {
  test('welche Endungen liefern Tags', () async {
    final libPfad = Platform.environment['PV_LIB'];
    if (libPfad == null) {
      markTestSkipped('PV_LIB noetig');
      return;
    }
    final nachEndung = <String, List<File>>{};
    await for (final e in Directory('$libPfad/originals').list(recursive: true)) {
      if (e is! File) continue;
      nachEndung.putIfAbsent(p.extension(e.path).toLowerCase(), () => []).add(e);
    }

    for (final endung in nachEndung.keys.toList()..sort()) {
      final dateien = nachEndung[endung]!..sort((a, b) => a.path.compareTo(b.path));
      final probe = [
        for (var i = 0; i < dateien.length && i < 8 * 50; i += 50) dateien[i]
      ];
      if (probe.isEmpty) continue;
      var mitTags = 0;
      var mitDatum = 0;
      var bytes = 0;
      final uhr = Stopwatch()..start();
      for (final d in probe) {
        try {
          final roh = await d.readAsBytes();
          bytes += roh.length;
          final tags = await readExifFromBytes(roh);
          if (tags.isNotEmpty) mitTags++;
          if (tags['EXIF DateTimeOriginal'] != null) mitDatum++;
        } catch (_) {
          // zaehlt als „nichts"
        }
      }
      uhr.stop();
      print('${endung.padRight(7)} ${dateien.length.toString().padLeft(5)} Dateien  '
          'Probe ${probe.length.toString().padLeft(2)}: '
          '$mitTags mit Tags, $mitDatum mit Datum, '
          '${(bytes / 1024 / 1024).toStringAsFixed(0).padLeft(4)} MB in '
          '${uhr.elapsedMilliseconds.toString().padLeft(5)} ms');
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}
