// Messgerät: Was die Staubsuche je Aufnahme kostet – und woran sie
// scheitert. Lesend, gegen eine Kopie der Bibliothek.
//
//   dart run tool/messe_staubaufwand.dart <bibliotheksordner> <datei> ...
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:photo_vault/services/staubflecken.dart';

int rssMb() {
  final r = Process.runSync('ps', ['-o', 'rss=', '-p', '$pid']);
  return (int.parse((r.stdout as String).trim()) / 1024).round();
}

void main(List<String> args) {
  for (final pfad in args) {
    final datei = File(pfad);
    if (!datei.existsSync()) {
      stdout.writeln('$pfad -> fehlt');
      continue;
    }
    final vorher = rssMb();
    final t0 = DateTime.now();
    final bytes = datei.readAsBytesSync();
    final bild = img.decodeImage(bytes);
    final tDek = DateTime.now().difference(t0).inMilliseconds;
    final nachDek = rssMb();
    if (bild == null) {
      stdout.writeln('${_kurz(pfad)}  ${(bytes.length / 1e6).toStringAsFixed(1)} MB '
          '-> NICHT DEKODIERBAR ($tDek ms)');
      continue;
    }
    final t1 = DateTime.now();
    final verdachte = findeStaubverdacht(bild);
    final tSuche = DateTime.now().difference(t1).inMilliseconds;
    stdout.writeln('${_kurz(pfad)}  ${bild.width}x${bild.height}  '
        'dekodieren $tDek ms  suchen $tSuche ms  '
        'RSS $vorher->$nachDek->${rssMb()} MB  '
        'Verdachte ${verdachte.length}');
  }
}

String _kurz(String p) => p.split('/').last.padRight(42);
