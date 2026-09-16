import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/model_catalog.dart';
import 'package:photo_vault/services/model_download_service.dart';
import 'package:photo_vault/services/ocr_service.dart';
import 'package:photo_vault/services/onnx_hardswish.dart';

/// Dasselbe 126-Byte-Modell wie in `onnx_hardswish_test.dart`: zwei
/// HardSwish mit einem Relu dazwischen.
const _mitHardswish =
    'CAgSBXByb2JlOm0KGQoBeBIBYRoGZXJzdGVyIglIYXJkU3dpc2gKDAoBYRIBYiIEUmVsdQoRCg'
    'FiEgF5IglIYXJkU3dpc2gSBXByb2JlWhMKAXgSDgoMCAESCAoCCAEKAggEYhMKAXkSDgoMCAES'
    'CAoCCAEKAggEQgQKABAO';

void main() {
  late Directory ordner;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_ocr_umbau_');
  });

  tearDown(() async {
    if (await ordner.exists()) await ordner.delete(recursive: true);
  });

  Future<File> legeModellAn(Uint8List inhalt) async {
    final f = File('${ordner.path}/ocr_rec.onnx');
    await f.writeAsBytes(inhalt);
    return f;
  }

  test('legt beim ersten Laden eine Fassung ohne HardSwish daneben', () async {
    await legeModellAn(base64.decode(_mitHardswish));

    final pfad = await OcrService.lesemodellPfad(ordner.path);

    expect(pfad, endsWith(OcrService.lesungUmgebaut));
    final umgebaut = File(pfad).readAsBytesSync();
    expect(HardswishUmbau.zaehle(umgebaut), 0);
    expect(HardswishUmbau.knoten(umgebaut).map((k) => k.art),
        containsAll(['HardSigmoid', 'Mul', 'Relu']));
  });

  test('das heruntergeladene Modell bleibt unangetastet', () async {
    final quelle = await legeModellAn(base64.decode(_mitHardswish));
    final vorher = quelle.readAsBytesSync();

    await OcrService.lesemodellPfad(ordner.path);

    expect(quelle.readAsBytesSync(), vorher);
  });

  test('ein zweiter Aufruf baut nicht noch einmal um', () async {
    await legeModellAn(base64.decode(_mitHardswish));
    final pfad = await OcrService.lesemodellPfad(ordner.path);
    final ersteZeit = File(pfad).lastModifiedSync();

    await OcrService.lesemodellPfad(ordner.path);

    expect(File(pfad).lastModifiedSync(), ersteZeit);
  });

  test('ein neu geladenes Original wird neu umgebaut', () async {
    final quelle = await legeModellAn(base64.decode(_mitHardswish));
    final pfad = await OcrService.lesemodellPfad(ordner.path);
    await File(pfad)
        .setLastModified(DateTime.now().subtract(const Duration(days: 2)));
    quelle.setLastModifiedSync(DateTime.now());

    await OcrService.lesemodellPfad(ordner.path);

    expect(
      File(pfad)
          .lastModifiedSync()
          .isAfter(DateTime.now().subtract(const Duration(minutes: 1))),
      isTrue,
    );
  });

  test('ohne HardSwish wird gar nichts angelegt', () async {
    // Das bereits umgebaute Modell als Quelle: da ist nichts mehr zu tun.
    final ohne = HardswishUmbau.schreibeUm(base64.decode(_mitHardswish));
    await legeModellAn(ohne);

    final pfad = await OcrService.lesemodellPfad(ordner.path);

    expect(pfad, endsWith('ocr_rec.onnx'));
    expect(File('${ordner.path}/${OcrService.lesungUmgebaut}').existsSync(),
        isFalse);
  });

  test('eine unlesbare Datei führt zum Original, nicht zum Absturz', () async {
    await legeModellAn(Uint8List.fromList([0xff, 0xff, 0xff, 0xff]));

    final pfad = await OcrService.lesemodellPfad(ordner.path);

    expect(pfad, endsWith('ocr_rec.onnx'));
  });

  test('beim Löschen des Eintrags verschwindet auch die eigene Datei',
      () async {
    for (final f in ModelCatalog.ocrPaddle.files) {
      await File('${ordner.path}/${f.fileName}').writeAsBytes([1, 2, 3]);
    }
    final abgeleitet = File('${ordner.path}/${OcrService.lesungUmgebaut}');
    await abgeleitet.writeAsBytes(List.filled(500, 7));

    final dienst = ModelDownloadService(ordner.path);
    // Der eigene Anteil zählt beim belegten Platz mit …
    expect(dienst.belegteBytes(ModelCatalog.ocrPaddle), 3 * 3 + 500);

    await dienst.deleteEntry(ModelCatalog.ocrPaddle);

    // … und bleibt nicht liegen.
    expect(abgeleitet.existsSync(), isFalse);
    expect(dienst.belegteBytes(ModelCatalog.ocrPaddle), 0);
  });
}
