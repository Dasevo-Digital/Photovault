// ignore_for_file: avoid_print
// Rechnen die Modelle über FFI dasselbe wie in der App über das Plugin?
//
// Dieselben Proben wie `integration_test/onnx_wechsel_test.dart` – soweit
// die Modelle im Kern liegen –, mit denselben Prüfbildern, aber über
// FfiOnnxPlattform. Verglichen wird mit dem Abdruck, den jener Test mit
// dem Plugin geschrieben hat.
//
//   PV_ONNXRUNTIME=…/libonnxruntime.so.1.28.3 PV_MODELLE=~/pv_probe_modelle \
//   PV_ABDRUCK_VORHER=~/pv_abdruck_kern.json dart run tool/abdruck_ffi.dart
//
// Mit PV_WHISPER=<Ordner mit de1.wav und den Whisper-Modellen> hört es
// zusätzlich die Sprachprobe ab.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:kern/services/clip_service.dart';
import 'package:kern/services/eye_state_service.dart';
import 'package:kern/services/face_engine_service.dart';
import 'package:kern/services/florence_captioning_service.dart';
import 'package:kern/services/kratzermodell.dart';
import 'package:kern/services/ocr_service.dart';
import 'package:kern/services/translation_service.dart';
import 'package:kern/services/whisper_service.dart';
import 'package:onnxruntime_api/onnxruntime_api.dart';
import 'package:photo_vault_server/photo_vault_server.dart';

// --- wörtlich aus integration_test/onnx_wechsel_test.dart ------------------

img.Image _pruefbild(int kante) {
  final b = img.Image(width: kante, height: kante);
  for (var y = 0; y < kante; y++) {
    for (var x = 0; x < kante; x++) {
      b.setPixelRgb(x, y, (x * 7 + y * 3) % 256, (x * 5) % 256, (y * 11) % 256);
    }
  }
  return b;
}

img.Image _schriftbild() {
  final b = img.Image(width: 640, height: 200)
    ..clear(img.ColorRgb8(245, 245, 240));
  img.drawString(
    b,
    'PHOTO VAULT 2026',
    font: img.arial48,
    x: 30,
    y: 30,
    color: img.ColorRgb8(10, 10, 10),
  );
  img.drawString(
    b,
    'Bahnhofstrasse 12',
    font: img.arial48,
    x: 30,
    y: 110,
    color: img.ColorRgb8(10, 10, 10),
  );
  return b;
}

List<double> _stichprobe(List<double> v) {
  final schritt = math.max(1, v.length ~/ 512);
  return [for (var i = 0; i < v.length; i += schritt) v[i]];
}

List<double> _kleinbild(img.Image b) {
  final k = img.copyResize(
    b,
    width: 16,
    height: 16,
    interpolation: img.Interpolation.average,
  );
  return [
    for (final px in k) ...[px.r.toDouble(), px.g.toDouble(), px.b.toDouble()],
  ];
}

// ---------------------------------------------------------------------------

Int16List _wav(File datei) {
  final b = datei.readAsBytesSync();
  final d = ByteData.sublistView(b);
  var i = 12;
  while (i + 8 <= b.length) {
    final name = String.fromCharCodes(b.sublist(i, i + 4));
    final laenge = d.getUint32(i + 4, Endian.little);
    if (name == 'data') {
      return Int16List.fromList([
        for (var k = 0; k < laenge ~/ 2; k++)
          d.getInt16(i + 8 + k * 2, Endian.little),
      ]);
    }
    i += 8 + laenge + (laenge.isOdd ? 1 : 0);
  }
  throw StateError('kein data-Chunk');
}

