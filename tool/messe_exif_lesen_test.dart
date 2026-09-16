// ignore_for_file: avoid_print

import 'dart:io';

import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';

/// Vergleicht die beiden Wege, an die EXIF-Daten einer Datei zu kommen:
/// die ganze Datei in den Speicher ziehen (`readExifFromBytes`) gegen den
/// stroemenden Leser (`readExifFromFile`).
///
/// Der Datumsnachtrag geht ueber 8098 Dateien; wenn er dafuer jede
/// vollstaendig liest, zieht er ein Vielfaches der Bibliothek durch den
/// Speicher, um in den ersten Kilobytes nachzusehen.
///
///     PV_LIB=/pfad/zur/library flutter test tool/messe_exif_lesen_test.dart
void main() {
  test('ganze Datei gegen stroemend', () async {
    final libPfad = Platform.environment['PV_LIB'];
    if (libPfad == null) {
      markTestSkipped('PV_LIB noetig');
      return;
    }
    final dateien = <File>[];
    await for (final e in Directory('$libPfad/originals').list(recursive: true)) {
      if (e is! File) continue;
      final endung = e.path.toLowerCase();
      if (endung.endsWith('.jpg') ||
          endung.endsWith('.jpeg') ||
          endung.endsWith('.cr3') ||
          endung.endsWith('.dng') ||
          endung.endsWith('.heic')) {
        dateien.add(e);
      }
    }
    dateien.sort((a, b) => a.path.compareTo(b.path));
    // Jede zehnte, damit die Messung nicht Minuten braucht.
    final probe = [for (var i = 0; i < dateien.length; i += 10) dateien[i]];
    var bytes = 0;
    for (final d in probe) {
      bytes += await d.length();
    }
    print('${probe.length} Dateien, ${(bytes / 1024 / 1024).toStringAsFixed(0)} MB');

    // Erst einmal warmlaufen, damit der Dateisystem-Zwischenspeicher
    // nicht die eine Haelfte bevorzugt.
    for (final d in probe.take(20)) {
      await readExifFromBytes(await d.readAsBytes());
    }

    var trefferGanz = 0;
    final uhrGanz = Stopwatch()..start();
    for (final d in probe) {
      final tags = await readExifFromBytes(await d.readAsBytes());
      if (tags['EXIF DateTimeOriginal'] != null) trefferGanz++;
    }
    uhrGanz.stop();

    var trefferStrom = 0;
    final uhrStrom = Stopwatch()..start();
    for (final d in probe) {
      final tags = await readExifFromFile(d);
      if (tags['EXIF DateTimeOriginal'] != null) trefferStrom++;
    }
    uhrStrom.stop();

    print('ganze Datei  ${uhrGanz.elapsedMilliseconds} ms  '
        '$trefferGanz Aufnahmedaten');
    print('stroemend    ${uhrStrom.elapsedMilliseconds} ms  '
        '$trefferStrom Aufnahmedaten');

    // Die Zahl der gefundenen Daten MUSS gleich sein - ein schnellerer
    // Weg, der weniger findet, ist kein schnellerer Weg.
    expect(trefferStrom, trefferGanz,
        reason: 'beide Wege muessen dasselbe finden');
  }, timeout: const Timeout(Duration(minutes: 30)));
}
