import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/diashow.dart';
import 'package:photo_vault/services/flugvideo.dart';

/// Die Diashow als Video: wann was zu sehen ist, und dass der Lauf durch
/// die Videoausgabe kommt.
void main() {
  group('Takt', () {
    Diashowtakt takt(int ms, int anzahl) =>
        diashowTakt(Duration(milliseconds: ms), anzahl);

    test('erst die Titelkarte, gegen Ende blendet das erste Foto ein', () {
      expect(takt(0, 3).titel, isTrue);
      expect(takt(0, 3).naechster, isNull);
      final ende = takt(diashowTitel.inMilliseconds - 400, 3);
      expect(ende.titel, isTrue);
      expect(ende.naechster, 0);
      expect(ende.ueberblendung, closeTo(0.5, 0.01));
    });

    test('jedes Foto kommt dran, in der Reihe', () {
      final gesehen = <int>{};
      final ende = diashowDauer(5).inMilliseconds;
      for (var ms = 0; ms < ende; ms += 100) {
        final t = takt(ms, 5);
        if (!t.titel) gesehen.add(t.index);
      }
      expect(gesehen, {0, 1, 2, 3, 4});
    });

    test('überblendet wird nur zwischen zwei Fotos, nie nach dem letzten', () {
      final vorEnde1 =
          diashowTitel.inMilliseconds + diashowJeBild.inMilliseconds - 400;
      final t = takt(vorEnde1, 3);
      expect(t.index, 0);
      expect(t.naechster, 1);
      expect(t.ueberblendung, closeTo(0.5, 0.01));
      final letztes = takt(diashowDauer(3).inMilliseconds - 100, 3);
      expect(letztes.index, 2);
      expect(letztes.naechster, isNull);
    });

    test('nach dem Ende bleibt das letzte Foto stehen', () {
      expect(takt(diashowDauer(2).inMilliseconds + 5000, 2).index, 1);
    });
  });

  testWidgets('der Lauf kommt mit allen Bildern durch die Ausgabe', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final ordner = Directory.systemTemp.createTempSync('pv_diashow');
      addTearDown(() => ordner.deleteSync(recursive: true));
      // Zwei kleine Fotos und ein kaputtes, das das Video nicht aufhält.
      Future<File> foto(String name, Color farbe) async {
        final r = ui.PictureRecorder();
        ui.Canvas(r).drawColor(farbe, BlendMode.src);
        final bild = await r.endRecording().toImage(40, 30);
        final png = await bild.toByteData(format: ui.ImageByteFormat.png);
        return File('${ordner.path}/$name.png')
          ..writeAsBytesSync(png!.buffer.asUint8List());
      }

      final dateien = [
        await foto('a', Colors.red),
        File('${ordner.path}/kaputt.jpg')..writeAsStringSync('kein Bild'),
        await foto('b', Colors.blue),
      ];
      final merk = File('${ordner.path}/aufruf.txt');
      final ffmpeg = File('${ordner.path}/ffmpeg.sh')
        ..writeAsStringSync('''
#!/bin/sh
n=\$(cat | wc -c)
echo "bytes=\$n" > "${merk.path}"
for letztes in "\$@"; do :; done
: > "\$letztes"
''');
      await Process.run('chmod', ['+x', ffmpeg.path]);

      final e = await schreibeDiashow(
        ziel: File('${ordner.path}/rueckblick.mp4'),
        dateien: dateien,
        titel: 'Im Oktober vor 5 Jahren',
        breite: 32,
        hoehe: 18,
        bilderJeSekunde: 4,
        ffmpeg: ffmpeg.path,
      );
      expect(e.ausgang, Videoausgang.fertig, reason: '${e.meldung}');
      final bilder = (diashowDauer(3).inMilliseconds * 4 / 1000).round();
      expect(
        RegExp(r'bytes=\s*(\d+)').firstMatch(merk.readAsStringSync())!.group(1),
        '${bilder * 32 * 18 * 4}',
      );
    });
  }, skip: Platform.isWindows);
}