Future<void> main() async {
  final u = Platform.environment;
  final plattform = await FfiOnnxPlattform.starte(u['PV_ONNXRUNTIME']!);
  OnnxRuntimePlatform.instance = plattform;
  final modelle = u['PV_MODELLE']!;
  print('ONNX Runtime ${plattform.fassung} über FFI, Modelle in $modelle');

  final abdruck = <String, Object>{};
  Future<void> miss(String name, Future<Object?> Function() rechne) async {
    final uhr = Stopwatch()..start();
    final e = await rechne();
    if (e == null) {
      print('$name: nicht installiert');
      return;
    }
    abdruck[name] = e;
    print('$name: ${uhr.elapsedMilliseconds} ms');
  }

  final bild = _pruefbild(512);
  await miss('clip_bild', () async {
    if (!ClipService.isAvailable(modelle)) return null;
    final d = await ClipService.load(modelle, text: false);
    final v = await d.embedImage(bild);
    await d.dispose();
    return _stichprobe(v);
  });
  await miss('clip_text', () async {
    if (!ClipService.isAvailable(modelle)) return null;
    final d = await ClipService.load(modelle, bild: false);
    final v = await d.embedText('a photo of a red bicycle in 1985');
    await d.dispose();
    return _stichprobe(v);
  });
  final gesichter = await FaceEngineService.load(modelle);
  await miss('gesicht_suche', () async {
    if (gesichter == null) return null;
    final f = await gesichter.detectFaces(bild, scoreThreshold: 0.01);
    return [
      f.length.toDouble(),
      for (final g in f.take(3)) ...[g.x, g.y, g.width, g.height, g.score],
    ];
  });
  final kasten = DetectedFace(
    0.25,
    0.25,
    0.5,
    0.5,
    1,
    landmarks: [0.38, 0.4, 0.62, 0.4, 0.5, 0.52, 0.4, 0.62, 0.6, 0.62],
  );
  await miss('gesicht_abdruck', () async {
    if (gesichter == null || !gesichter.canEmbed) return null;
    final v = await gesichter.embedFace(_pruefbild(256), kasten);
    return v == null ? null : _stichprobe(v);
  });
  await gesichter?.dispose();
  await miss('augen', () async {
    final d = await EyeStateService.load(modelle);
    if (d == null) return null;
    final s = await d.eyeOpenScore(_pruefbild(256), kasten);
    await d.dispose();
    return [s ?? -1];
  });
  await miss('florence', () async {
    if (!FlorenceCaptioningService.isAvailable(modelle)) return null;
    final d = await FlorenceCaptioningService.load(modelle);
    final s = await d.generateCaption(bild);
    await d.dispose();
    return s;
  });
  for (final richtung in Uebersetzungsrichtung.values) {
    await miss('uebersetzung_${richtung.name}', () async {
      if (!TranslationService.isAvailable(modelle, richtung)) return null;
      final d = await TranslationService.load(modelle, richtung);
      final s = await d.translate(
        richtung == Uebersetzungsrichtung.enDe
            ? 'a red bicycle in front of a stone wall'
            : 'ein rotes Fahrrad vor einer Steinmauer',
      );
      await d.dispose();
      return s;
    });
  }
  await miss('ocr', () async {
    if (!OcrService.isAvailable(modelle)) return null;
    final d = await OcrService.load(modelle);
    final s = await d.erkenne(_schriftbild());
    await d.dispose();
    return s.map((t) => t.text).join(' | ');
  });
  await miss('kratzer', () async {
    if (!KratzerModellService.isAvailable(modelle)) return null;
    final d = await KratzerModellService.load(modelle);
    final quelle = _pruefbild(512);
    img.drawLine(
      quelle,
      x1: 40,
      y1: 60,
      x2: 470,
      y2: 300,
      color: img.ColorRgb8(250, 250, 250),
      thickness: 2,
    );
    final f = await d.suche(quelle);
    await d.dispose();
    return [f.kratzer.toDouble(), f.staub.toDouble(), ..._kleinbild(f.maske)];
  });

  final whisper = u['PV_WHISPER'];
  if (whisper != null && WhisperService.isAvailable(whisper)) {
    final w = await WhisperService.load(whisper);
    final uhr = Stopwatch()..start();
    final t = await w.transkribiere(_wav(File('$whisper/de1.wav')));
    print(
      'whisper de1 (${uhr.elapsedMilliseconds} ms): [${t?.sprache}] ${t?.text}',
    );
    await w.dispose();
  }

  // Vergleich mit dem Abdruck des Plugins.
  final vorherDatei = u['PV_ABDRUCK_VORHER'];
  var abweichend = 0;
  if (vorherDatei != null) {
    final vorher =
        ((jsonDecode(File(vorherDatei).readAsStringSync()) as Map)['abdruck']
                as Map)
            .cast<String, Object?>();
    print('\nVergleich mit $vorherDatei:');
    for (final e in abdruck.entries) {
      final alt = vorher[e.key];
      if (alt == null) {
        print('  ${e.key}: im Plugin-Abdruck nicht dabei');
        continue;
      }
      if (e.value is String) {
        final gleich = e.value == alt;
        if (!gleich) abweichend++;
        print(
          '  ${e.key}: ${gleich ? 'gleich' : 'ANDERS: "${e.value}" statt "$alt"'}',
        );
        continue;
      }
      final a = (e.value as List).cast<num>();
      final b = (alt as List).cast<num>();
      var groesste = 0.0;
      for (var i = 0; i < math.min(a.length, b.length); i++) {
        groesste = math.max(groesste, (a[i] - b[i]).abs().toDouble());
      }
      final gleich = a.length == b.length && groesste == 0;
      if (!gleich) abweichend++;
      print(
        '  ${e.key}: ${gleich ? 'bitgleich' : 'ANDERS (Länge ${a.length}/${b.length}, grösste Abweichung $groesste)'}',
      );
    }
  }
  plattform.beende();
  exit(abweichend == 0 ? 0 : 1);
}
