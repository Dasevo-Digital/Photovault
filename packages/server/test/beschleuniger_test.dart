import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:kern/auswertung/modelle.dart';
import 'package:onnxruntime_api/onnxruntime_api.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:photo_vault_server/src/beschleuniger.dart'
    show abweichung, langsamer, tempo;
import 'package:test/test.dart';

/// Beschleuniger (Issue #104): wie sie eingestellt werden, wann eine
/// Ausgabe als gleich gilt – und, wenn eine ONNX Runtime mit Modellen
/// angegeben ist, die Gegenprobe gegen die CPU am echten Modell.
///
/// Der letzte Teil braucht `PV_ONNXRUNTIME`, `PV_MODELLE` und
/// `PV_BESCHLEUNIGER` (auf einem Mac etwa `coreml`); ohne sie wird er
/// übersprungen.
void main() {
  group('PV_BESCHLEUNIGER', () {
    test('Vorgaben und Geräte', () {
      expect(Beschleuniger.aus(null).istCpu, isTrue);
      expect(Beschleuniger.aus(' ').istCpu, isTrue);
      expect(Beschleuniger.aus('openvino').name, 'OpenVINO:GPU');
      expect(
        Beschleuniger.aus('openvino:AUTO:GPU,CPU').name,
        'OpenVINO:AUTO:GPU,CPU',
      );
      expect(Beschleuniger.aus('CUDA').name, 'CUDA:0');
      expect(Beschleuniger.aus('cuda:1').name, 'CUDA:1');
      expect(Beschleuniger.aus('coreml').name, 'CoreML');
      expect(() => Beschleuniger.aus('rocm'), throwsFormatException);
      expect(() => Beschleuniger.aus('cuda:zwei'), throwsFormatException);
    });

    test('OpenVINO rechnet in der Genauigkeit des Modells', () {
      final o = Beschleuniger.aus('openvino').optionen(zwischenspeicher: '/z');
      expect(o, {
        'device_type': 'GPU',
        'precision': 'ACCURACY',
        'cache_dir': '/z',
      });
      expect(Beschleuniger.aus('cuda:1').optionen(), {'device_id': '1'});
    });
  });

  group('Gegenprobe', () {
    Float32List v(List<double> w) => Float32List.fromList(w);

    test('Rundungsunterschiede gehen durch', () {
      expect(abweichung(v([1, 2, 3]), v([1.00001, 1.99999, 3])), isNull);
      expect(abweichung(v([0, 0]), v([0, 0])), isNull);
      // Fast überall null (Texterkennung ohne Text): Rauschen von 1e-7
      // drückt den Kosinus, ändert aber nichts.
      expect(abweichung(v([1e-6, 2e-6, 0]), v([1.1e-6, 1.9e-6, 1e-7])), isNull);
    });

    test('langsamer als die CPU fällt durch, der erste Lauf zählt nicht', () {
      // Der erste Lauf übersetzt das Modell erst – danach schneller.
      expect(langsamer([(10000, 90000), (10000, 4000), (10000, 5000)]), isNull);
      expect(
        langsamer([(10000, 90000), (10000, 30000), (10000, 50000)]),
        'langsamer als die CPU: 30.0 ms gegen 10.0 ms im besten Lauf',
      );
      // Ein Ausreisser entscheidet nicht.
      expect(langsamer([(9000, 9000), (10000, 21000), (14000, 5700)]), isNull);
      expect(langsamer([(10000, 12000)]), contains('langsamer'));
      expect(langsamer(const []), isNull);
      final t = tempo([(10000, 90000), (12000, 4000), (8000, 6000)])!;
      expect((t.cpu, t.beschleunigt), (8.0, 4.0));
    });

    test('ein anderes Ergebnis nicht', () {
      expect(abweichung(v([1, 2, 3]), v([3, 2, 1])), contains('Kosinus'));
      expect(abweichung(v([1, 0, 0]), v([0, 0, 0])), contains('Kosinus'));
      // Gleiche Richtung, aber um mehr als ein Prozent verschoben.
      expect(abweichung(v([100, 0]), v([102, 0])), contains('Abweichung'));
      expect(abweichung(v([1, double.nan]), v([1, 2])), 'NaN');
    });
  });

  final u = Platform.environment;
  final ort = u['PV_ONNXRUNTIME'];
  final modelle = u['PV_MODELLE'];
  final b = Beschleuniger.aus(u['PV_BESCHLEUNIGER']);
  test(
    'am echten Modell: geprüft wird erst, dann rechnet der Beschleuniger',
    () async {
      final p = await FfiOnnxPlattform.starte(ort!, beschleuniger: b);
      OnnxRuntimePlatform.instance = p;
      final m = Modelle()..richteEin(modelle!);
      final clip = (await m.clipBildHalter.leihen())!;
      try {
        final bild = img.Image(width: 320, height: 240);
        for (var y = 0; y < 240; y++) {
          for (var x = 0; x < 320; x++) {
            bild.setPixelRgb(x, y, x % 256, y % 256, (x * y) % 256);
          }
        }
        expect(p.anbieterFuer('clip_image_encoder.onnx'), 'CPU');
        for (var i = 0; i < 3; i++) {
          await clip.embedImage(bild);
          expect(
            p.anbieterFuer('clip_image_encoder.onnx'),
            'CPU',
            reason: 'während der Gegenprobe zählt die CPU',
          );
        }
        final zustand = await p.zustand();
        final verworfen = (zustand['verworfen']! as Map).keys;
        if (verworfen.contains('clip_image_encoder.onnx')) {
          markTestSkipped('$b besteht die Gegenprobe für CLIP nicht');
          return;
        }
        expect(zustand['geprueft'], contains('clip_image_encoder.onnx'));
        await clip.embedImage(bild);
        expect(p.anbieterFuer('clip_image_encoder.onnx'), b.name);
      } finally {
        m.clipBildHalter.zurueckgeben();
        p.beende();
      }
    },
    skip: ort == null || modelle == null || b.istCpu
        ? 'PV_ONNXRUNTIME, PV_MODELLE und PV_BESCHLEUNIGER fehlen'
        : null,
  );
}
