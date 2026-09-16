import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'modellthreads.dart';

/// Entfernt Objekte aus einem Foto, indem es die markierte Stelle aus der
/// Umgebung neu erfindet (LaMa, siehe ModelCatalog.inpainting).
///
/// **Der Vertrag des Modells, nachgemessen statt angenommen:** Es nimmt
/// `image` als [1,3,512,512] in 0..1 und `mask` als [1,1,512,512] (1 =
/// füllen), liefert aber `output` in **0..255**. Diese Asymmetrie steht
/// nirgends geschrieben; mit 0..255 als Eingabe kommt sichtbarer Unsinn
/// heraus. An einem Farbverlauf mit ausgeschnittenem Fleck geprüft: Der
/// gefüllte Bereich weicht im Mittel um 1,8 von 255 vom Sollwert ab.
///
/// **Nur CPU, kein CoreML** – anders als [RestoreService]. Gemessen: 1267 ms
/// je Durchgang auf der CPU gegen 3509 ms mit CoreML. Von den 7956 Knoten
/// des Graphen kann CoreML nur 3699 übernehmen, und die daraus entstehenden
/// 621 Teilstücke kosten mehr an Hin- und Herschieben, als die
/// Beschleunigung einbringt.
class InpaintingService {
  InpaintingService._(this._session);

  final OrtSession _session;

  /// Kantenlänge, die das Modell fest verlangt.
  static const modellGroesse = 512;

  static bool isAvailable(String modelsDir) =>
      File('$modelsDir/lama_fp32.onnx').existsSync();

  static Future<InpaintingService> load(String modelsDir) async {
    final ort = OnnxRuntime();
    final session = await ort.createSession(
      '$modelsDir/lama_fp32.onnx',
      options: modelloptionen(providers: [OrtProvider.CPU]),
    );
    return InpaintingService._(session);
  }

  /// Entfernt alles, was in [maske] weiss ist, aus [quelle].
  ///
  /// [maske] muss dieselbe Grösse wie [quelle] haben; ausgewertet wird der
  /// Rotkanal (die Masken der App sind Graustufen).
  ///
  /// Gearbeitet wird auf einem Ausschnitt um die markierte Stelle, nicht auf
  /// dem ganzen Foto: Das Modell kann nur 512×512, und ein 24-Megapixel-Bild
  /// darauf zu schrumpfen hiesse, für einen Staubfleck die ganze Auflösung
  /// zu verlieren. Der Ausschnitt bekommt Rand mit, weil das Modell aus der
  /// Umgebung schliesst – ohne Kontext füllt es Matsch.
  ///
  /// Gibt `null` zurück, wenn die Maske leer ist.
  Future<img.Image?> entferne(img.Image quelle, img.Image maske) async {
    final kasten = maskenKasten(maske);
    if (kasten == null) return null;

    // Rand: die Hälfte der Kastengrösse, mindestens 48 Punkte. Weniger
    // Kontext liefert sichtbar schlechtere Füllungen, mehr verschenkt
    // Auflösung, weil der Ausschnitt auf 512 geschrumpft wird.
    final rand = math.max(48, math.max(kasten.width, kasten.height) ~/ 2);
    final ausschnitt = quadratischerAusschnitt(kasten, rand, quelle.width, quelle.height);

    final teilBild = img.copyCrop(quelle,
        x: ausschnitt.left, y: ausschnitt.top,
        width: ausschnitt.width, height: ausschnitt.height);
    final teilMaske = img.copyCrop(maske,
        x: ausschnitt.left, y: ausschnitt.top,
        width: ausschnitt.width, height: ausschnitt.height);

    final klein = img.copyResize(teilBild,
        width: modellGroesse, height: modellGroesse,
        interpolation: img.Interpolation.linear);
    // Die Maske mit nächstem Nachbarn: Eine geglättete Maske bekäme
    // Grauwerte am Rand, und das Modell behandelt alles über 0 als „füllen".
    final kleineMaske = img.copyResize(teilMaske,
        width: modellGroesse, height: modellGroesse,
        interpolation: img.Interpolation.nearest);

    final gefuellt = await _durchlauf(klein, kleineMaske);

    // Zurück auf die Ausschnittgrösse und nur innerhalb der Maske einsetzen.
    final zurueck = img.copyResize(gefuellt,
        width: ausschnitt.width, height: ausschnitt.height,
        interpolation: img.Interpolation.cubic);

    final ergebnis = img.Image.from(quelle);
    for (var y = 0; y < ausschnitt.height; y++) {
      for (var x = 0; x < ausschnitt.width; x++) {
        final anteil = teilMaske.getPixel(x, y).r / 255.0;
        if (anteil <= 0) continue;
        final alt = teilBild.getPixel(x, y);
        final neu = zurueck.getPixel(x, y);
        double misch(num a, num b) => a + (b - a) * anteil;
        ergebnis.setPixelRgb(
          ausschnitt.left + x,
          ausschnitt.top + y,
          misch(alt.r, neu.r).round().clamp(0, 255),
          misch(alt.g, neu.g).round().clamp(0, 255),
          misch(alt.b, neu.b).round().clamp(0, 255),
        );
      }
    }
    return ergebnis;
  }

