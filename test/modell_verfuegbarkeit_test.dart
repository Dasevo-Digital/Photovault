import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kern/services/clip_service.dart';
import 'package:kern/services/eye_state_service.dart';
import 'package:kern/services/face_engine_service.dart';
import 'package:kern/services/florence_captioning_service.dart';
import 'package:kern/services/kratzermodell.dart';
import 'package:kern/services/model_catalog.dart';
import 'package:kern/services/model_download_service.dart';
import 'package:kern/services/ocr_service.dart';
import 'package:kern/services/translation_service.dart';
import 'package:kern/services/whisper_service.dart';
import 'package:photo_vault/services/inpainting_service.dart';
import 'package:photo_vault/services/kolorieren.dart';
import 'package:photo_vault/services/restore_service.dart';
import 'package:photo_vault/services/segmentation_service.dart';

/// Die Dienste fragen vor dem Laden, ob ihr Modell da ist – und müssen
/// dabei dasselbe meinen wie die Modellkarte in den Einstellungen.
///
/// Bis zur Prüfung KI-014 fragten sie nur, ob die Datei existiert. Mit
/// einer abgeschnittenen YuNet-Datei zeigte die Karte richtig
/// „Herunterladen“, „Gesichtserkennung aktiv“ meldete aber weiter „Nur
/// Erkennung aktiv“, und die Analyse hielt das Modell für einsatzbereit.
void main() {
  late Directory dir;
  late ModelDownloadService dienst;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pv_verfuegbar_');
    dienst = ModelDownloadService(dir.path);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// Als Loch-Datei: Geprüft wird die Länge, geschrieben werden müssen
  /// die Attrappen nicht.
  void lege(String name, int laenge) {
    final datei = File('${dir.path}/$name').openSync(mode: FileMode.write);
    datei.truncateSync(laenge);
    datei.closeSync();
  }

  void installiere(ModelCatalogEntry eintrag) {
    for (final f in eintrag.files) {
      lege(f.fileName, f.bytes);
    }
  }

  final pruefungen = <String, (ModelCatalogEntry, bool Function(String))>{
    'YuNet': (
      ModelCatalog.faceDetection,
      FaceEngineService.isDetectionAvailable,
    ),
    'SFace': (
      ModelCatalog.faceRecognition,
      FaceEngineService.isRecognitionAvailable,
    ),
    'Augen': (ModelCatalog.eyeState, EyeStateService.isAvailable),
    'CLIP': (ModelCatalog.clip, ClipService.isAvailable),
    'Florence': (
      ModelCatalog.captioningFlorence,
      FlorenceCaptioningService.isAvailable,
    ),
    'Whisper': (ModelCatalog.spracherkennung, WhisperService.isAvailable),
    'OCR': (ModelCatalog.ocrPaddle, OcrService.isAvailable),
    'Kratzer': (ModelCatalog.kratzer, KratzerModellService.isAvailable),
    'EN→DE': (
      ModelCatalog.translationEnDe,
      (o) => TranslationService.isAvailable(o, Uebersetzungsrichtung.enDe),
    ),
    'DE→EN': (
      ModelCatalog.translationDeEn,
      (o) => TranslationService.isAvailable(o, Uebersetzungsrichtung.deEn),
    ),
    'LaMa': (ModelCatalog.inpainting, InpaintingService.isAvailable),
    'DDColor': (ModelCatalog.kolorieren, KolorierService.isAvailable),
    'Real-ESRGAN': (ModelCatalog.neuralRestore, RestoreService.isAvailable),
    'NAFNet': (ModelCatalog.entrauschen, Entrauschdienst.isAvailable),
    'SAM': (ModelCatalog.segmentation, SegmentationService.isAvailable),
  };

  test('eine abgeschnittene YuNet-Datei macht die Erkennung nicht bereit', () {
    final f = ModelCatalog.faceDetection.files.single;
    lege(f.fileName, f.bytes - 100);
    expect(dienst.isEntryInstalled(ModelCatalog.faceDetection), isFalse);
    expect(FaceEngineService.isDetectionAvailable(dir.path), isFalse);

    lege(f.fileName, f.bytes);
    expect(FaceEngineService.isDetectionAvailable(dir.path), isTrue);
  });

  for (final MapEntry(key: name, value: (eintrag, verfuegbar))
      in pruefungen.entries) {
    test('$name: Dienst und Modellkarte meinen dasselbe', () {
      expect(verfuegbar(dir.path), isFalse, reason: 'ohne Dateien');

      installiere(eintrag);
      expect(dienst.isEntryInstalled(eintrag), isTrue);
      expect(verfuegbar(dir.path), isTrue, reason: 'vollständig');

      for (final f in eintrag.files) {
        lege(f.fileName, f.bytes - 1);
        expect(dienst.isEntryInstalled(eintrag), isFalse);
        expect(
          verfuegbar(dir.path),
          isFalse,
          reason: '${f.fileName} abgeschnitten',
        );
        lege(f.fileName, f.bytes);
      }
    });
  }

  test('eine Datei, die der Katalog nicht kennt, genügt, wenn sie da ist', () {
    expect(ModelCatalog.dateiVollstaendig(dir.path, 'eigen.onnx'), isFalse);
    lege('eigen.onnx', 3);
    expect(ModelCatalog.dateiVollstaendig(dir.path, 'eigen.onnx'), isTrue);
  });
}
