import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

import 'tile_processor.dart';
import 'modellthreads.dart';

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
class RestoreService {
  RestoreService._(this._session);

  final OrtSession _session;

  static const tileSize = 512;
  static const overlap = 16;
  static const scaleFactor = 4;

  static bool isAvailable(String modelsDir) =>
      File('$modelsDir/real_esrgan_x4.onnx').existsSync();

  static Future<RestoreService> load(String modelsDir) async {
    final ort = OnnxRuntime();
    final session = await ort.createSession(
      '$modelsDir/real_esrgan_x4.onnx',
      options: modelloptionen(
        providers: [OrtProvider.CORE_ML, OrtProvider.CPU],
      ),
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
      tileSize: tileSize,
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
    final post = ReceivePort();
    final lauf = Restaurierungslauf._();
    unawaited(
      Isolate.spawn(
        _restaurierungImIsolat,
        (
          token: RootIsolateToken.instance!,
          session: _session,
          jpeg: TransferableTypedData.fromList([quelle]),
          qualitaet: quality,
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

  Future<void> dispose() async {
    await _session.close();
  }
}

/// EIN Forward-Pass für eine einzelne Kachel. try/finally analog zu
/// SegmentationService.encodeImage/decodeMask: stellt sicher, dass die
/// (bei 512×512 rund 3 MB großen) Ein-/Ausgabe-Tensoren auch bei einem
/// Fehler mitten im Aufruf disposed werden.
///
/// Frei stehend statt als Methode: Das Isolat aus
/// [RestoreService.restoreJpeg] hat nur die Sitzung, nicht den Dienst.
Future<img.Image> _rechneKachel(OrtSession session, img.Image tile) async {
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

    final outWidth = width * RestoreService.scaleFactor;
    final outHeight = height * RestoreService.scaleFactor;
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
    return result;
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

/// Der Lauf im Isolat – siehe [RestoreService.starteJpeg].
Future<void> _restaurierungImIsolat(
  ({
    RootIsolateToken token,
    OrtSession session,
    TransferableTypedData jpeg,
    int qualitaet,
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
      tileSize: RestoreService.tileSize,
      overlap: RestoreService.overlap,
      scaleFactor: RestoreService.scaleFactor,
      infer: (kachel) async {
        // Vor jeder Kachel: angehalten wird zwischen zwei Kacheln, nie
        // mitten in einer.
        while (pausiert && !abgebrochen) {
          await (weiter ??= Completer<void>()).future;
        }
        if (abgebrochen) throw _Abgebrochen();
        return _rechneKachel(a.session, kachel);
      },
      onProgress: (fertig, gesamt) =>
          a.antwort.send(('fortschritt', fertig, gesamt)),
      isCancelled: () => abgebrochen,
    );
    if (abgebrochen) Isolate.exit(a.antwort, ('fertig', null));
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
