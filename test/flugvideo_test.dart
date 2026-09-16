// Der Videoexport – geprüft mit einem gestellten „ffmpeg".
//
// **Warum ein gestelltes und kein echtes.** Ein echter Lauf hinge davon
// ab, ob auf dieser Maschine ffmpeg liegt, und er dauerte Sekunden je
// Test. Was hier zu prüfen ist, sind die Schalter und das Verhalten am
// Prozess: dass die Kantenlängen gerade sind, dass genau so viele Bilder
// ankommen wie gerechnet, dass ein Abbruch die halbfertige Datei
// wegräumt, und dass ein Fehler von ffmpeg als Fehler ankommt statt
// still zu bleiben.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/flugvideo.dart';

/// Ein Skript, das sich wie ffmpeg verhält: Es liest `stdin` leer,
/// schreibt die Zahl der gelesenen Bytes und die Schalter in eine
/// Merkdatei, legt die Zieldatei an und endet mit [code].
Future<File> _gestelltesFfmpeg(Directory ordner,
    {int code = 0, String meldung = ''}) async {
  final merk = File('${ordner.path}/aufruf.txt');
  final skript = File('${ordner.path}/ffmpeg.sh');
  await skript.writeAsString('''
#!/bin/sh
echo "\$@" > "${merk.path}"
n=\$(cat | wc -c)
echo "bytes=\$n" >> "${merk.path}"
# Die Zieldatei ist das letzte Argument.
for letztes in "\$@"; do :; done
: > "\$letztes"
${meldung.isEmpty ? '' : 'echo "$meldung" >&2'}
exit $code
''');
  await Process.run('chmod', ['+x', skript.path]);
  return skript;
}

Future<String> _aufruf(Directory ordner) =>
    File('${ordner.path}/aufruf.txt').readAsString();

