import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:kern/services/face_engine_service.dart';
import 'package:onnxruntime_api/onnxruntime_api.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:test/test.dart';

/// Die Gesichtserkennung mit dem echten YuNet (#461): Ein Panorama und ein
/// Hochformat kommen mit Rand in die Eingabe statt gestaucht, und die
/// Kästen landen an der Stelle des Gesichts.
///
/// Braucht die ONNX Runtime, die Modelle und ein Foto mit genau einem
/// Gesicht, das gut ein Drittel der Bildhöhe einnimmt:
///
///     PV_ONNXRUNTIME=…/libonnxruntime.1.28.3.dylib
///     PV_MODELLE=<Ordner mit face_detection_yunet.onnx>
///     PV_GESICHTSBILD=<Foto mit einem Gesicht>
///
/// Ohne sie wird übersprungen – Gesichtsbilder liegen nicht im Repo. Die
/// Rückrechnung selbst prüft test/face_postprocess_test.dart ohne Modell.
void main() {
  final u = Platform.environment;
  final runtime = u['PV_ONNXRUNTIME'];
  final modelle = u['PV_MODELLE'];
  final foto = u['PV_GESICHTSBILD'];
  final fehlt = runtime == null || modelle == null || foto == null
      ? 'PV_ONNXRUNTIME, PV_MODELLE und PV_GESICHTSBILD nicht gesetzt'
      : null;

  late FfiOnnxPlattform plattform;
  FaceEngineService? engine;
  late img.Image gesicht;
  late DetectedFace vorlage;

  setUpAll(() async {
    if (fehlt != null) return;
    plattform = await FfiOnnxPlattform.starte(runtime!);
    OnnxRuntimePlatform.instance = plattform;
    engine = await FaceEngineService.load(modelle!);
    gesicht = img.decodeImage(File(foto!).readAsBytesSync())!;
    final funde = await engine!.detectFaces(gesicht);
    expect(funde, hasLength(1), reason: 'das Foto soll ein Gesicht zeigen');
    vorlage = funde.single;
  });
  tearDownAll(() async {
    if (fehlt != null) return;
    await engine?.dispose();
    plattform.beende();
  });

  /// [gesicht] bei ([links], [oben]) auf einer grauen Fläche von
  /// [breite] × [hoehe] Punkten.
  img.Image aufFlaeche(int breite, int hoehe, int links, int oben) {
    final flaeche = img.Image(width: breite, height: hoehe)
      ..clear(img.ColorRgb8(128, 128, 128));
    return img.compositeImage(flaeche, gesicht, dstX: links, dstY: oben);
  }

  /// Wo der Kasten der Vorlage auf der Fläche liegen muss.
  DetectedFace erwartet(img.Image flaeche, int links, int oben) => DetectedFace(
    (links + vorlage.x * gesicht.width) / flaeche.width,
    (oben + vorlage.y * gesicht.height) / flaeche.height,
    vorlage.width * gesicht.width / flaeche.width,
    vorlage.height * gesicht.height / flaeche.height,
    1,
  );

  /// Das Gesicht ist gefunden, und zwar dort, wo es auf der Fläche liegt.
  ///
  /// Nicht auf den Punkt genau wie im Foto allein: In der Fläche kommt das
  /// Gesicht dreimal kleiner im Netz an, und YuNet zieht den Kasten dann
  /// etwas anders. Gestaucht fand es dort gar nichts.
  Future<void> pruefe(img.Image flaeche, int links, int oben) async {
    final funde = await engine!.detectFaces(flaeche);
    expect(funde, hasLength(1));
    final soll = erwartet(flaeche, links, oben);
    final ist = funde.single;
    final grund =
        'ist ${[ist.x, ist.y, ist.width, ist.height]}, '
        'soll ${[soll.x, soll.y, soll.width, soll.height]}';
    // Die Mitte höchstens ein Fünftel der Gesichtsgrösse daneben.
    final mitteX = (ist.x + ist.width / 2 - soll.x - soll.width / 2).abs();
    final mitteY = (ist.y + ist.height / 2 - soll.y - soll.height / 2).abs();
    expect(mitteX, lessThan(soll.width / 5), reason: grund);
    expect(mitteY, lessThan(soll.height / 5), reason: grund);
    // Und die Grösse in beiden Richtungen ähnlich – ein falsch
    // zurückgerechneter Kasten wäre in einer Richtung um den Faktor drei
    // daneben.
    expect(ist.width / soll.width, inInclusiveRange(0.7, 1.4), reason: grund);
    expect(ist.height / soll.height, inInclusiveRange(0.7, 1.4), reason: grund);
    // Die Augen liegen im Kasten.
    final punkte = ist.landmarks!;
    for (var i = 0; i < 2; i++) {
      expect(punkte[i * 2], inInclusiveRange(soll.x, soll.x + soll.width));
      expect(punkte[i * 2 + 1], inInclusiveRange(soll.y, soll.y + soll.height));
    }
  }

  test('Panorama: das Gesicht rechts aussen', () async {
    // Dreimal so breit wie das Foto. Gestaucht kam das Gesicht dreimal zu
    // schmal im Netz an.
    final breite = gesicht.width * 3, hoehe = gesicht.height;
    final links = breite - gesicht.width;
    await pruefe(aufFlaeche(breite, hoehe, links, 0), links, 0);
  }, skip: fehlt ?? false);

  test('Hochformat: das Gesicht unten', () async {
    final breite = gesicht.width, hoehe = gesicht.height * 3;
    final oben = hoehe - gesicht.height;
    await pruefe(aufFlaeche(breite, hoehe, 0, oben), 0, oben);
  }, skip: fehlt ?? false);
}
