import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/services/inpainting_service.dart';
import 'package:photo_vault/services/kolorieren.dart';

import 'hilfen/onnx_attrappe.dart';

/// Retusche (LaMa) und Einfärben mit einer Attrappe statt des Modells.
///
/// Die Attrappe füllt jede Stelle schwarz (Retusche) bzw. ohne Farbe
/// (Einfärben) – geprüft wird, was um das Modell herum geschieht.
void main() {
  const n = InpaintingService.modellGroesse;
  late Directory ordner;

  setUp(() {
    ordner = Directory.systemTemp.createTempSync('retusche_');
    OnnxRuntimePlatform.instance = OnnxAttrappe(
      rechne: (pfad, _) => {
        if (pfad.endsWith('lama_fp32.onnx'))
          'output': (daten: Float32List(3 * n * n), form: [1, 3, n, n]),
        if (pfad.endsWith(KolorierService.datei))
          'output': (daten: Float32List(2 * n * n), form: [1, 2, n, n]),
      },
    );
  });
  tearDown(() => ordner.deleteSync(recursive: true));

  img.Image weiss(int breite, int hoehe) =>
      img.Image(width: breite, height: hoehe)
        ..clear(img.ColorRgb8(255, 255, 255));

  img.Image strich(int breite, int hoehe, int x1, int y1, int x2, int y2) =>
      img.fillRect(
        img.Image(width: breite, height: hoehe),
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        color: img.ColorRgb8(255, 255, 255),
      );

  /// Die längste Zeit, in der das Isolat dieses Tests nicht dazu kam, eine
  /// Uhr alle 5 ms abzufragen, während [arbeit] lief – so lange stünde
  /// das Fenster still.
  Future<Duration> laengsterStillstand(Future<void> Function() arbeit) async {
    final uhr = Stopwatch()..start();
    var zuletzt = uhr.elapsed;
    var laengster = Duration.zero;
    void miss() {
      final jetzt = uhr.elapsed;
      if (jetzt - zuletzt > laengster) laengster = jetzt - zuletzt;
      zuletzt = jetzt;
    }

    final takt = Timer.periodic(const Duration(milliseconds: 5), (_) => miss());
    await arbeit();
    takt.cancel();
    miss();
    return laengster;
  }

  group('Retusche', () {
    test('ein Strich länger als die kurze Bildseite geht ganz weg', () async {
      // Eine Leitung quer über ein Querformat: länger als die Höhe des
      // Fotos. Der Ausschnitt ist quadratisch und höchstens so gross wie
      // die kurze Seite – bisher blieben die Enden des Strichs stehen.
      final dienst = await InpaintingService.load(ordner.path);
      final ergebnis = (await dienst.entferne(
        weiss(1200, 400),
        strich(1200, 400, 20, 190, 1179, 209),
      ))!;
      var stehengeblieben = 0;
      for (var y = 190; y <= 209; y++) {
        for (var x = 20; x <= 1179; x++) {
          if (ergebnis.getPixel(x, y).r != 0) stehengeblieben++;
        }
      }
      expect(stehengeblieben, 0);
      // Ausserhalb der Maske bleibt alles, wie es war.
      expect(ergebnis.getPixel(10, 200).r, 255);
      expect(ergebnis.getPixel(600, 100).r, 255);
      expect(ergebnis.getPixel(1190, 200).r, 255);
      await dienst.dispose();
    });

    test('Hochformat: auch ein senkrechter Strich geht ganz weg', () async {
      final dienst = await InpaintingService.load(ordner.path);
      final ergebnis = (await dienst.entferne(
        weiss(300, 1000),
        strich(300, 1000, 140, 10, 159, 989),
      ))!;
      for (final y in [10, 300, 500, 700, 989]) {
        expect(ergebnis.getPixel(150, y).r, 0, reason: 'y=$y');
      }
      expect(ergebnis.getPixel(150, 995).r, 255);
      await dienst.dispose();
    });

    test('eine leere Maske ergibt null', () async {
      final dienst = await InpaintingService.load(ordner.path);
      expect(
        await dienst.entferne(
          weiss(100, 100),
          img.Image(width: 100, height: 100),
        ),
        isNull,
      );
      await dienst.dispose();
    });

    test('das Fenster steht nicht still, während sie rechnet', () async {
      // Ein Foto mit 24 Megapixeln. Bisher lief alles ausser dem Modell
      // im Isolat der Oberfläche: das Absuchen der Maske, das
      // Zurückrechnen des Ausschnitts und das Einsetzen – Sekunden, in
      // denen auch die Warteanzeige stillstand.
      final dienst = await InpaintingService.load(ordner.path);
      final bild = weiss(6000, 4000);
      final maske = strich(6000, 4000, 1000, 1500, 3999, 1519);
      final stillstand = await laengsterStillstand(
        () => dienst.entferne(bild, maske),
      );
      expect(stillstand, lessThan(const Duration(milliseconds: 600)));
      await dienst.dispose();
    });
  });

  group('Einfärben', () {
    test('das Fenster steht nicht still, während es rechnet', () async {
      // Die Farbe wird in voller Auflösung über das Original gelegt, mit
      // sieben Potenzen je Bildpunkt – bisher im Isolat der Oberfläche.
      final dienst = await KolorierService.load(ordner.path);
      final bild = img.Image(width: 6000, height: 4000)
        ..clear(img.ColorRgb8(120, 120, 120));
      late img.Image ergebnis;
      final stillstand = await laengsterStillstand(
        () async => ergebnis = await dienst.faerbe(bild),
      );
      expect(stillstand, lessThan(const Duration(milliseconds: 600)));
      expect(ergebnis.width, 6000);
      expect(ergebnis.getPixel(10, 10).r, closeTo(120, 1));
      await dienst.dispose();
    });
  });
}
