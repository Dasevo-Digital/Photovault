// ignore_for_file: avoid_print
// Stellt den Fehler nach: ein Modell mit genau einem Rechenschritt.
// Erwartet die Modelle aus modelle_bauen.py unter $HOME/ocr_modelle/.
//
// Erwartet (ONNX-Referenz, python onnxruntime):
//   HardSwish    -0      -0      -0.3333 -0.2083 0      0.2917 0.6667 3
//   HardSigmoid   0       0       0.3     0.4    0.5    0.6    0.7    1
//   Sigmoid       0.018   0.0474  0.2689  0.3775 0.5    0.6225 0.7311 0.9526
//   Relu          0       0       0       0      0      0.5    1      3
//   Elu          -0.9817 -0.9502 -0.6321 -0.3935 0      0.5    1      3
//   Softplus      0.0181  0.0486  0.3133  0.4741 0.6931 0.9741 1.3133 3.0486
//   Celu         -0.9817 -0.9502 -0.6321 -0.3935 0      0.5    1      3
//   Mish         -0.0726 -0.1456 -0.3034 -0.2207 0      0.3752 0.8651 2.9865
//
// Unter Linux kommt bei HardSwish stattdessen achtmal null heraus; alle
// uebrigen Schritte stimmen.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('ein Rechenschritt je Modell', () async {
    final ordner = '${Platform.environment['HOME']}/ocr_modelle';
    final x =
        Float32List.fromList([-4.0, -3.0, -1.0, -0.5, 0.0, 0.5, 1.0, 3.0]);

    for (final op in [
      'hardswish',
      'hardsigmoid',
      'sigmoid',
      'relu',
      'elu',
      'softplus',
      'celu',
      'mish',
    ]) {
      final datei = '$ordner/nur_$op.onnx';
      if (!File(datei).existsSync()) {
        print('$op: Modell fehlt ($datei)');
        continue;
      }
      final s = await OnnxRuntime().createSession(datei);
      final t = await OrtValue.fromList(x, [1, 8]);
      final aus = await s.run({s.inputNames.first: t});
      final roh = (await aus.values.first.asFlattenedList()).cast<num>();
      print('${op.padRight(12)} '
          '${roh.map((v) => v.toDouble().toStringAsFixed(4)).join(' ')}');
      for (final v in aus.values) {
        await v.dispose();
      }
      await t.dispose();
      await s.close();
    }
  });
}
