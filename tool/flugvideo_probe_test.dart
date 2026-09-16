/// **Ein echtes Video, mit echtem ffmpeg.**
///
/// Kein Teil der Prüfsuite: `flugvideo_test.dart` stellt ffmpeg durch ein
/// Skript nach und prüft damit die Schalter und das Verhalten am Prozess.
/// Was ein Skript nicht beantworten kann, ist die Frage, ob am Ende eine
/// **abspielbare Datei** steht – dafür braucht es den echten Kodierer.
///
/// Läuft nur, wo ffmpeg liegt. Unter Linux und Windows ist es im Paket,
/// unter macOS nicht.
///
/// ```sh
/// PV_VIDEO=/tmp/pv_probe flutter test tool/flugvideo_probe_test.dart
/// ```
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/flugvideo.dart';

void main() {
  testWidgets('ein echtes Video entsteht und laesst sich lesen',
      (tester) async {
    final ordner = Platform.environment['PV_VIDEO'];
    if (ordner == null) {
      markTestSkipped('PV_VIDEO nicht gesetzt');
      return;
    }
    Directory(ordner).createSync(recursive: true);

    // **Jeder Prozessaufruf gehoert in `runAsync`.** Das hat mich hier
    // fuenf Minuten gekostet: `Process.run` ausserhalb kehrt in der
    // gestellten Zeit eines Widget-Tests NIE zurueck, und der Lauf
    // haengt wortlos bis zur Zeitgrenze - ohne eine einzige Zeile
    // Ausgabe, die auf die Stelle zeigt.
    String pfad = '';
    await tester.runAsync(() async {
      final ffmpeg = await Process.run('which', ['ffmpeg']);
      pfad = (ffmpeg.stdout as String).trim();
    });
    if (pfad.isEmpty) {
      markTestSkipped('kein ffmpeg auf dieser Maschine');
      return;
    }
    stdout.writeln('ffmpeg: $pfad');

    final ziel = File('$ordner/probe.mp4');
    late Videoergebnis ergebnis;
    final uhr = Stopwatch()..start();
    await tester.runAsync(() async {
      ergebnis = await schreibeFlugvideo(
        ziel: ziel,
        breite: 1920,
        hoehe: 1080,
        dauer: const Duration(seconds: 3),
        ffmpeg: pfad,
        fortschritt: (a) {
          if ((a * 90).round() % 30 == 0) {
            stdout.writeln('  ${(a * 100).round()} % nach '
                '${uhr.elapsedMilliseconds} ms');
          }
        },
        maleBild: (leinwand, flaeche, t) {
          // Etwas, das sich bewegt und Kanten hat - ein Standbild waere
          // auch dann klein, wenn die Bilder gar nicht ankaemen.
          leinwand.drawRect(
            ui.Rect.fromLTWH(0, 0, flaeche.width, flaeche.height),
            ui.Paint()..color = Color.lerp(Colors.indigo, Colors.orange, t)!,
          );
          for (var i = 0; i < 40; i++) {
            final w = t * math.pi * 2 + i * 0.16;
            leinwand.drawCircle(
              Offset(flaeche.width * (0.5 + 0.4 * math.cos(w)),
                  flaeche.height * (0.5 + 0.4 * math.sin(w * 1.3))),
              18 + 10 * math.sin(w * 3),
              ui.Paint()..color = Colors.white.withValues(alpha: 0.7),
            );
          }
        },
      );
    });
    uhr.stop();

    expect(ergebnis.ausgang, Videoausgang.fertig,
        reason: '${ergebnis.meldung}');
    expect(ziel.existsSync(), isTrue);
    final groesse = ziel.lengthSync();
    stdout.writeln('${(groesse / 1024).round()} kB in '
        '${(uhr.elapsedMilliseconds / 1000).toStringAsFixed(1)} s '
        'fuer 90 Bilder in 1920x1080');
    expect(groesse, greaterThan(10000),
        reason: 'eine Datei von wenigen Bytes ist keine');

    // **Und der eigentliche Beleg: ffprobe muss sie lesen koennen.** Eine
    // Datei, die entsteht, ist noch keine, die sich abspielen laesst.
    late ProcessResult probe;
    await tester.runAsync(() async {
      probe = await Process.run('ffprobe', [
        '-v', 'error',
        '-select_streams', 'v:0',
        '-show_entries', 'stream=width,height,nb_read_frames,codec_name',
        '-count_frames',
        '-of', 'default=noprint_wrappers=1',
        ziel.path,
      ]);
    });
    final text = '${probe.stdout}';
    stdout.writeln(text.trim());
    expect(probe.exitCode, 0, reason: '${probe.stderr}');
    expect(text, contains('width=1920'));
    expect(text, contains('height=1080'));
    expect(text, contains('codec_name=h264'));
    // Drei Sekunden zu dreissig Bildern.
    expect(text, contains('nb_read_frames=90'));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
