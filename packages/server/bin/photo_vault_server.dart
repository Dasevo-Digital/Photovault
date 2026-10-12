import 'dart:async';
import 'dart:io';

import 'package:kern/protokoll.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main(List<String> argumente) async {
  protokollZiel = (meldung) =>
      stdout.writeln('${DateTime.now().toIso8601String()} $meldung');
  // Auf dem Server gibt es keinen nativen Kanal einer App: Bilder, Videos
  // und Ton gehen über die Werkzeuge (ffmpeg, libheif, LibRaw).
  Bildwerkzeuge.standard = const WerkzeugBildwerkzeuge();

  final e = Einstellungen.ausUmgebung();
  final zugang = await Zugang.ladeOderLegeAn(e.zugangsdatei);
  final bibliothek = await Bibliothek.oeffne(
    Directory(p.join(e.bibliotheken.path, 'standard')),
  );
  final hochladen = Hochladen(e.eingang, bibliothek);
  final weg = await hochladen.raeumeAuf();
  if (weg > 0) protokoll('$weg liegengebliebene Uploads weggeräumt');

  final server = await shelf_io.serve(
    baueApi(bibliothek: bibliothek, hochladen: hochladen, zugang: zugang),
    e.adresse,
    e.port,
  );
  server.autoCompress = true;
  protokoll(
    'Photo Vault Server auf http://${e.adresse}:${server.port} – '
    'Daten in ${e.daten.path}, Schlüssel in ${e.zugangsdatei.path}',
  );

  await Future.any([
    ProcessSignal.sigint.watch().first,
    if (!Platform.isWindows) ProcessSignal.sigterm.watch().first,
  ]);
  protokoll('Beende …');
  await server.close();
  await bibliothek.schliesse();
  exit(0);
}
