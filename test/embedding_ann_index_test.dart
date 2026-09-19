import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/embedding_ann_index.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('pv_ann_'));
  tearDown(() => temp.deleteSync(recursive: true));

  Float32List vector(double first, double second) {
    final values = Float32List(512);
    values[0] = first;
    values[1] = second;
    for (var i = 2; i < values.length; i++) {
      values[i] = ((i * 17) % 31 - 15) / 500;
    }
    return values;
  }

  test('speichert und lädt einen zu derselben Kennungsmenge passenden Index',
      () async {
    final embeddings = {
      'a': vector(1, 0),
      'b': vector(0, 1),
      'c': vector(-1, 0),
    };
    final file = File('${temp.path}/embedding_ann_v1.json');
    final index = EmbeddingAnnIndex.build(embeddings);
    await index.save(file);

    final loaded = await EmbeddingAnnIndex.load(file, ['a', 'b', 'c']);

    expect(loaded, isNotNull);
    expect(loaded!.candidates(embeddings['a']!, minimum: 1), contains('a'));
  });

  test('verwirft einen Index bei geänderter Asset-Menge', () async {
    final file = File('${temp.path}/embedding_ann_v1.json');
    final index = EmbeddingAnnIndex.build({'a': vector(1, 0)});
    await index.save(file);

    expect(await EmbeddingAnnIndex.load(file, ['a', 'b']), isNull);
  });
}
