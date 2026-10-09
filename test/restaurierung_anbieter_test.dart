import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/restore_service.dart';

/// CoreML gibt es nur auf macOS – unter Linux und Windows lehnt das Plugin
/// den Anbieter ab, und die KI-Restaurierung scheiterte dort beim Laden.
void main() {
  test('macOS: CoreML, dann CPU', () {
    expect(restaurierungsAnbieter(macos: true), [
      OrtProvider.CORE_ML,
      OrtProvider.CPU,
    ]);
  });

  test('Linux und Windows: nur CPU', () {
    expect(restaurierungsAnbieter(macos: false), [OrtProvider.CPU]);
  });
}
