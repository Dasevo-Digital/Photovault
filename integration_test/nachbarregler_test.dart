// ignore_for_file: avoid_print
// Rechnen Linux, Windows und macOS Schärfe, Rauschminderung, Klarheit und
// Vignette gleich?
//
// Unter macOS rechnet Core Image das gespeicherte Ergebnis, unter Linux
// und Windows der GPU-Weg (lib/services/develop_nachbarn.dart). Der hat
// seine Formeln aus Messungen an Core Image; ob sie im laufenden Programm
// dasselbe ergeben, zeigt nur der Vergleich an denselben Pixeln.
//
// - macOS: beide Wege an der Prüftafel (test/hilfen/entwickeln_tafel.dart)
//   rechnen und vergleichen. Die Core-Image-Ergebnisse legt der Test im
//   Temp-Ordner seines Sandkastens ab und nennt den Pfad (REFERENZ …) –
//   daraus entstehen die Referenzbilder unter
//   test/fixtures/entwickeln_referenz.
// - Linux, Windows: den GPU-Weg gegen diese Referenzbilder vergleichen,
//   PV_REFERENZ_EIN=<Ordner>.
//
// Dazu die Renderzeit: Speichern (Kante 4096) und Vorschau (1600), je
// neutral und mit allen vier Reglern.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/develop_render.dart';
import 'package:photo_vault/services/native_image_converter.dart';

import '../test/hilfen/entwickeln_tafel.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late File tafel;
  late File maske;

  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('pv_nachbarn_');
    tafel = File(p.join(temp.path, 'tafel.png'))
      ..writeAsBytesSync(img.encodePng(entwickelnTafel()));
    maske = File(p.join(temp.path, 'maske.png'))
      ..writeAsBytesSync(img.encodePng(entwickelnTafelMaske()));
  });
  tearDownAll(() => temp.deleteSync(recursive: true));

  Future<img.Image> gpu(
    DevelopAdjustments a, {
    List<MaskAdjustmentLayer> masks = const [],
  }) async => img.decodeJpg(
    (await DevelopRender.rendere(
      tafel,
      adjustments: a,
      masks: masks,
      quality: 100,
    ))!,
  )!;

  test('GPU-Weg gegen Core Image', () async {
    final faelle = <String, (DevelopAdjustments, List<MaskAdjustmentLayer>)>{
      for (final e in entwickelnFaelle.entries) e.key: (e.value, const []),
      'maske': (
        maskenfallGlobal,
        [
          MaskAdjustmentLayer(
            maskFilePath: maske.path,
            adjustments: maskenfallMaske,
          ),
        ],
      ),
    };
    final aus = Directory(p.join(Directory.systemTemp.path, 'pv_referenz'));
    if (Platform.isMacOS) {
      aus.createSync(recursive: true);
      print('REFERENZ ${aus.path}');
    }
    final ein = Platform.environment['PV_REFERENZ_EIN'];
    if (!Platform.isMacOS && ein == null) {
      print('VERGLEICH ohne PV_REFERENZ_EIN nicht möglich – übersprungen');
      return;
    }
    final neutral = await gpu(const DevelopAdjustments());

    for (final MapEntry(key: name, value: (werte, masks)) in faelle.entries) {
      final img.Image referenz;
      if (Platform.isMacOS) {
        final bytes = await NativeImageConverter.developImage(
          tafel,
          adjustments: werte,
          masks: masks,
          maxDimension: 1600,
          quality: 1.0,
        );
        referenz = img.decodeJpg(bytes!)!;
        File(p.join(aus.path, '$name.jpg')).writeAsBytesSync(bytes);
      } else {
        referenz = img.decodeJpg(
          File(p.join(ein!, '$name.jpg')).readAsBytesSync(),
        )!;
      }
      final ergebnis = await gpu(werte, masks: masks);
      if (Platform.isMacOS) {
        File(
          p.join(aus.path, 'gpu_$name.png'),
        ).writeAsBytesSync(img.encodePng(ergebnis));
      }
      final d = abweichung(ergebnis, referenz);
      final ohne = abweichung(neutral, referenz);
      print(
        'VERGLEICH ${Platform.operatingSystem} $name: '
        'mittel ${d.mittel.toStringAsFixed(2)}, grösste ${d.groesste} '
        '(ohne Filter ${ohne.mittel.toStringAsFixed(2)})',
      );
      expect(
        d.mittel,
        lessThan(ohne.mittel * 0.35),
        reason:
            '$name: der GPU-Weg liegt kaum näher an Core Image als gar nichts',
      );
    }
  });

  test('Renderzeit', () async {
    final bild = img.Image(width: 6000, height: 4000);
    for (var y = 0; y < 4000; y++) {
      for (var x = 0; x < 6000; x++) {
        // Verlauf mit feinem Muster, damit die Filter etwas zu tun haben.
        final muster = ((x ~/ 3 + y ~/ 3) % 2) * 24;
        bild.setPixelRgb(
          x,
          y,
          (x * 200) ~/ 6000 + muster,
          (y * 200) ~/ 4000 + muster,
          ((x + y) * 200) ~/ 10000 + muster,
        );
      }
    }
    final quelle = File(p.join(temp.path, 'gross.jpg'))
      ..writeAsBytesSync(img.encodeJpg(bild, quality: 90));
    const alle = DevelopAdjustments(
      sharpness: 0.5,
      noiseReduction: 0.3,
      clarity: 0.5,
      vignette: 0.5,
    );
    for (final kante in [4096, 1600]) {
      for (final (name, werte) in [
        ('neutral', const DevelopAdjustments()),
        ('alle vier', alle),
        ('Schärfe', const DevelopAdjustments(sharpness: 0.5)),
        ('Rauschen', const DevelopAdjustments(noiseReduction: 0.3)),
        ('Klarheit', const DevelopAdjustments(clarity: 0.5)),
        ('Vignette', const DevelopAdjustments(vignette: 0.5)),
      ]) {
        // Das schnellste von drei Läufen: Die Laptop-Prozessoren der
        // Testrechner drosseln unter Dauerlast.
        var bester = 1 << 30;
        for (var lauf = 0; lauf < 3; lauf++) {
          final uhr = Stopwatch()..start();
          final bytes = await DevelopRender.rendere(
            quelle,
            adjustments: werte,
            maxDimension: kante,
            quality: 92,
          );
          uhr.stop();
          expect(bytes, isNotNull);
          if (uhr.elapsedMilliseconds < bester) {
            bester = uhr.elapsedMilliseconds;
          }
        }
        print(
          'NACHBARZEIT ${Platform.operatingSystem} Kante $kante $name: '
          '$bester ms',
        );
      }
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}
