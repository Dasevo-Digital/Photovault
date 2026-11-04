import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kern/services/platform/desktop_image_tools.dart';
import 'package:path/path.dart' as p;

/// Ein Bildwerkzeug, das hängt, gibt nach [DesktopImageTools.wandlungsgrenze]
/// auf (#263).
///
/// Bis 3.52 wartete jeder Aufruf von dcraw_emu, heif-dec, djxl oder
/// vipsthumbnail ohne Ende. Am Server wandelt immer nur eines auf einmal;
/// eine kaputte Datei hielt dort jede weitere Vollansicht auf, bis der
/// Dienst neu startete.
void main() {
  late Directory temp;
  final vorher = DesktopImageTools.wandlungsgrenze;
  setUp(() => temp = Directory.systemTemp.createTempSync('pv_zeitgrenze_'));
  tearDown(() {
    DesktopImageTools.wandlungsgrenze = vorher;
    DesktopImageTools.vergissWerkzeuge();
    temp.deleteSync(recursive: true);
  });

  test('ein hängendes djxl wird beendet, und es kommt nichts', () async {
    final pidDatei = File(p.join(temp.path, 'pid'));
    final djxl = File(p.join(temp.path, 'djxl'))
      ..writeAsStringSync('''#!/bin/sh
echo \$\$ > "${pidDatei.path}"
exec sleep 60
''');
    Process.runSync('chmod', ['+x', djxl.path]);
    DesktopImageTools.stelleWerkzeuge({'djxl': djxl.path});
    // Lang genug, dass das Skript auch unter der Last der ganzen
    // Testreihe anläuft und seine Kennung schreibt – mit 300 ms scheiterte
    // der Test dort ab und zu.
    DesktopImageTools.wandlungsgrenze = const Duration(seconds: 2);

    final uhr = Stopwatch()..start();
    final r = await DesktopImageTools.convertToJpeg(
      File('test/fixtures/jxl/klein_40x24.jxl'),
    );
    expect(r, isNull);
    expect(uhr.elapsed, lessThan(const Duration(seconds: 30)));

    // Und es läuft nicht im Hintergrund weiter. Ohne Kennung kam es gar
    // nicht bis zum `echo` – dann lebt es ohnehin nicht mehr.
    if (!pidDatei.existsSync()) return;
    final pid = pidDatei.readAsStringSync().trim();
    var lebt = true;
    for (var i = 0; i < 200 && lebt; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      lebt = Process.runSync('kill', ['-0', pid]).exitCode == 0;
    }
    expect(lebt, isFalse);
  }, skip: Platform.isWindows ? 'Shell-Skript als Werkzeug' : false);
}
