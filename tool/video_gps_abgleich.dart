// Liest den Ort aus jedem Video einer Liste – mit dem Code, der auch in
// der App läuft. Zum Gegenlesen gegen `exiftool` an einer echten
// Bibliothek:
//
//   dart run tool/video_gps_abgleich.dart <liste.txt>
//
// Ausgabe je Zeile: Pfad|Breite|Länge bzw. Pfad|KEIN_GPS.
import 'dart:io';

import 'package:photo_vault/services/video_gps.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Aufruf: dart run tool/video_gps_abgleich.dart <liste.txt>');
    exitCode = 2;
    return;
  }
  final pfade =
      File(args[0]).readAsLinesSync().where((z) => z.trim().isNotEmpty);
  final uhr = Stopwatch()..start();
  var anzahl = 0;
  for (final pfad in pfade) {
    final ort = await leseVideoGps(File(pfad));
    anzahl++;
    stdout.writeln(ort == null
        ? [pfad, 'KEIN_GPS'].join('|')
        : [pfad, ort.breite.toStringAsFixed(8), ort.laenge.toStringAsFixed(8)]
            .join('|'));
  }
  stderr.writeln('$anzahl Dateien in ${uhr.elapsedMilliseconds} ms');
}
