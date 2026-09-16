import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'clip_tokenizer.dart';
import 'modellthreads.dart';

/// Mittelwert/Standardabweichung, mit denen CLIP-Modelle trainiert wurden
/// (Standard für alle offiziellen OpenAI-CLIP-Checkpoints).
const _clipMean = [0.48145466, 0.4578275, 0.40821073];
const _clipStd = [0.26862954, 0.26130258, 0.27577711];
const _imageSize = 224;

/// Bringt ein Foto auf die 224×224 des Bild-Encoders – **kurze Seite
/// skalieren, dann mittig zuschneiden**, so wie CLIP trainiert wurde.
///
/// Vorher wurde schlicht auf 224×224 gestaucht. Das kostet mehr, als es
/// aussieht: Ein Querformat 3:2 wird dabei um ein Drittel zusammengedrückt,
/// ein Hochformat 9:16 fast auf die Hälfte. Der Encoder hat solche Bilder
/// nie gesehen, und die Einbettung wird entsprechend unschärfer – was
/// sowohl die Suche als auch das Tagging trifft, weil beide auf demselben
/// Vektor beruhen.
///
/// An 40 echten Fotos gemessen hob allein dieser Wechsel die Güte des
/// Taggings von F1 0,41 auf 0,48.
///
/// Der Zuschnitt verliert die Ränder – das ist der Preis und zugleich die
/// Absicht: Ein Bildinhalt sitzt selten am äussersten Rand, eine Verzerrung
/// dagegen trifft jedes Pixel.
///
/// Öffentlich, weil sich reine Geometrie ohne ONNX-Sitzung prüfen lässt –
/// und weil genau hier ein Fehler jahrelang unbemerkt bleiben kann: Ein
/// gestauchtes Bild sieht in keiner Ansicht falsch aus, es liefert nur
/// schlechtere Treffer.
img.Image aufClipGroesse(img.Image bild) {
  final kurz = bild.width < bild.height ? bild.width : bild.height;
  if (kurz == 0) return img.copyResize(bild, width: _imageSize, height: _imageSize);
  final faktor = _imageSize / kurz;
  final skaliert = img.copyResize(
    bild,
    width: (bild.width * faktor).round().clamp(_imageSize, 1 << 20),
    height: (bild.height * faktor).round().clamp(_imageSize, 1 << 20),
    interpolation: img.Interpolation.cubic,
  );
  return img.copyCrop(
    skaliert,
    x: (skaliert.width - _imageSize) ~/ 2,
    y: (skaliert.height - _imageSize) ~/ 2,
    width: _imageSize,
    height: _imageSize,
  );
}

/// Kapselt On-Device-Inferenz mit einem CLIP-Modell (Bild- und Text-Encoder
/// als zwei separate ONNX-Dateien), um natürlichsprachliche Bildsuche ohne
/// Cloud-Dienst zu ermöglichen.
///
/// WICHTIG: Diese Klasse benötigt drei vom Nutzer bereitzustellende Dateien
/// (siehe README → "KI-Modelle einrichten"):
///   - clip_image_encoder.onnx
///   - clip_text_encoder.onnx
///   - vocab.json + merges.txt (Tokenizer-Dateien, siehe clip_tokenizer.dart)
///
/// Die Ein-/Ausgabenamen der ONNX-Sitzungen folgen der Konvention des
/// HuggingFace-`optimum`-Exports (`pixel_values` → `image_embeds`,
/// `input_ids`/`attention_mask` → `text_embeds`). Falls dein konkretes
/// Modell andere Namen verwendet (mit z.B. Netron prüfbar), passe die
/// Konstanten unten an.
class ClipService {
  ClipService._(this._imageSession, this._textSession, this._tokenizer);

  /// Beide Encoder sind einzeln ladbar, weil sie zu verschiedenen Zeiten
  /// gebraucht werden und zusammen 577 MB belegen: Der Bild-Encoder
  /// (335 MB) arbeitet in der Hintergrundanalyse, der Text-Encoder
  /// (242 MB) ausschliesslich dann, wenn jemand eine Kontext-Suche
  /// eintippt. Wer nur sucht, soll nicht den Bildteil mitladen – und
  /// umgekehrt. Siehe [load].
  final OrtSession? _imageSession;
  final OrtSession? _textSession;
  final ClipTokenizer? _tokenizer;

  // Eingabenamen werden zur Laufzeit dynamisch aus session.inputNames gelesen
  // (siehe embedImage/embedText) statt geraten – das war zuvor eine
  // Fehlerquelle (z.B. schlug "attention_mask" beim Xenova-CLIP-Text-Encoder
  // fehl, weil dieser gar kein solches Eingabefeld hat).
  static const imageOutputName = 'image_embeds'; // bevorzugter Name, mit Fallback
  static const textOutputName = 'text_embeds'; // bevorzugter Name, mit Fallback

  static bool _filesPresent(String modelsDir) {
    for (final name in [
      'clip_image_encoder.onnx',
      'clip_text_encoder.onnx',
      'vocab.json',
      'merges.txt',
    ]) {
      if (!File('$modelsDir/$name').existsSync()) return false;
    }
    return true;
  }

