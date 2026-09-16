// ignore_for_file: avoid_print

import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/platform/desktop_image_tools.dart';
import 'package:photo_vault/services/videostandbilder.dart';

/// Holt aus einem echten Video die Standbilder, die
/// [videostandbildstellen] vorsieht, und belegt, dass es **verschiedene**
/// Bilder sind.
///
/// Das ist die Frage, an der die ganze Stufe haengt: Wenn `-ss` am
/// falschen Keyframe aufsetzt, liefern fuenf angeforderte Stellen fuenfmal
/// dasselbe Bild – und die Auswertung waere teurer als vorher und keinen
/// Deut besser.
///
/// Geht ueber `ffmpeg` und damit ueber denselben Weg wie Linux und
/// Windows. Der native Weg unter macOS (AVFoundation) laesst sich aus
/// einem Prueflauf heraus nicht ansprechen – dort fehlt der
/// Method-Channel.
///
///     PV_VIDEO=/pfad/zum/video.mov \
///     flutter test tool/videostandbilder_probe_test.dart
void main() {
  test('fuenf Stellen, fuenf verschiedene Bilder', () async {
    final pfad = Platform.environment['PV_VIDEO'];
    if (pfad == null) {
      markTestSkipped('PV_VIDEO noetig');
      return;
    }
    final datei = File(pfad);
    final dauer = await DesktopImageTools.videoDauer(datei);
    print('Laufzeit ${dauer?.toStringAsFixed(1)} s');
    final stellen = videostandbildstellen(dauer);
    print('${stellen.length} zusaetzliche Stellen: '
        '${[for (final s in stellen) s.toStringAsFixed(3)].join(', ')}');
    if (stellen.isEmpty) return;

    final pruefsummen = <String>[];
    final uhr = Stopwatch()..start();
    for (final stelle in stellen) {
      final bild = await DesktopImageTools.videoThumbnail(datei,
          maxDimension: 2048, anteil: stelle);
      expect(bild, isNotNull, reason: 'Stelle $stelle');
      final summe = sha256.convert(bild!.jpeg).toString().substring(0, 12);
      pruefsummen.add(summe);
      print('  ${(stelle * 100).toStringAsFixed(0).padLeft(3)} %  '
          '${(bild.jpeg.length / 1024).toStringAsFixed(0).padLeft(5)} kB  $summe');
    }
    uhr.stop();
    print('${stellen.length} Bilder in ${uhr.elapsedMilliseconds} ms');

    expect(pruefsummen.toSet(), hasLength(pruefsummen.length),
        reason: 'gleiche Bytes hiessen: es ist immer dasselbe Bild');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