void main() {
  group('gestelltes ffmpeg', () {
    late Directory ordner;
    setUp(() => ordner = Directory.systemTemp.createTempSync('pv_flugvideo'));
    tearDown(() {
      if (ordner.existsSync()) ordner.deleteSync(recursive: true);
    });

    void malEtwas(ui.Canvas leinwand, ui.Size flaeche, double t) {
      leinwand.drawRect(
        ui.Rect.fromLTWH(0, 0, flaeche.width, flaeche.height),
        ui.Paint()..color = Color.lerp(Colors.red, Colors.blue, t)!,
      );
    }

    testWidgets('so viele Bilder wie gerechnet, in der richtigen Groesse',
        (tester) async {
      await tester.runAsync(() async {
        final ffmpeg = await _gestelltesFfmpeg(ordner);
        final ziel = File('${ordner.path}/flug.mp4');
        final e = await schreibeFlugvideo(
          ziel: ziel,
          breite: 64,
          hoehe: 48,
          dauer: const Duration(seconds: 1),
          bilderJeSekunde: 10,
          maleBild: malEtwas,
          ffmpeg: ffmpeg.path,
        );
        expect(e.ausgang, Videoausgang.fertig, reason: '${e.meldung}');
        final text = await _aufruf(ordner);
        expect(text, contains('-video_size 64x48'));
        expect(text, contains('-framerate 10'));
        expect(text, contains('rawvideo'));
        expect(text, contains('yuv420p'));
        // Zehn Bilder zu 64 x 48 x 4 Byte. `wc -c` polstert mit
        // Leerzeichen - deshalb die Zahl fuer sich, nicht der ganze Text.
        expect(RegExp(r'bytes=\s*(\d+)').firstMatch(text)!.group(1),
            '${10 * 64 * 48 * 4}');
      });
    });

    testWidgets('ungerade Kanten werden gerade gemacht', (tester) async {
      // `yuv420p` tastet die Farbe halb so fein ab wie die Helligkeit; eine
      // ungerade Kante laesst sich nicht halbieren, und ffmpeg bricht mit
      // "width not divisible by 2" ab.
      await tester.runAsync(() async {
        final ffmpeg = await _gestelltesFfmpeg(ordner);
        final e = await schreibeFlugvideo(
          ziel: File('${ordner.path}/flug.mp4'),
          breite: 65,
          hoehe: 49,
          dauer: const Duration(milliseconds: 200),
          bilderJeSekunde: 10,
          maleBild: malEtwas,
          ffmpeg: ffmpeg.path,
        );
        expect(e.ausgang, Videoausgang.fertig);
        expect(await _aufruf(ordner), contains('-video_size 64x48'));
      });
    });

    testWidgets('ohne ffmpeg wird das gesagt, statt still nichts zu tun',
        (tester) async {
      await tester.runAsync(() async {
        final e = await schreibeFlugvideo(
          ziel: File('${ordner.path}/flug.mp4'),
          breite: 32,
          hoehe: 32,
          dauer: const Duration(milliseconds: 100),
          maleBild: malEtwas,
          // Der Weg ueber die Werkzeugsuche wird hier uebersprungen; auf
          // einer Maschine ohne ffmpeg liefert sie `null`, und genau das
          // wird hier gestellt.
          ffmpeg: '${ordner.path}/gibtesnicht',
        );
        expect(e.ausgang, Videoausgang.fehler);
        expect(File('${ordner.path}/flug.mp4').existsSync(), isFalse);
      });
    });

    testWidgets('ein Abbruch laesst keine halbe Datei zurueck', (tester) async {
      // Eine halbfertige Datei sieht aus wie eine fertige und laesst sich
      // nicht abspielen - schlimmer als gar keine.
      await tester.runAsync(() async {
        final ffmpeg = await _gestelltesFfmpeg(ordner);
        final ziel = File('${ordner.path}/flug.mp4');
        var bilder = 0;
        final e = await schreibeFlugvideo(
          ziel: ziel,
          breite: 32,
          hoehe: 32,
          dauer: const Duration(seconds: 2),
          bilderJeSekunde: 10,
          maleBild: (l, f, t) {
            bilder++;
            malEtwas(l, f, t);
          },
          abbruch: () => bilder >= 3,
          ffmpeg: ffmpeg.path,
        );
        expect(e.ausgang, Videoausgang.abgebrochen);
        expect(bilder, 3, reason: 'der Abbruch greift zu spaet');
        expect(ziel.existsSync(), isFalse);
      });
    });

    testWidgets('beschwert sich ffmpeg, kommt die Beschwerde an',
        (tester) async {
      await tester.runAsync(() async {
        final ffmpeg = await _gestelltesFfmpeg(ordner,
            code: 1, meldung: 'Unknown encoder libx264');
        final e = await schreibeFlugvideo(
          ziel: File('${ordner.path}/flug.mp4'),
          breite: 32,
          hoehe: 32,
          dauer: const Duration(milliseconds: 300),
          bilderJeSekunde: 10,
          maleBild: malEtwas,
          ffmpeg: ffmpeg.path,
        );
        expect(e.ausgang, Videoausgang.fehler);
        expect(e.meldung, contains('libx264'));
      });
    });

    testWidgets('null Dauer ergibt keinen Prozess', (tester) async {
      await tester.runAsync(() async {
        final ffmpeg = await _gestelltesFfmpeg(ordner);
        final e = await schreibeFlugvideo(
          ziel: File('${ordner.path}/flug.mp4'),
          breite: 32,
          hoehe: 32,
          dauer: Duration.zero,
          maleBild: malEtwas,
          ffmpeg: ffmpeg.path,
        );
        expect(e.ausgang, Videoausgang.fehler);
        expect(File('${ordner.path}/aufruf.txt').existsSync(), isFalse,
            reason: 'ffmpeg wurde umsonst gestartet');
      });
    });
  },
      skip: Platform.isWindows
          ? 'Der POSIX-ffmpeg-Doppelgänger wird durch flugvideo_nativ_test abgedeckt.'
          : false);
}