  static bool isAvailable(String modelsDir) => _filesPresent(modelsDir);

  /// Öffnet eine Sitzung und übersetzt ein Scheitern in [ModellUnbrauchbar].
  ///
  /// **Warum nicht einfach durchreichen.** Eine Datei kann vorhanden und
  /// trotzdem unbrauchbar sein – etwa weil sie in einem Zahlenformat
  /// vorliegt, das die mitgelieferte ONNX Runtime nicht laden kann (siehe
  /// [ModelCatalog.clip]). Der Anwender bekam dann eine C++-Zusicherung
  /// mit Dateipfaden eines fremden Bauservers zu lesen und keinen
  /// Hinweis, was zu tun ist. [ClipService.isAvailable] kann das nicht
  /// abfangen: Ob ein Modell lädt, weiss man erst, wenn man es lädt.
  static Future<OrtSession> _sitzung(OnnxRuntime ort, String pfad) async {
    try {
      return await ort.createSession(pfad, options: modelloptionen());
    } catch (fehler) {
      throw ModellUnbrauchbar(p.basename(pfad), fehler);
    }
  }

  /// Lädt nur die angeforderten Encoder. [bild] wird für [embedImage]
  /// gebraucht, [text] für [embedText]; der Tokenizer hängt am Textteil.
  /// Der jeweils nicht angeforderte Encoder bleibt ungeladen, und die
  /// zugehörige Methode wirft dann einen erklärenden Fehler statt still
  /// Unsinn zu liefern.
  static Future<ClipService> load(
    String modelsDir, {
    bool bild = true,
    bool text = true,
  }) async {
    assert(bild || text, 'Ein ClipService ohne Encoder wäre nutzlos.');
    final ort = OnnxRuntime();
    final imageSession = bild
        ? await _sitzung(ort, '$modelsDir/clip_image_encoder.onnx')
        : null;
    final textSession = text
        ? await _sitzung(ort, '$modelsDir/clip_text_encoder.onnx')
        : null;
    final tokenizer = text
        ? await ClipTokenizer.loadFromFiles(
            vocabJsonPath: '$modelsDir/vocab.json',
            mergesTxtPath: '$modelsDir/merges.txt',
          )
        : null;
    return ClipService._(imageSession, textSession, tokenizer);
  }

  /// Berechnet das Bild-Embedding eines bereits dekodierten Fotos. Nimmt
  /// bewusst ein [img.Image] statt einer [File] entgegen: Aufrufer wie
  /// [LibraryState] dekodieren dasselbe Bild ohnehin schon für die
  /// Gesichtserkennung – ein zweites Mal von der Platte zu lesen und zu
  /// dekodieren wäre verschwendete Rechenzeit. Videos werden aktuell nicht
  /// unterstützt (es müsste zunächst ein Frame extrahiert werden).
  Future<Float32List> embedImage(img.Image decoded) async {
    final session = _imageSession;
    if (session == null) {
      throw StateError('Dieser ClipService wurde ohne Bild-Encoder geladen.');
    }
    final resized = aufClipGroesse(decoded);

    final chw = Float32List(3 * _imageSize * _imageSize);
    var idx = 0;
    for (var c = 0; c < 3; c++) {
      for (var y = 0; y < _imageSize; y++) {
        for (var x = 0; x < _imageSize; x++) {
          final pixel = resized.getPixel(x, y);
          final value = c == 0 ? pixel.r : (c == 1 ? pixel.g : pixel.b);
          final normalized = (value / 255.0 - _clipMean[c]) / _clipStd[c];
          chw[idx++] = normalized;
        }
      }
    }

    final inputTensor = await OrtValue.fromList(chw, [1, 3, _imageSize, _imageSize]);
    // Freigeben gehört ins finally, nicht dahinter: Wirft run(), das
    // Auspacken oder der !-Zugriff, bliebe der Tensor sonst als nativer
    // Speicher liegen, den der Dart-Sammler nie zurückholt. Dieser Pfad
    // läuft beim Import über jedes Foto – ein Stapel mit kaputten Dateien
    // summiert sich (Prüfrunde 12).
    Map<String, OrtValue>? outputs;
    try {
      outputs = await session.run({session.inputNames.first: inputTensor});
      final outputTensor = outputs[imageOutputName] ?? outputs[session.outputNames.first]!;
      final raw = await outputTensor.asFlattenedList();
      return _l2Normalize(Float32List.fromList(raw.map((e) => (e as num).toDouble()).toList()));
    } finally {
      await inputTensor.dispose();
      for (final v in outputs?.values ?? const <OrtValue>[]) {
        await v.dispose();
      }
    }
  }