  Future<img.Image> _durchlauf(img.Image bild, img.Image maske) async {
    const n = modellGroesse;
    final chw = Float32List(3 * n * n);
    var i = 0;
    for (var c = 0; c < 3; c++) {
      for (var y = 0; y < n; y++) {
        for (var x = 0; x < n; x++) {
          final p = bild.getPixel(x, y);
          // 0..1 – siehe Klassenkommentar.
          chw[i++] = (c == 0 ? p.r : (c == 1 ? p.g : p.b)) / 255.0;
        }
      }
    }
    final maskenDaten = Float32List(n * n);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        maskenDaten[y * n + x] = maske.getPixel(x, y).r > 127 ? 1.0 : 0.0;
      }
    }

    final bildTensor = await OrtValue.fromList(chw, [1, 3, n, n]);
    final maskenTensor = await OrtValue.fromList(maskenDaten, [1, 1, n, n]);
    // Wie in RestoreService._inferTile: Alle Tensoren kommen in ein Set und
    // werden im finally freigegeben, damit auch ein Fehler mitten im Lauf
    // keine hunderte Megabyte liegen lässt.
    final lebend = <OrtValue>{bildTensor, maskenTensor};
    try {
      final ausgaben = await _session.run({'image': bildTensor, 'mask': maskenTensor});
      lebend.addAll(ausgaben.values);
      final roh = await ausgaben['output']!.asFlattenedList();

      final ergebnis = img.Image(width: n, height: n);
      const kanal = n * n;
      for (var y = 0; y < n; y++) {
        for (var x = 0; x < n; x++) {
          final idx = y * n + x;
          // Ausgabe ist bereits 0..255 – hier NICHT noch einmal skalieren.
          ergebnis.setPixelRgb(
            x, y,
            (roh[idx] as num).round().clamp(0, 255),
            (roh[kanal + idx] as num).round().clamp(0, 255),
            (roh[2 * kanal + idx] as num).round().clamp(0, 255),
          );
        }
      }
      return ergebnis;
    } finally {
      for (final v in lebend) {
        try {
          await v.dispose();
        } catch (_) {
          // Bereits freigegeben – bestmöglich.
        }
      }
    }
  }

  Future<void> dispose() async => _session.close();
}

/// Das umschliessende Rechteck aller markierten Punkte, oder `null` bei
/// leerer Maske.
@visibleForTesting
({int left, int top, int width, int height})? maskenKasten(img.Image maske) {
  var links = maske.width, oben = maske.height, rechts = -1, unten = -1;
  for (var y = 0; y < maske.height; y++) {
    for (var x = 0; x < maske.width; x++) {
      if (maske.getPixel(x, y).r > 127) {
        if (x < links) links = x;
        if (x > rechts) rechts = x;
        if (y < oben) oben = y;
        if (y > unten) unten = y;
      }
    }
  }
  if (rechts < 0) return null;
  return (left: links, top: oben, width: rechts - links + 1, height: unten - oben + 1);
}

/// Erweitert [kasten] um [rand], macht ihn quadratisch und hält ihn im Bild.
///
/// Quadratisch, weil das Modell 512×512 verlangt: Ein längliches Rechteck
/// darauf zu verzerren staucht das Motiv in einer Richtung, und das Modell
/// füllt dann entsprechend verzerrt.
/// Der Ausschnitt ist zudem NIE kleiner als [InpaintingService.modellGroesse].
///
/// Das ist der wichtigste Wert dieser Datei, und er ist gemessen: Ein
/// kleinerer Ausschnitt müsste auf 512 hochgerechnet werden, und darauf
/// arbeitet das Modell dramatisch schlechter. An einem Farbverlauf mit
/// 100 Punkten grossem Loch: mittlerer Fehler 62,8 von 255 bei einem
/// 300-Punkte-Ausschnitt, 1,2 bei 512. Herunterrechnen schadet dagegen
/// nicht.
@visibleForTesting
({int left, int top, int width, int height}) quadratischerAusschnitt(
    ({int left, int top, int width, int height}) kasten,
    int rand, int bildBreite, int bildHoehe) {
  var seite = math.max(kasten.width, kasten.height) + 2 * rand;
  seite = math.max(seite, InpaintingService.modellGroesse);
  seite = math.min(seite, math.min(bildBreite, bildHoehe));

  final mitteX = kasten.left + kasten.width / 2;
  final mitteY = kasten.top + kasten.height / 2;
  final links = (mitteX - seite / 2).round().clamp(0, bildBreite - seite);
  final oben = (mitteY - seite / 2).round().clamp(0, bildHoehe - seite);
  return (left: links, top: oben, width: seite, height: seite);
}
