import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:photo_vault/services/blur_detection.dart';

// Misst die Laplace-Varianz echter Gesichtsausschnitte, um die Schwelle fuer
// "das Gesicht ist unscharf" aus Daten statt aus einer Vermutung zu setzen -
// siehe gesichtUnscharfSchwelle in lib/services/blur_detection.dart.
//
//   dart run tool/messe_gesichtsschaerfe.dart <faces-ordner> [belege-ordner]
//
// Der zweite Pfad ist optional: Dorthin werden die weichsten, die schaerfsten
// und ein paar Ausschnitte aus dem Grenzbereich kopiert. Eine Verteilung
// allein sagt nicht, ob die Schwelle die richtigen trifft - dafuer muss man
// sie ansehen.
void main(List<String> args) {
  final ordner = Directory(args.first);
  final dateien = ordner.listSync().whereType<File>().where((f) => f.path.endsWith('.jpg')).toList();
  dateien.sort((a, b) => a.path.compareTo(b.path));
  final schritt = math.max(1, dateien.length ~/ 1500);
  final werte = <double>[];
  var masse = <String>{};
  final uhr = Stopwatch()..start();
  for (var i = 0; i < dateien.length; i += schritt) {
    final bytes = dateien[i].readAsBytesSync();
    final bild = img.decodeJpg(bytes);
    if (bild == null) continue;
    masse.add('${bild.width}x${bild.height}');
    werte.add(computeBlurScore(bild));
  }
  uhr.stop();
  werte.sort();
  double q(double p) => werte[(werte.length * p).clamp(0, werte.length - 1).toInt()];
  stdout.writeln('Ausschnitte gesamt: ${dateien.length}, gemessen: ${werte.length}');
  stdout.writeln('Masse: $masse');
  stdout.writeln('Zeit je Ausschnitt: ${(uhr.elapsedMicroseconds / werte.length / 1000).toStringAsFixed(2)} ms');
  for (final p in [0.01, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.99]) {
    stdout.writeln('  ${(p * 100).toStringAsFixed(0).padLeft(3)}%: ${q(p).toStringAsFixed(1)}');
  }
  stdout.writeln('  min ${werte.first.toStringAsFixed(1)}  max ${werte.last.toStringAsFixed(1)}');
  for (final schwelle in [20.0, 30.0, 40.0, 50.0, 100.0]) {
    final anteil = werte.where((w) => w < schwelle).length / werte.length;
    stdout.writeln('  unter $schwelle: ${(anteil * 100).toStringAsFixed(1)} %');
  }

  // Belege zum Ansehen: die weichsten und die schaerfsten Ausschnitte.
  if (args.length > 1) {
    final ziel = Directory(args[1])..createSync(recursive: true);
    final mitWert = <(double, File)>[];
    for (var i = 0; i < dateien.length; i += schritt) {
      final bild = img.decodeJpg(dateien[i].readAsBytesSync());
      if (bild != null) mitWert.add((computeBlurScore(bild), dateien[i]));
    }
    mitWert.sort((a, b) => a.$1.compareTo(b.$1));
    for (var i = 0; i < 6; i++) {
      mitWert[i].$2.copySync('${ziel.path}/weich_${i}_${mitWert[i].$1.toStringAsFixed(0)}.jpg');
      final s = mitWert[mitWert.length - 1 - i];
      s.$2.copySync('${ziel.path}/scharf_${i}_${s.$1.toStringAsFixed(0)}.jpg');
    }
    // Der Grenzbereich - hier entscheidet sich, ob die Schwelle taugt.
    var n = 0;
    for (final (wert, datei) in mitWert) {
      if (wert < 25 || wert > 70 || n >= 8) continue;
      datei.copySync('${ziel.path}/grenze_${n++}_${wert.toStringAsFixed(0)}.jpg');
    }
    stdout.writeln('Belege in ${ziel.path}');
  }
}
