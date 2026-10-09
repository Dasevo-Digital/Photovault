/// **Kratzer finden mit dem trainierten Netz** aus „Bringing Old Photos
/// Back to Life“ (Microsoft, CVPR 2020, MIT-Lizenz).
///
/// Ein U-Net, das an synthetischen und an 400 von Hand markierten echten
/// alten Fotos gelernt hat, wo Kratzer, Knicke und Risse liegen. Die
/// Autoren geben nur PyTorch-Gewichte heraus; die ONNX-Datei ist daraus
/// umgewandelt (siehe `tool/kratzermodell/`), ohne die Gewichte zu
/// verändern, und in float16 abgelegt – Ein- und Ausgabe bleiben float32.
///
/// Ohne das Modell bleibt die Suche ohne Modell aus `kratzersuche.dart`;
/// mit ihm wird sie ersetzt, nicht ergänzt: Das Netz sieht, was der
/// Zylinderhut sieht, und kennt dazu den Unterschied zwischen einem
/// Kratzer und einer Stromleitung.
///
/// Vor- und Nachbereitung wie im Original (`Global/detection.py`):
/// Graustufen, auf [-1, 1] gestreckt, Kanten auf Vielfache von 16,
/// Sigmoid, Schwelle [kratzerSchwelle].
///
/// Im Original läuft die Erkennung auf der kurzen Seite 256; hier auf
/// [kratzerKurzeSeite]. Beides begründet bei den Konstanten.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

import 'kratzersuche.dart' show Kratzerfund;
import 'modellthreads.dart';

/// Ab dieser Wahrscheinlichkeit gilt ein Punkt als Kratzer.
///
/// **0,6 statt der 0,4 der Autoren**, gewählt an einem Prüfsatz: 58 Fotos,
/// grau und weichgezeichnet wie ein alter Abzug, mit drei bis sechs
/// geschwungenen, 2 bis 5 Punkte breiten Kratzern; dazu dieselben Fotos
/// ohne Kratzer.
///
/// ```
///                         gefunden  davon richtig  saubere Fotos: Fläche
/// ohne Modell                 6 %         22 %          0,044 %
/// Netz, Schwelle 0,4         44 %         42 %          0,74 %
/// Netz, Schwelle 0,6         42 %         46 %          0,51 %
/// Netz, Schwelle 0,9         35 %         56 %          0,20 %
/// ```
///
/// Zwei Punkte weniger gefunden, ein Drittel weniger Fehlfläche. Die
/// saubere Seite ist für das Netz fremdes Gelände – es kennt alte Abzüge,
/// und moderne Kanten hält es gern für Risse. Gerade dort hilft die
/// höhere Schwelle.
const kratzerSchwelle = 0.6;

/// Die kurze Bildseite, auf die vor dem Netz verkleinert wird. Die Autoren
/// nehmen 256; an demselben Prüfsatz fand 512 mehr (45 statt 43 %) bei
/// weniger Fehlern, 768 wieder weniger.
const kratzerKurzeSeite = 512;

class KratzerModellService {
  KratzerModellService._(this._session);

  final OrtSession _session;

  /// Die Datei im Modellordner.
  static const datei = 'kratzererkennung_fp16.onnx';

  static bool isAvailable(String modelsDir) =>
      File('$modelsDir/$datei').existsSync();

  static Future<KratzerModellService> load(String modelsDir) async {
    final session = await OnnxRuntime().createSession(
      '$modelsDir/$datei',
      options: modelloptionen(providers: [OrtProvider.CPU]),
    );
    return KratzerModellService._(session);
  }

  /// Sucht in [quelle] nach Kratzern. Die Maske hat die Grösse von
  /// [quelle]; [Kratzerfund.kratzer] zählt die zusammenhängenden Stellen.
  Future<Kratzerfund> suche(img.Image quelle) async {
    final (b, h) = kratzerArbeitsmasse(quelle.width, quelle.height);
    final eingabe = await OrtValue.fromList(kratzereingabe(quelle, b, h), [
      1,
      1,
      h,
      b,
    ]);
    final lebend = <OrtValue>{eingabe};
    try {
      final ausgaben = await _session.run({'input': eingabe});
      lebend.addAll(ausgaben.values);
      final roh = await ausgaben['logits']!.asFlattenedList();
      final logits = Float32List(roh.length);
      for (var i = 0; i < roh.length; i++) {
        logits[i] = (roh[i] as num).toDouble();
      }
      return kratzermaske(logits, b, h, quelle.width, quelle.height);
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

/// Die Arbeitsgrösse: kurze Seite [kratzerKurzeSeite], beide Kanten auf
/// Vielfache von 16 gerundet (das Netz halbiert viermal). Kleinere Bilder
/// werden nicht vergrössert.
(int, int) kratzerArbeitsmasse(int breite, int hoehe) {
  final kurz = breite < hoehe ? breite : hoehe;
  final faktor = kurz > kratzerKurzeSeite ? kratzerKurzeSeite / kurz : 1.0;
  int sechzehn(double v) => ((v / 16).round() * 16).clamp(16, 1 << 16);
  return (sechzehn(breite * faktor), sechzehn(hoehe * faktor));
}

/// Graustufen wie PIL (`convert("L")`: 0,299 R + 0,587 G + 0,114 B), auf
/// [-1, 1] gestreckt.
Float32List kratzereingabe(img.Image quelle, int b, int h) {
  final klein = img.copyResize(
    quelle,
    width: b,
    height: h,
    interpolation: img.Interpolation.cubic,
  );
  final daten = Float32List(b * h);
  for (final p in klein) {
    final grau = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b) / 255;
    daten[p.y * b + p.x] = (grau - 0.5) / 0.5;
  }
  return daten;
}

/// Aus den Rohwerten des Netzes ([logits], [b] × [h]) die Maske in
/// Zielgrösse – etwas verbreitert, damit beim Füllen kein Saum bleibt.
Kratzerfund kratzermaske(
  Float32List logits,
  int b,
  int h,
  int zielBreite,
  int zielHoehe,
) {
  // sigmoid(x) >= s  <=>  x >= ln(s / (1 - s)); spart je Punkt eine exp().
  final grenze = math.log(kratzerSchwelle / (1 - kratzerSchwelle));
  final an = Uint8List(b * h);
  for (var i = 0; i < logits.length; i++) {
    if (logits[i] >= grenze) an[i] = 1;
  }
  final stellen = _zaehleStellen(an, b, h);
  final verbreitert = img.Image(width: b, height: h, numChannels: 1);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < b; x++) {
      if (an[y * b + x] == 0) continue;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx >= 0 && ny >= 0 && nx < b && ny < h) {
            verbreitert.setPixelR(nx, ny, 255);
          }
        }
      }
    }
  }
  final maske = img.copyResize(
    verbreitert,
    width: zielBreite,
    height: zielHoehe,
    interpolation: img.Interpolation.nearest,
  );
  return (maske: maske, kratzer: stellen, staub: 0);
}

int _zaehleStellen(Uint8List an, int b, int h) {
  final besucht = Uint8List(an.length);
  final stapel = <int>[];
  var n = 0;
  for (var s = 0; s < an.length; s++) {
    if (an[s] == 0 || besucht[s] == 1) continue;
    n++;
    besucht[s] = 1;
    stapel.add(s);
    while (stapel.isNotEmpty) {
      final i = stapel.removeLast();
      final x = i % b, y = i ~/ b;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= b || ny >= h) continue;
          final j = ny * b + nx;
          if (an[j] == 1 && besucht[j] == 0) {
            besucht[j] = 1;
            stapel.add(j);
          }
        }
      }
    }
  }
  return n;
}
