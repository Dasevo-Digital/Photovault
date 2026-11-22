import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kern/services/clip_service.dart';
import 'package:kern/services/florence_captioning_service.dart';
import 'package:kern/services/modell_laden.dart';
import 'package:kern/services/ocr_service.dart';
import 'package:kern/services/translation_service.dart';
import 'package:kern/services/whisper_service.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'hilfen/onnx_attrappe.dart';

/// Modelle aus mehreren Teilen: Scheitert ein späterer Teil, bleiben die
/// schon geöffneten Sitzungen nicht offen liegen.
///
/// Vorher wurde jeder Teil nacheinander geöffnet und bei einem Fehler
/// nichts geschlossen. Der Halter versucht es beim nächsten Gebrauch
/// erneut – jeder Versuch liess eine weitere Sitzung mit Hunderten
/// Megabyte nativem Speicher zurück.
void main() {
  late Directory ordner;

  setUp(() {
    ordner = Directory.systemTemp.createTempSync('modell_laden_');
  });
  tearDown(() => ordner.deleteSync(recursive: true));

  OnnxAttrappe attrappe(Set<String> scheitertBei) {
    final a = OnnxAttrappe(scheitertBei: scheitertBei);
    OnnxRuntimePlatform.instance = a;
    return a;
  }

  Future<void> scheitertOhneRest(
    OnnxAttrappe a,
    Future<Object> Function() laden, {
    required int mindestensGeoeffnet,
  }) async {
    await expectLater(laden(), throwsA(anything));
    expect(a.geoeffnet, greaterThanOrEqualTo(mindestensGeoeffnet));
    expect(a.offeneSitzungen, isEmpty);
  }

  test(
    'Spracherkennung: Decoder scheitert, Encoder wird geschlossen',
    () async {
      final a = attrappe({'whisper_decoder.onnx'});
      await scheitertOhneRest(
        a,
        () => WhisperService.load(ordner.path),
        mindestensGeoeffnet: 2,
      );
    },
  );

  test('Spracherkennung: Vokabular fehlt, beide Sitzungen zu', () async {
    final a = attrappe(const {});
    await scheitertOhneRest(
      a,
      () => WhisperService.load(ordner.path),
      mindestensGeoeffnet: 2,
    );
  });

  test('Übersetzung: Decoder scheitert, Encoder wird geschlossen', () async {
    final a = attrappe({'translate_en_de_decoder.onnx'});
    await scheitertOhneRest(
      a,
      () => TranslationService.load(ordner.path, Uebersetzungsrichtung.enDe),
      mindestensGeoeffnet: 2,
    );
  });

  test(
    'Bildbeschreibung: dritter Teil scheitert, die ersten zwei zu',
    () async {
      final a = attrappe({'florence_encoder.onnx'});
      await scheitertOhneRest(
        a,
        () => FlorenceCaptioningService.load(ordner.path),
        mindestensGeoeffnet: 3,
      );
    },
  );

  test(
    'Texterkennung: Lesemodell scheitert, Erkennung wird geschlossen',
    () async {
      // Das Lesemodell wird vor dem Öffnen auf HardSwish-Knoten geprüft;
      // eine nicht deutbare Datei bleibt, wie sie ist.
      File('${ordner.path}/${OcrService.lesungsDatei}').writeAsBytesSync([1]);
      final a = attrappe({OcrService.lesungsDatei});
      await scheitertOhneRest(
        a,
        () => OcrService.load(ordner.path),
        mindestensGeoeffnet: 2,
      );
    },
  );

  test('CLIP-Text: Tokenizer fehlt, Encoder wird geschlossen', () async {
    final a = attrappe(const {});
    await scheitertOhneRest(
      a,
      () => ClipService.load(ordner.path, bild: false, text: true),
      mindestensGeoeffnet: 1,
    );
  });

  test('gelingt alles, bleiben die Sitzungen offen', () async {
    final a = attrappe(const {});
    final sitzungen = await sitzungenLaden(
      (oeffne) async => [await oeffne('a.onnx'), await oeffne('b.onnx')],
    );
    expect(sitzungen, hasLength(2));
    expect(a.offeneSitzungen, hasLength(2));
  });
}
