@TestOn('mac-os')
library;

// ignore_for_file: avoid_print
// **Die Videoausgabe unter macOS – in der echten, eingesperrten App.**
//
// Unittests können hier nichts belegen: Ein Method Channel führt unter
// `flutter test` nirgendwohin, und der Sandkasten, um den es geht, ist
// dort gar nicht da. Genau in dieser Lücke sass der Fehler von 3.5.0 –
// die Ausgabe rief nach ffmpeg, und ein eingesperrter Prozess darf kein
// fremdes Programm starten. Auf der Kommandozeile fällt das nie auf.
//
// Geprüft wird deshalb dreierlei, alles im laufenden Programm:
//
//   1. Die Ausgabe hält sich für möglich, **ohne** dass ffmpeg dafür
//      nötig wäre.
//   2. Ein gefundenes ffmpeg lässt sich trotzdem nicht starten – der
//      Beleg für den eigentlichen Grund, und zugleich die Warnung an den
//      Nächsten, der es wieder darüber versuchen will.
//   3. Am Ende steht eine Datei, die das System selbst wieder lesen kann:
//      AVFoundation liefert Dauer und ein Standbild daraus zurück.
//
//   flutter test integration_test/flugvideo_nativ_echt_test.dart -d macos
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photo_vault/services/flugvideo.dart';
import 'package:photo_vault/services/native_image_converter.dart';
import 'package:photo_vault/services/platform/nativer_videoschreiber.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory ordner;
  setUp(() => ordner = Directory.systemTemp.createTempSync('pv_flugvideo'));
  tearDown(() {
    if (ordner.existsSync()) ordner.deleteSync(recursive: true);
  });

  void malEtwas(ui.Canvas leinwand, ui.Size flaeche, double t) {
    leinwand.drawRect(
      ui.Rect.fromLTWH(0, 0, flaeche.width, flaeche.height),
      ui.Paint()..color = Color.lerp(Colors.indigo, Colors.orange, t)!,
    );
    // Kanten, damit ein Standbild nicht auch dann klein wäre, wenn gar
    // nichts ankäme.
    for (var i = 0; i < 20; i++) {
      leinwand.drawCircle(
        Offset(flaeche.width * (0.1 + 0.8 * t), flaeche.height * i / 20),
        6,
        ui.Paint()..color = Colors.white,
      );
    }
  }

  testWidgets('der native Schreiber ist da', (tester) async {
    expect(await NativerVideoschreiber.verfuegbar(), isTrue);
    expect(await videoausgabeMoeglich(), isTrue);
  });

  testWidgets('ein gefundenes ffmpeg laesst sich trotzdem nicht starten',
      (tester) async {
    final pfad = await ffmpegPfad();
    print('ffmpegPfad(): $pfad');
    if (pfad == null) {
      // Aus dem Dock gestartet ist Homebrew gar nicht erst im PATH – dann
      // ist hier nichts zu zeigen. Beim Lauf über `flutter test` erbt die
      // App den PATH der Kommandozeile, und genau dann greift der zweite,
      // wichtigere Grund unten.
      print('kein ffmpeg im PATH dieses Laufs – dann eben nicht');
      return;
    }
    // Der Sandkasten: `stat()` gelingt (deshalb findet die Suche es),
    // `execve` nicht.
    expect(File(pfad).existsSync(), isTrue,
        reason: 'gefunden wurde es ja – daran lag es nie');
    await expectLater(
      Process.start(pfad, const ['-version']),
      throwsA(isA<ProcessException>()),
      reason: 'wenn das hier durchgeht, ist der Sandkasten weg – dann '
          'gehoert dieser Test geprueft, nicht geloescht',
    );
  });

  testWidgets('es entsteht ein Video, das das System wieder lesen kann',
      (tester) async {
    final ziel = File('${ordner.path}/flug.mp4');
    final uhr = Stopwatch()..start();
    late Videoergebnis ergebnis;
    await tester.runAsync(() async {
      ergebnis = await schreibeFlugvideo(
        ziel: ziel,
        breite: 640,
        hoehe: 360,
        dauer: const Duration(seconds: 2),
        maleBild: malEtwas,
      );
    });
    uhr.stop();
    expect(ergebnis.ausgang, Videoausgang.fertig, reason: '${ergebnis.meldung}');
    expect(ziel.existsSync(), isTrue);
    final groesse = ziel.lengthSync();
    print('${(groesse / 1024).round()} kB in '
        '${(uhr.elapsedMilliseconds / 1000).toStringAsFixed(1)} s '
        'fuer 60 Bilder in 640x360');
    expect(groesse, greaterThan(10000), reason: 'eine Datei von wenigen '
        'Bytes ist keine');

    // **Der eigentliche Beleg.** Eine Datei, die entsteht, ist noch keine,
    // die sich abspielen laesst. AVFoundation liest sie hier selbst
    // wieder ein – dieselbe Stelle, die auch die Vorschaubilder der
    // Mediathek macht.
    final gelesen = await tester.runAsync(
        () => NativeImageConverter.generateVideoThumbnail(ziel, maxDimension: 320));
    expect(gelesen, isNotNull, reason: 'das System kann die Datei nicht lesen');
    expect(gelesen!.jpegBytes.length, greaterThan(1000));
    expect(gelesen.durationSeconds, isNotNull);
    print('AVFoundation liest: ${gelesen.durationSeconds!.toStringAsFixed(2)} s');
    expect(gelesen.durationSeconds, closeTo(2.0, 0.15));
  });

  testWidgets('ein Abbruch laesst keine halbe Datei zurueck', (tester) async {
    final ziel = File('${ordner.path}/abbruch.mp4');
    late Videoergebnis ergebnis;
    await tester.runAsync(() async {
      var bilder = 0;
      ergebnis = await schreibeFlugvideo(
        ziel: ziel,
        breite: 320,
        hoehe: 240,
        dauer: const Duration(seconds: 3),
        maleBild: (l, f, t) {
          bilder++;
          malEtwas(l, f, t);
        },
        abbruch: () => bilder >= 5,
      );
    });
    expect(ergebnis.ausgang, Videoausgang.abgebrochen);
    expect(ziel.existsSync(), isFalse);
  });
}
