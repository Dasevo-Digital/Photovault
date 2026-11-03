import 'dart:async';
import 'dart:math' as math;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

import 'tile_processor.dart';
import 'package:kern/services/modellthreads.dart';

/// Kapselt On-Device-Inferenz mit Real-ESRGAN x4 (siehe model_catalog.dart:
/// `neuralRestore`) für KI-Restaurierung (Hochskalieren + Entrauschen in
/// einem Durchgang, siehe RestoreQueueService/RestoreJobs). Anders als bei
/// SAM/CLIP EIN einzelnes Modell mit dynamischer Eingabegröße `[1,3,h,w]`,
/// Ausgabe `[1,3,4h,4w]` – siehe [restore] für die Kachel-Verarbeitung
/// (das Modell selbst kennt keine ganzen Fotos, nur einzelne Kacheln).
///
/// Real per Python `onnxruntime`-Benchmark auf diesem Gerät gemessen: eine
/// 512×512-Kachel dauert ~20,1s auf der CPU, ~4,8s mit dem CoreML Execution
/// Provider (2 von 1024 Graph-Knoten sind nicht CoreML-fähig und fallen auf
/// CPU zurück) – [load] fordert CoreML deshalb explizit an, mit CPU als
/// Fallback, falls CoreML auf dem jeweiligen Gerät nicht verfügbar ist.
/// Womit Real-ESRGAN rechnet: auf macOS mit CoreML, sonst auf der CPU.
///
/// **CoreML nur auf macOS.** Die Liste galt früher für alle Plattformen;
/// unter Linux und Windows lehnt das Plugin einen unbekannten Anbieter
/// aber ab, statt ihn zu überspringen („Provider is not supported:
/// CORE_ML“). Die KI-Restaurierung scheiterte dort schon beim Laden des
/// Modells – aufgefallen bei der Probe zu Issue #14 unter Linux.
List<OrtProvider> restaurierungsAnbieter({bool? macos}) => [
  if (macos ?? Platform.isMacOS) OrtProvider.CORE_ML,
  OrtProvider.CPU,
];

class RestoreService {
  RestoreService._(this._session);

  final OrtSession _session;

  /// Kantenlänge einer Kachel. Mit CoreML (macOS) 512, auf der CPU 256:
  /// Das Netz rechnet intern in vierfacher Grösse, und auf der CPU hält
  /// ONNX Runtime die Zwischenergebnisse einer 512er-Kachel gleichzeitig –
  /// gemessen bis 5,8 GB, worauf Linux die App auf einem Rechner mit 8 GB
  /// beendete.
  static int kachelGroesse({bool? macos}) =>
      (macos ?? Platform.isMacOS) ? 512 : 256;
  static const overlap = 16;
  static const scaleFactor = 4;

  static bool isAvailable(String modelsDir) =>
      File('$modelsDir/real_esrgan_x4.onnx').existsSync();

  static Future<RestoreService> load(String modelsDir) async {
    final ort = OnnxRuntime();
    final session = await ort.createSession(
      '$modelsDir/real_esrgan_x4.onnx',
      options: modelloptionen(providers: restaurierungsAnbieter()),
    );
    return RestoreService._(session);
  }