  Future<Float32List> embedText(String text) async {
    final session = _textSession;
    final tokenizer = _tokenizer;
    if (session == null || tokenizer == null) {
      throw StateError('Dieser ClipService wurde ohne Text-Encoder geladen.');
    }
    final tokenIds = Int64List.fromList(tokenizer.encode(text));

    final idsTensor = await OrtValue.fromList(tokenIds, [1, ClipTokenizer.contextLength]);
    Map<String, OrtValue>? outputs;
    try {
      outputs = await session.run({
        session.inputNames.first: idsTensor,
      });
      final outputTensor = outputs[textOutputName] ?? outputs[session.outputNames.first]!;
      final raw = await outputTensor.asFlattenedList();
      return _l2Normalize(Float32List.fromList(raw.map((e) => (e as num).toDouble()).toList()));
    } finally {
      await idsTensor.dispose();
      for (final v in outputs?.values ?? const <OrtValue>[]) {
        await v.dispose();
      }
    }
  }

  Float32List _l2Normalize(Float32List vector) {
    var sumSq = 0.0;
    for (final v in vector) {
      sumSq += v * v;
    }
    final norm = math.sqrt(sumSq);
    if (norm == 0) return vector;
    final result = Float32List(vector.length);
    for (var i = 0; i < vector.length; i++) {
      result[i] = vector[i] / norm;
    }
    return result;
  }

  /// Sortiert eine Menge gespeicherter Embeddings nach Kosinus-Ähnlichkeit
  /// zu einem Anfrage-Vektor (z.B. aus [embedText]) – Brute-Force, aber für
  /// private Fotobibliotheken ausreichend performant.
  ///
  /// Nur die besten [topK] werden festgehalten, über einen begrenzten
  /// Haufen statt einer vollständigen Sortierung. Bei gleichem Abstand
  /// gewinnt der zuerst gesehene Eintrag – damit ist die Reihenfolge
  /// **verlässlich dieselbe**, was sie mit `List.sort` nicht war.
  ///
  /// **Und sie läuft hier, nicht in einem eigenen Isolat.** Das war eine
  /// Zeit lang anders. Gemessen an der gewachsenen Bibliothek
  /// (`tool/messe_rangfolge_test.dart`):
  ///
  /// ```
  /// Kandidaten   hier     im Isolat
  ///        50   0,4 ms      0,2 ms
  ///       500   0,3 ms      1,5 ms
  ///      2000   0,8 ms      2,9 ms
  ///      8096   3,0 ms      8,8 ms
  /// ```
  ///
  /// Drei Millisekunden für die ganze Bibliothek sind ein Sechstel eines
  /// Bildes – es gab kein Ruckeln zu verhindern, und der Umweg hat die
  /// Gesamtzeit verdreifacht. Ab etwa der zehnfachen Bibliothek kippt das:
  /// Dann kostet diese Schleife mehr als ein Bild, und dann gehört sie
  /// wieder hinaus.
  static List<MapEntry<String, double>> rankBySimilarity(
    Float32List query,
    Map<String, Float32List> candidates, {
    int topK = 200,
  }) {
    if (topK <= 0 || candidates.isEmpty) return const [];
    final heap = <({String key, double score, int order})>[];

    bool schlechterAls(
            ({String key, double score, int order}) a,
            ({String key, double score, int order}) b) =>
        a.score < b.score || (a.score == b.score && a.order > b.order);

    void nachOben(int index) {
      while (index > 0) {
        final eltern = (index - 1) ~/ 2;
        if (!schlechterAls(heap[index], heap[eltern])) break;
        final tmp = heap[index];
        heap[index] = heap[eltern];
        heap[eltern] = tmp;
        index = eltern;
      }
    }

    void nachUnten(int index) {
      while (true) {
        final links = index * 2 + 1;
        if (links >= heap.length) return;
        final rechts = links + 1;
        var schlechtester = links;
        if (rechts < heap.length &&
            schlechterAls(heap[rechts], heap[links])) {
          schlechtester = rechts;
        }
        if (!schlechterAls(heap[schlechtester], heap[index])) return;
        final tmp = heap[index];
        heap[index] = heap[schlechtester];
        heap[schlechtester] = tmp;
        index = schlechtester;
      }
    }

    var order = 0;
    for (final e in candidates.entries) {
      var dot = 0.0;
      final v = e.value;
      final len = math.min(query.length, v.length);
      for (var i = 0; i < len; i++) {
        dot += query[i] * v[i];
      }
      final kandidat = (key: e.key, score: dot, order: order++);
      if (heap.length < topK) {
        heap.add(kandidat);
        nachOben(heap.length - 1);
      } else if (schlechterAls(heap.first, kandidat)) {
        heap[0] = kandidat;
        nachUnten(0);
      }
    }
    heap.sort((a, b) {
      final nachWert = b.score.compareTo(a.score);
      return nachWert != 0 ? nachWert : a.order.compareTo(b.order);
    });
    return [for (final e in heap) MapEntry(e.key, e.score)];
  }

  Future<void> dispose() async {
    await _imageSession?.close();
    await _textSession?.close();
  }
}

/// Ein Modell liegt zwar da, lässt sich aber nicht öffnen.
///
/// Trägt den Dateinamen, damit die Oberfläche sagen kann, welches Modell
/// gemeint ist, und den ursprünglichen Fehler für das Protokoll.
class ModellUnbrauchbar implements Exception {
  ModellUnbrauchbar(this.datei, this.ursache);

  final String datei;
  final Object ursache;

  @override
  String toString() => 'ModellUnbrauchbar($datei): $ursache';
}
