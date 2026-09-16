// Prueft die Staubsuche an einer echten Kameraserie:
//
//   dart run tool/messe_staubflecken.dart <liste.txt> [belegbild.png]
//
// <liste.txt> enthaelt eine Bilddatei je Zeile - alle aus DERSELBEN Kamera,
// sonst sagt die Bestaetigung ueber die Serie nichts.
//
// Eine Verteilung sagt hier nichts. Was zaehlt, ist, ob die bestaetigten
// Stellen ueber die Serie hinweg dieselben sind. Deshalb schreibt das
// Werkzeug die Fundstellen als Bild heraus: ansehen statt glauben.
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:photo_vault/services/staubflecken.dart';

void main(List<String> args) {
  final dateien = File(args[0])
      .readAsLinesSync()
      .where((z) => z.trim().isNotEmpty)
      .map(File.new)
      .where((f) => f.existsSync())
      .toList();
  if (dateien.isEmpty) {
    stdout.writeln('keine lesbaren Dateien in ${args[0]}');
    return;
  }

  final uhr = Stopwatch()..start();
  final proAufnahme = <List<Staubverdacht>>[];
  img.Image? erstes;
  for (final datei in dateien) {
    final bild = img.decodeImage(datei.readAsBytesSync());
    if (bild == null) continue;
    erstes ??= bild;
    proAufnahme.add(findeStaubverdacht(bild));
  }
  uhr.stop();

  final verdachte = proAufnahme.fold(0, (s, l) => s + l.length);
  stdout.writeln('${proAufnahme.length} Aufnahmen, $verdachte Verdachte '
      '(${(verdachte / proAufnahme.length).toStringAsFixed(1)} je Aufnahme)');
  stdout.writeln('Zeit je Aufnahme: '
      '${(uhr.elapsedMilliseconds / proAufnahme.length).toStringAsFixed(0)} ms');

  for (final schwelle in [0.4, 0.5, 0.6, 0.7, 0.8]) {
    final stellen = bestaetigeUeberSerie(proAufnahme, mindestanteil: schwelle);
    stdout.writeln('  ab ${(schwelle * 100).toStringAsFixed(0)} %: '
        '${stellen.length} bestaetigte Stellen');
  }

  final stellen = bestaetigeUeberSerie(proAufnahme);
  for (final s in stellen.take(12)) {
    stdout.writeln('  ${s.x.toStringAsFixed(3)}/${s.y.toStringAsFixed(3)}  '
        'r=${s.radius.toStringAsFixed(4)}  ${s.treffer}/${s.untersucht}');
  }

  if (args.length > 1 && erstes != null && stellen.isNotEmpty) {
    final beleg = img.copyResize(erstes, width: 1200);
    for (final s in stellen) {
      final r = (s.radius * beleg.height).round().clamp(6, 80);
      img.drawCircle(beleg,
          x: (s.x * beleg.width).round(),
          y: (s.y * beleg.height).round(),
          radius: r + 6,
          color: img.ColorRgb8(255, 40, 40));
    }
    File(args[1]).writeAsBytesSync(img.encodePng(beleg));
    stdout.writeln('Beleg: ${args[1]}');
  }
}