  /// Hochskaliert+entrauscht [source] um Faktor [scaleFactor] – läuft
  /// kachelweise (siehe [processInTiles]), typischerweise mehrere Minuten
  /// für ein reales Foto. [onProgress] meldet nach jeder Kachel
  /// `done`/`total` (für RestoreJobs.tilesDone/tilesTotal), [isCancelled]
  /// wird zwischen Kacheln geprüft.
  Future<img.Image> restore(
    img.Image source, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) {
    return processInTiles(
      source,
      tileSize: kachelGroesse(),
      overlap: overlap,
      scaleFactor: scaleFactor,
      infer: (kachel) => _rechneKachel(_session, kachel),
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }

  /// Startet die Restaurierung des JPEG [quelle] **in einem eigenen
  /// Isolat** und gibt den laufenden [Restaurierungslauf] zurück.
  ///
  /// **Warum ein eigenes Isolat** (Issue #14). Das Modell selbst rechnet
  /// nicht in Dart, aber alles darum herum: das Foto dekodieren, je Kachel
  /// 4,2 Millionen Bildpunkte auspacken und überblenden, am Ende ein Bild
  /// von 49 Megapixeln zusammensetzen und als JPEG schreiben. Auf dem
  /// Faden der Oberfläche stand die App dabei jedes Mal sekundenlang. Hier
  /// bekommt die Oberfläche nur noch den Fortschritt zu sehen; das Modell
  /// ruft das Isolat selbst über den Plattformkanal auf (seit Flutter 3.7
  /// aus Hintergrund-Isolaten erlaubt).
  Restaurierungslauf starteJpeg(
    Uint8List quelle, {
    int quality = 92,
    void Function(int done, int total)? onProgress,
  }) {
    return _starte(
      _session,
      quelle,
      quality: quality,
      onProgress: onProgress,
      art: (
        kachel: kachelGroesse(),
        overlap: overlap,
        massstab: scaleFactor,
        vielfaches: 1,
        staerke: 1.0,
      ),
    );
  }

  Future<void> dispose() async {
    await _session.close();
  }
}

/// Was den einen Lauf vom anderen unterscheidet: Kachelgrösse und
/// Überlappung, wie stark das Netz vergrössert, auf welches Vielfache eine
/// Kachel aufzufüllen ist, und wie viel vom Ergebnis über das Original
/// kommt (1 = alles).
typedef _Laufart = ({
  int kachel,
  int overlap,
  int massstab,
  int vielfaches,
  double staerke,
});

/// **KI-Entrauschen** mit NAFNet (siehe model_catalog.dart: `entrauschen`,
/// #275) – derselbe Weg wie [RestoreService]: kachelweise in einem eigenen
/// Isolat, nur ohne Vergrösserung. Die Kanten jeder Kachel werden auf ein
/// Vielfaches von 16 aufgefüllt (das verlangt der Export), danach wieder
/// abgeschnitten.
///
/// **Stärke.** NAFNet ist auf das Rauschen von fünf Telefonen trainiert und
/// glättet feine Strukturen mit – an einem rauschfreien Testbild kamen nur
/// 28 dB zurück. Das Ergebnis wird deshalb mit dem Original gemischt; der
/// Regler steht anfangs auf 70 %.
///
/// **Nur auf der CPU.** Mit CoreML und dynamischer Eingabe dauerte eine
/// Kachel von 512 Pixeln 42 bis 52 s statt 0,5 s.
class Entrauschdienst {
  Entrauschdienst._(this._session);

  final OrtSession _session;

  static const datei = 'denoise_nafnet_sidd_w32.onnx';
  static const kachelGroesse = 512;
  static const overlap = 32;

  static bool isAvailable(String modelsDir) =>
      File('$modelsDir/$datei').existsSync();

  static Future<Entrauschdienst> load(String modelsDir) async {
    final session = await OnnxRuntime().createSession(
      '$modelsDir/$datei',
      options: modelloptionen(providers: [OrtProvider.CPU]),
    );
    return Entrauschdienst._(session);
  }

  /// Entrauscht das JPEG [quelle] in einem eigenen Isolat; [staerke] von 0
  /// bis 1 mischt das Ergebnis über das Original.
  Restaurierungslauf starteJpeg(
    Uint8List quelle, {
    double staerke = 0.7,
    int quality = 92,
    void Function(int done, int total)? onProgress,
  }) => _starte(
    _session,
    quelle,
    quality: quality,
    onProgress: onProgress,
    art: (
      kachel: kachelGroesse,
      overlap: overlap,
      massstab: 1,
      vielfaches: 16,
      staerke: staerke.clamp(0.0, 1.0),
    ),
  );

