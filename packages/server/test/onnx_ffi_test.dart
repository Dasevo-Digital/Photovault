import 'dart:io';
import 'dart:typed_data';

import 'package:onnxruntime_api/onnxruntime_api.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:test/test.dart';

/// ONNX Runtime über FFI, an einem winzigen Modell (`fixtures/klein.onnx`,
/// gebaut mit dem Python-Paket `onnx`): z = 2x + 1, w = y + 1, b = x > 0 –
/// je ein Ausgang mit Gleitkomma, Ganzzahl und Wahrheitswert.
///
/// Braucht die Bibliothek: `PV_ONNXRUNTIME=/pfad/libonnxruntime.so.1.28.3`.
/// Ohne sie wird übersprungen; auf dem Linux-Prüfrechner liegt sie im Bau
/// des Plugins.
void main() {
  final pfad = Platform.environment['PV_ONNXRUNTIME'];
  late FfiOnnxPlattform plattform;

  setUpAll(() async {
    if (pfad == null) return;
    plattform = await FfiOnnxPlattform.starte(pfad);
    OnnxRuntimePlatform.instance = plattform;
  });
  tearDownAll(() {
    if (pfad != null) plattform.beende();
  });

  test('rechnet das kleine Modell', () async {
    expect(plattform.fassung, startsWith('1.28'));
    expect(
      await OnnxRuntime().getAvailableProviders(),
      contains(OrtProvider.CPU),
    );
    final s = await OnnxRuntime().createSession(
      'test/fixtures/klein.onnx',
      options: OrtSessionOptions(intraOpNumThreads: 1, interOpNumThreads: 1),
    );
    expect(s.inputNames, ['x', 'y']);
    expect(s.outputNames, ['z', 'w', 'b']);
    final x = await OrtValue.fromList(
      Float32List.fromList([1, -2, 3, 0.5, -0.5, 0]),
      [2, 3],
    );
    final y = await OrtValue.fromList(Int64List.fromList([1, 2, 3]), [3]);
    final aus = await s.run({'x': x, 'y': y});
    expect(await aus['z']!.asFlattenedList(), [3, -3, 7, 2, 0, 1]);
    expect(aus['z']!.shape, [2, 3]);
    expect(await aus['w']!.asFlattenedList(), [2, 3, 4]);
    expect(await aus['b']!.asFlattenedList(), [
      true,
      false,
      true,
      true,
      false,
      false,
    ]);
    for (final v in [x, y, ...aus.values]) {
      await v.dispose();
    }

    // Eine Eingabe mit falscher Form: Die Meldung von ONNX Runtime kommt
    // als Fehler an, statt den Arbeitsfaden mitzureissen.
    final falsch = await OrtValue.fromList(Float32List(4), [2, 2]);
    await expectLater(
      s.run({
        'x': falsch,
        'y': await OrtValue.fromList(Int64List(3), [3]),
      }),
      throwsA(isA<StateError>()),
    );
    await s.close();
    // Danach geht es weiter.
    expect(await OnnxRuntime().getAvailableProviders(), isNotEmpty);
  }, skip: pfad == null ? 'PV_ONNXRUNTIME nicht gesetzt' : false);
}
