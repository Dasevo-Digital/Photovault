import '../services/clip_service.dart';
import '../services/eye_state_service.dart';
import '../services/face_engine_service.dart';
import '../services/florence_captioning_service.dart';
import '../services/modell_halter.dart';
import '../services/ocr_service.dart';
import '../services/translation_service.dart';
import '../services/whisper_service.dart';

/// Die KI-Modelle des Kerns, je hinter einem [ModellHalter]: geladen erst
/// beim ersten Gebrauch, wieder freigegeben, wenn niemand sie braucht.
///
/// Ein Feld je Modell und nicht eine Liste, weil die Auswertungen und die
/// Oberfläche ein bestimmtes Modell brauchen, nicht irgendeines. Die Felder
/// sind veränderlich: [richteEin] ersetzt sie nach einem Download, und
/// Tests setzen eigene ein.
class Modelle {
  ModellHalter<FaceEngineService> faceEngineHalter = _leer('Gesichtserkennung');
  ModellHalter<EyeStateService> eyeStateHalter = _leer('Augen-Zustand');
  ModellHalter<ClipService> clipBildHalter = _leer('CLIP-Bild');
  ModellHalter<ClipService> clipTextHalter = _leer('CLIP-Text');
  ModellHalter<FlorenceCaptioningService> captioningHalter = _leer(
    'Bildbeschreibung',
  );
  ModellHalter<WhisperService> spracherkennungHalter = _leer('Spracherkennung');
  ModellHalter<TranslationService> uebersetzungEnDeHalter = _leer(
    'translate-en-de',
  );
  ModellHalter<TranslationService> uebersetzungDeEnHalter = _leer(
    'translate-de-en',
  );
  ModellHalter<OcrService> ocrHalter = _leer('Texterkennung');

  /// Ein Halter für ein Modell, das (noch) nicht da ist.
  static ModellHalter<T> _leer<T>(String name) => ModellHalter<T>(
    name: name,
    installiert: false,
    laden: () => throw StateError('Die Modelle sind noch nicht eingerichtet.'),
    entsorgen: (_) async {},
  );

  /// Alle Halter – zum regelmässigen Freigeben und Abräumen.
  List<ModellHalter> get alle => [
    faceEngineHalter,
    eyeStateHalter,
    clipBildHalter,
    clipTextHalter,
    captioningHalter,
    spracherkennungHalter,
    uebersetzungEnDeHalter,
    uebersetzungDeEnHalter,
    ocrHalter,
  ];

  /// Legt für jedes Modell in [ordner] einen frischen Halter an und gibt
  /// die bisherigen zurück. Die bisherigen werden nicht entsorgt: Einer
  /// könnte gerade rechnen. Wer sie abräumt, wartet, bis sie frei sind
  /// (siehe [ModellHalter.freigebenWennUnbenutzt]).
  ///
  /// Frisch, weil ein Halter nur beim Anlegen nachsieht, ob sein Modell
  /// installiert ist – nach einem Download braucht es einen neuen.
  List<ModellHalter> richteEin(String ordner) {
    final bisher = alle;
    faceEngineHalter = ModellHalter<FaceEngineService>(
      name: 'Gesichtserkennung',
      installiert: FaceEngineService.isDetectionAvailable(ordner),
      // load() ist nullable, weil es intern denselben Dateicheck wie
      // isDetectionAvailable() wiederholt – der ist über `installiert`
      // bereits als true bekannt, daher unbedenklich entpackt.
      laden: () async => (await FaceEngineService.load(ordner))!,
      entsorgen: (s) => s.dispose(),
    );
    eyeStateHalter = ModellHalter<EyeStateService>(
      name: 'Augen-Zustand',
      installiert: EyeStateService.isAvailable(ordner),
      laden: () async => (await EyeStateService.load(ordner))!,
      entsorgen: (s) => s.dispose(),
    );
    // Beide Halter prüfen dieselben Dateien (isAvailable deckt Bild-,
    // Text-Encoder und Tokenizer gemeinsam ab), laden aber jeweils nur
    // ihren Teil – siehe ClipService.load.
    clipBildHalter = ModellHalter<ClipService>(
      name: 'CLIP-Bild',
      installiert: ClipService.isAvailable(ordner),
      laden: () => ClipService.load(ordner, bild: true, text: false),
      entsorgen: (s) => s.dispose(),
    );
    clipTextHalter = ModellHalter<ClipService>(
      name: 'CLIP-Text',
      installiert: ClipService.isAvailable(ordner),
      laden: () => ClipService.load(ordner, bild: false, text: true),
      entsorgen: (s) => s.dispose(),
    );
    uebersetzungEnDeHalter = ModellHalter<TranslationService>(
      name: 'translate-en-de',
      installiert: TranslationService.isAvailable(
        ordner,
        Uebersetzungsrichtung.enDe,
      ),
      laden: () => TranslationService.load(ordner, Uebersetzungsrichtung.enDe),
      entsorgen: (s) => s.dispose(),
    );
    uebersetzungDeEnHalter = ModellHalter<TranslationService>(
      name: 'translate-de-en',
      installiert: TranslationService.isAvailable(
        ordner,
        Uebersetzungsrichtung.deEn,
      ),
      laden: () => TranslationService.load(ordner, Uebersetzungsrichtung.deEn),
      entsorgen: (s) => s.dispose(),
    );
    ocrHalter = ModellHalter<OcrService>(
      name: 'Texterkennung',
      installiert: OcrService.isAvailable(ordner),
      laden: () => OcrService.load(ordner),
      entsorgen: (s) => s.dispose(),
    );
    captioningHalter = ModellHalter<FlorenceCaptioningService>(
      name: 'Bildbeschreibung',
      installiert: FlorenceCaptioningService.isAvailable(ordner),
      laden: () => FlorenceCaptioningService.load(ordner),
      entsorgen: (s) => s.dispose(),
    );
    spracherkennungHalter = ModellHalter<WhisperService>(
      name: 'Spracherkennung',
      installiert: WhisperService.isAvailable(ordner),
      laden: () => WhisperService.load(ordner),
      entsorgen: (s) => s.dispose(),
    );
    return bisher;
  }
}