  Future<void> dispose() async {
    await _session.close();
  }
}

Restaurierungslauf _starte(
  OrtSession session,
  Uint8List quelle, {
  required int quality,
  required _Laufart art,
  void Function(int done, int total)? onProgress,
}) {
  final post = ReceivePort();
  final lauf = Restaurierungslauf._();
  unawaited(
    Isolate.spawn(
      _restaurierungImIsolat,
      (
        token: RootIsolateToken.instance!,
        session: session,
        jpeg: TransferableTypedData.fromList([quelle]),
        qualitaet: quality,
        art: art,
        antwort: post.sendPort,
      ),
      onError: post.sendPort,
      onExit: post.sendPort,
      debugName: 'KI-Restaurierung',
    ).catchError((Object e) {
      post.close();
      lauf._fertig.completeError(e);
      return Isolate.current;
    }),
  );
  Uint8List? ergebnis;
  Object? fehler;
  post.listen((nachricht) {
    switch (nachricht) {
      case SendPort p:
        lauf._verbinde(p);
      case ('fortschritt', int fertig, int gesamt):
        onProgress?.call(fertig, gesamt);
      case ('fertig', TransferableTypedData daten):
        ergebnis = daten.materialize().asUint8List();
        if (!lauf._fertig.isCompleted) lauf._fertig.complete(ergebnis);
      case ('fertig', null):
        if (!lauf._fertig.isCompleted) lauf._fertig.complete(null);
      case [final meldung, final stapel]:
        // Ein unbehandelter Fehler im Isolat kommt als Paar aus
        // Meldung und Stapel an (onError).
        fehler = StateError('$meldung\n$stapel');
      case null:
        // onExit: Das Isolat ist beendet – mit oder ohne Ergebnis.
        post.close();
        if (lauf._fertig.isCompleted) return;
        if (fehler != null) {
          lauf._fertig.completeError(fehler!);
        } else {
          lauf._fertig.complete(ergebnis);
        }
    }
  });
  return lauf;
}

/// EIN Forward-Pass für eine einzelne Kachel. try/finally analog zu
/// SegmentationService.encodeImage/decodeMask: stellt sicher, dass die
/// (bei 512×512 rund 3 MB großen) Ein-/Ausgabe-Tensoren auch bei einem
/// Fehler mitten im Aufruf disposed werden.
///
/// Frei stehend statt als Methode: Das Isolat aus
/// [RestoreService.restoreJpeg] hat nur die Sitzung, nicht den Dienst.
Future<img.Image> _rechneKachel(
  OrtSession session,
  img.Image kachel, {
  int massstab = RestoreService.scaleFactor,
  int vielfaches = 1,
}) async {
  final tile = fuelleAuf(kachel, vielfaches);
  final width = tile.width;
  final height = tile.height;
  final ebene = width * height;
  final chw = Float32List(3 * ebene);
  for (final p in tile) {
    final i = p.y * width + p.x;
    chw[i] = p.r / 255.0;
    chw[ebene + i] = p.g / 255.0;
    chw[2 * ebene + i] = p.b / 255.0;
  }

  final inputTensor = await OrtValue.fromList(chw, [1, 3, height, width]);
  final liveTensors = <OrtValue>{inputTensor};
  try {
    final outputs = await session.run({'input': inputTensor});
    liveTensors.addAll(outputs.values);
    final outputRaw = await outputs['output']!.asFlattenedList();

    final outWidth = width * massstab;
    final outHeight = height * massstab;
    final channelSize = outWidth * outHeight;
    // Getypt lesen, wenn die Plattform getypt liefert (macOS, Linux):
    // Dann kostet jeder Wert keine Umwandlung über `num`.
    final werte = outputRaw is Float32List
        ? outputRaw
        : Float32List.fromList([
            for (final v in outputRaw) (v as num).toDouble(),
          ]);
    int kanal(double v) => (v * 255).round().clamp(0, 255);
    final result = img.Image(width: outWidth, height: outHeight);
    for (var y = 0; y < outHeight; y++) {
      final rowBase = y * outWidth;
      for (var x = 0; x < outWidth; x++) {
        final pixelIdx = rowBase + x;
        result.setPixelRgb(
          x,
          y,
          kanal(werte[pixelIdx]),
          kanal(werte[channelSize + pixelIdx]),
          kanal(werte[2 * channelSize + pixelIdx]),
        );
      }
    }
    if (identical(tile, kachel)) return result;
    return img.copyCrop(
      result,
      x: 0,
      y: 0,
      width: kachel.width * massstab,
      height: kachel.height * massstab,
    );
  } finally {
    for (final v in liveTensors) {
      try {
        await v.dispose();
      } catch (_) {
        // Bereits disposed – bestmöglich.
      }
    }
  }
}

/// Eine laufende Restaurierung im Hintergrund – siehe
/// [RestoreService.starteJpeg].
///
/// **Anhalten heisst warten, nicht verwerfen.** Die Warteschlange hält
/// den Lauf an, sobald jemand die App bedient, und lässt ihn nach einer
/// ruhigen Phase weiterlaufen. Vorher wurde ein Auftrag dabei verworfen
/// und von vorn eingereiht – bei rund 60 Kacheln je Foto und gut fünf
/// Minuten Rechenzeit wurde er so nie fertig, solange jemand mit der App
/// arbeitete. Jetzt endet die laufende Kachel, und das Isolat wartet mit
/// allem schon Gerechneten auf [fortsetzen].
class Restaurierungslauf {
  Restaurierungslauf._();

  final _fertig = Completer<Uint8List?>();
  SendPort? _isolat;
  final _vorher = <String>[];

  /// Das Ergebnis als JPEG – `null`, wenn sich die Quelle nicht dekodieren
  /// liess oder der Lauf abgebrochen wurde.
  Future<Uint8List?> get ergebnis => _fertig.future;

  void pausieren() => _sende('pause');
  void fortsetzen() => _sende('weiter');
  void abbrechen() => _sende('abbrechen');

