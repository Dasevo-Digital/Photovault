import 'dart:async';

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
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('eine Restaurierungskachel', (tester) async {
    final support = await getApplicationSupportDirectory();
    final modelle = p.join(support.path, 'PhotoVault', 'models');
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
    unawaited(() async {
      while (laeuft) {
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
    final support = await getApplicationSupportDirectory();
    final modelle = p.join(support.path, 'PhotoVault', 'models');
    if (!RestoreService.isAvailable(modelle)) {
      markTestSkipped('real_esrgan_x4.onnx fehlt in $modelle');
      return;
    }
    final dienst = await RestoreService.load(modelle);
    // 800 × 600: vier Kacheln, Ergebnis 3200 × 2400 – genug, damit das
    // Zusammensetzen und das JPEG am Ende ins Gewicht fallen.
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
    final erste = Completer<void>();
    final uhr = Stopwatch()..start();
    final lauf = dienst.starteJpeg(
      jpeg,
      onProgress: (fertig, gesamt) {
        stand.add(fertig);
        if (!erste.isCompleted) erste.complete();
      },
    );
    // Auf die erste Kachel warten – oder auf das Ende, falls das Isolat
    // vorher scheitert: Sonst hinge der Test wortlos.
    await Future.any([
      erste.future,
      lauf.ergebnis,
    ]).timeout(const Duration(seconds: 60));
    expect(
      stand,
      isNotEmpty,
      reason: 'das Isolat hat nie eine Kachel gemeldet',
    );
    lauf.pausieren();
    // Die laufende Kachel darf noch fertig werden, danach steht er.
    await Future<void>.delayed(const Duration(seconds: 9));
    final waehrendPause = stand.length;
    await Future<void>.delayed(const Duration(seconds: 6));
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
    expect(stand.last, 4, reason: 'alle vier Kacheln, keine doppelt');
    expect(stand.length, 4);

    // Abbrechen liefert nichts und beendet das Isolat.
    final zweiter = dienst.starteJpeg(jpeg);
    zweiter.abbrechen();
    expect(await zweiter.ergebnis, isNull);
    await dienst.dispose();

    // ignore: avoid_print
    print(
      'Foto ${uhr.elapsedMilliseconds} ms (mit 15 s Pause) | Dart-Takt '
      'fehlte höchstens ${groessteLuecke.inMilliseconds} ms | Kacheln $stand',
    );
    expect(groessteLuecke.inMilliseconds, lessThan(250));
  });
}
