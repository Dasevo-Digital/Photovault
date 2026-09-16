// Liest Aufnahmezeit und Kamera aus jedem Video einer Liste – mit dem
// Code, der auch in der App läuft. Zum Gegenlesen gegen `exiftool` an
// einer echten Bibliothek:
//
//   dart run tool/video_zeit_abgleich.dart <liste.txt>
//
// Ausgabe je Zeile: Pfad|Zeitpunkt|Herkunft|Hersteller|Gerät
// bzw. Pfad|KEINE_ZEIT|…
//
// Gegenprobe auf der anderen Seite:
//   exiftool -json -CreationDate -CreateDate -Make -Model -@ liste.txt
// Wobei `CreationDate` (Apple, mit Zone) massgeblich ist und `CreateDate`
// roh aus `mvhd` kommt – siehe den Kopf von video_metadaten.dart.
import 'dart:io';

import 'package:photo_vault/services/video_metadaten.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Aufruf: dart run tool/video_zeit_abgleich.dart <liste.txt>');
    exitCode = 2;
    return;
  }
  final pfade =
      File(args[0]).readAsLinesSync().where((z) => z.trim().isNotEmpty);
  final uhr = Stopwatch()..start();
  var anzahl = 0;
  for (final pfad in pfade) {
    final datei = File(pfad);
    final zeit = await leseVideoZeit(datei);
    final kamera = await leseVideoKamera(datei);
    anzahl++;
    stdout.writeln([
      pfad,
      zeit == null ? 'KEINE_ZEIT' : zeit.zeitpunkt.toIso8601String(),
      zeit == null ? '-' : zeit.herkunft.name,
      kamera.hersteller ?? '-',
      kamera.geraet ?? '-',
    ].join('|'));
  }
  stderr.writeln('$anzahl Dateien in ${uhr.elapsedMilliseconds} ms');
}