  void _verbinde(SendPort p) {
    _isolat = p;
    for (final n in _vorher) {
      p.send(n);
    }
    _vorher.clear();
  }

  // Was vor dem Start des Isolats kommt, wird nachgereicht – ein „Pause“
  // in der ersten Millisekunde ginge sonst verloren.
  void _sende(String n) => _isolat == null ? _vorher.add(n) : _isolat!.send(n);
}

class _Abgebrochen implements Exception {}

/// Der Lauf im Isolat – siehe [RestoreService.starteJpeg] und
/// [Entrauschdienst.starteJpeg].
Future<void> _restaurierungImIsolat(
  ({
    RootIsolateToken token,
    OrtSession session,
    TransferableTypedData jpeg,
    int qualitaet,
    _Laufart art,
    SendPort antwort,
  })
  a,
) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(a.token);
  final eingang = ReceivePort();
  a.antwort.send(eingang.sendPort);
  var abgebrochen = false;
  var pausiert = false;
  Completer<void>? weiter;
  final abo = eingang.listen((m) {
    switch (m) {
      case 'pause':
        pausiert = true;
      case 'weiter' || 'abbrechen':
        pausiert = false;
        if (m == 'abbrechen') abgebrochen = true;
        weiter?.complete();
        weiter = null;
    }
  });
  try {
    final quelle = img.decodeJpg(a.jpeg.materialize().asUint8List());
    if (quelle == null) Isolate.exit(a.antwort, ('fertig', null));
    final ergebnis = await processInTiles(
      quelle,
      tileSize: a.art.kachel,
      overlap: a.art.overlap,
      scaleFactor: a.art.massstab,
      infer: (kachel) async {
        // Vor jeder Kachel: angehalten wird zwischen zwei Kacheln, nie
        // mitten in einer.
        while (pausiert && !abgebrochen) {
          await (weiter ??= Completer<void>()).future;
        }
        if (abgebrochen) throw _Abgebrochen();
        return _rechneKachel(
          a.session,
          kachel,
          massstab: a.art.massstab,
          vielfaches: a.art.vielfaches,
        );
      },
      onProgress: (fertig, gesamt) =>
          a.antwort.send(('fortschritt', fertig, gesamt)),
      isCancelled: () => abgebrochen,
    );
    if (abgebrochen) Isolate.exit(a.antwort, ('fertig', null));
    if (a.art.staerke < 1 && a.art.massstab == 1) {
      mische(quelle, ergebnis, a.art.staerke);
    }
    final jpeg = img.encodeJpg(ergebnis, quality: a.qualitaet);
    // Isolate.exit statt send: Der Kanal zur Plattform hält einen eigenen
    // Port offen, und ein Isolat mit offenem Port endet nie von selbst.
    // Mit `send` und `return` lief es weiter, und das Ergebnis kam nie an.
    Isolate.exit(a.antwort, ('fertig', TransferableTypedData.fromList([jpeg])));
  } on _Abgebrochen {
    Isolate.exit(a.antwort, ('fertig', null));
  } finally {
    await abo.cancel();
    eingang.close();
  }
}

/// Legt [ergebnis] mit [staerke] über [original] – in [ergebnis]. Beide
/// gleich gross.
@visibleForTesting
void mische(img.Image original, img.Image ergebnis, double staerke) {
  final rest = 1 - staerke;
  for (final p in ergebnis) {
    final o = original.getPixel(p.x, p.y);
    p
      ..r = (p.r * staerke + o.r * rest).round()
      ..g = (p.g * staerke + o.g * rest).round()
      ..b = (p.b * staerke + o.b * rest).round();
  }
}

/// Füllt [kachel] rechts und unten auf ein Vielfaches von [vielfaches]
/// auf – mit den Randpixeln, nicht mit Schwarz, sonst sähe das Netz eine
/// Kante, die es nicht gibt. Passt sie schon, kommt sie selbst zurück.
@visibleForTesting
img.Image fuelleAuf(img.Image kachel, int vielfaches) {
  final breite = (kachel.width + vielfaches - 1) ~/ vielfaches * vielfaches;
  final hoehe = (kachel.height + vielfaches - 1) ~/ vielfaches * vielfaches;
  if (breite == kachel.width && hoehe == kachel.height) return kachel;
  final aus = img.Image(width: breite, height: hoehe);
  for (var y = 0; y < hoehe; y++) {
    for (var x = 0; x < breite; x++) {
      aus.setPixel(
        x,
        y,
        kachel.getPixel(
          math.min(x, kachel.width - 1),
          math.min(y, kachel.height - 1),
        ),
      );
    }
  }
  return aus;
}
