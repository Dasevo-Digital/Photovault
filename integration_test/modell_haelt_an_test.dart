import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_vault/services/restore_service.dart';

/// **Hält ein laufendes Modell die App an?** (Issue #14)
///
/// Gemessen wird während einer Kachel der KI-Restaurierung zweierlei:
///
/// * wie lange ein 10-ms-Takt in Dart ausbleibt – der Faden, der die
///   Oberfläche baut;
/// * wie lange ein belangloser Kanalaufruf auf seine Antwort wartet – der
///   Hauptfaden der Plattform, über den Maus und Tastatur kommen.
///
/// Übersprungen, wenn das Modell fehlt.
/// Der Modellordner: aus `PV_MODELLE`, sonst der der App.
///
/// **Auf den Testrechnern immer über `PV_MODELLE`.** Dort teilt sich der
/// Testbau den Datenordner mit der eingespielten Fassung. Und ein Ordner
/// `models` am neuen Ort reicht der App als Zeichen, dass die Daten der
/// früheren Kennung schon übernommen sind (`_siehtNachDatenAus`); ein hier
/// abgelegtes Modell liesse sie beim nächsten Start leer dastehen.
Future<String> _modellordner() async =>
    Platform.environment['PV_MODELLE'] ??
    p.join(
      (await getApplicationSupportDirectory()).path,
      'PhotoVault',
      'models',
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('eine Restaurierungskachel', (tester) async {
    final modelle = await _modellordner();
    if (!RestoreService.isAvailable(modelle)) {
      markTestSkipped('real_esrgan_x4.onnx fehlt in $modelle');
      return;
    }
    final dienst = await RestoreService.load(modelle);
    final bild = img.Image(width: 512, height: 512)
      ..clear(img.ColorRgb8(120, 130, 140));
    // Einmal vorweg: Die erste Inferenz übersetzt für CoreML und zählt
    // nicht.
    await dienst.restore(img.Image(width: 64, height: 64));

    var groessteLuecke = Duration.zero;
    var letzter = DateTime.now();
    final takt = Timer.periodic(const Duration(milliseconds: 10), (_) {
      final jetzt = DateTime.now();
      final luecke = jetzt.difference(letzter);
      if (luecke > groessteLuecke) groessteLuecke = luecke;
      letzter = jetzt;
    });
    final kanal = <Duration>[];
    var laeuft = true;
    // Den Kanal zum Messen gibt es nur auf macOS (ImageConverter.swift).
    unawaited(() async {
      while (laeuft && Platform.isMacOS) {
        final uhr = Stopwatch()..start();
        await const MethodChannel(
          'photo_vault/image_convert',
        ).invokeMethod<void>('ping');
        kanal.add(uhr.elapsed);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }());

    final uhr = Stopwatch()..start();
    await dienst.restore(bild);
    uhr.stop();
    laeuft = false;
    takt.cancel();
    await dienst.dispose();

    kanal.sort();
    // ignore: avoid_print
    print(
      'Kachel ${uhr.elapsedMilliseconds} ms | Dart-Takt fehlte höchstens '
      '${groessteLuecke.inMilliseconds} ms | Kanalantwort höchstens '
      '${kanal.isEmpty ? '-' : kanal.last.inMilliseconds} ms '
      '(${kanal.length} Aufrufe)',
    );
  });

  testWidgets('ein ganzes Foto im Isolat: anhalten, fortsetzen, abbrechen', (
    tester,
  ) async {
    final modelle = await _modellordner();
    if (!RestoreService.isAvailable(modelle)) {
      markTestSkipped('real_esrgan_x4.onnx fehlt in $modelle');
      return;
    }
    final dienst = await RestoreService.load(modelle);
    // 800 × 600, Ergebnis 3200 × 2400 – genug, damit das Zusammensetzen
    // und das JPEG am Ende ins Gewicht fallen.
    final quelle = img.Image(width: 800, height: 600);
    for (final q in quelle) {
      q
        ..r = (q.x * 255 / 800).round()
        ..g = (q.y * 255 / 600).round()
        ..b = 128;
    }
    final jpeg = img.encodeJpg(quelle);

    var groessteLuecke = Duration.zero;
    var letzter = DateTime.now();
    final takt = Timer.periodic(const Duration(milliseconds: 10), (_) {
      final jetzt = DateTime.now();
      final luecke = jetzt.difference(letzter);
      if (luecke > groessteLuecke) groessteLuecke = luecke;
      letzter = jetzt;
    });

    final stand = <int>[];
    var gesamtKacheln = 0;
    final erste = Completer<void>();
    final uhr = Stopwatch()..start();
    final lauf = dienst.starteJpeg(
      jpeg,
      onProgress: (fertig, gesamt) {
        gesamtKacheln = gesamt;
        stand.add(fertig);
        if (!erste.isCompleted) erste.complete();
      },
    );
    // Auf die erste Kachel warten – oder auf das Ende, falls das Isolat
    // vorher scheitert: Sonst hinge der Test wortlos.
    await Future.any([
      erste.future,
      lauf.ergebnis,
    ]).timeout(const Duration(seconds: 180));
    expect(
      stand,
      isNotEmpty,
      reason: 'das Isolat hat nie eine Kachel gemeldet',
    );
    lauf.pausieren();
    // Die laufende Kachel darf noch fertig werden, danach steht er. Wie
    // lange eine Kachel braucht, hängt an der Plattform: mit CoreML rund
    // 4 s, auf der CPU unter Linux rund 11 s.
    final kachel = uhr.elapsed;
    await Future<void>.delayed(kachel * 1.5 + const Duration(seconds: 1));
    final waehrendPause = stand.length;
    await Future<void>.delayed(kachel);
    expect(
      stand.length,
      waehrendPause,
      reason: 'angehalten heisst: keine Kachel mehr',
    );
    lauf.fortsetzen();
    final ergebnis = await lauf.ergebnis;
    uhr.stop();
    takt.cancel();
    expect(ergebnis, isNotNull);
    final bild = img.decodeJpg(ergebnis!)!;
    expect(bild.width, 3200);
    // Jede Kachel genau einmal, in Reihenfolge – auch über die Pause
    // hinweg. Wie viele es sind, hängt an der Kachelgrösse der Plattform.
    expect(stand, [for (var i = 1; i <= gesamtKacheln; i++) i]);

    // Abbrechen liefert nichts und beendet das Isolat.
    final zweiter = dienst.starteJpeg(jpeg);
    zweiter.abbrechen();
    expect(await zweiter.ergebnis, isNull);
    await dienst.dispose();

    // ignore: avoid_print
    print(
      'Foto ${uhr.elapsedMilliseconds} ms (mit Pause) | Dart-Takt '
      'fehlte höchstens ${groessteLuecke.inMilliseconds} ms | Kacheln $stand',
    );
    expect(groessteLuecke.inMilliseconds, lessThan(250));
  });
}
