import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/model_processing_state.dart';

void main() {
  test('merkt Modellwechsel und bestätigt erst den vollständigen Neulauf',
      () async {
    final temp = Directory.systemTemp.createTempSync('pv_model_state_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final state = ModelProcessingState(File(p.join(temp.path, 'state.json')));

    expect(await state.initialize({'clip': 'eins', 'ocr': 'eins'}), isEmpty);
    expect(await state.initialize({'clip': 'zwei', 'ocr': 'eins'}), {'clip'});

    await state.markCurrent('clip', 'zwei');
    expect(await state.initialize({'clip': 'zwei', 'ocr': 'eins'}), isEmpty);
  });

  test('beschädigter Stand wird als neuer Ausgangspunkt behandelt', () async {
    final temp = Directory.systemTemp.createTempSync('pv_model_state_test_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final file = File(p.join(temp.path, 'state.json'))..writeAsStringSync('{');
    final state = ModelProcessingState(file);

    expect(await state.initialize({'captions': 'eins'}), isEmpty);
    expect(await state.initialize({'captions': 'zwei'}), {'captions'});
  });
}
