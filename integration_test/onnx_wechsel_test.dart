// ignore_for_file: avoid_print
// **Rechnen alle Modelle nach einem Wechsel der ONNX Runtime noch gleich?**
//
// Anlass ist Issue #60: flutter_onnxruntime 1.9.0 hebt ONNX Runtime unter
// Linux und Windows von 1.22 auf 1.28, unter macOS von 1.23 auf 1.28. Zwei
// fp16-Modelle sind früher nur im laufenden Programm gescheitert, nie im
// Unittest (siehe `clip_modelle_laden_test.dart`). Deshalb rechnet diese
// Probe jedes Modell der App einmal über ihren eigenen Dienst, mit einem
// berechneten Prüfbild, und hält das Ergebnis fest:
//
//   * Vektoren (CLIP, Gesichter, SAM) als Stichprobe von höchstens 512
//     Werten, verglichen über den Kosinus;
//   * Bilder (Restaurierung, Einfärben, Objektentfernung, Kratzermaske) auf
//     16 × 16 Punkte verkleinert, verglichen über die grösste Abweichung;
//   * Texte (Übersetzung, Texterkennung) wörtlich; die Bildbeschreibung
//     nur als Satz (Begründung beim Vergleich unten).
//
// Ablauf: einmal mit der alten Runtime laufen lassen, die Datei aus
// `PV_ABDRUCK` aufheben, dann mit der neuen und `PV_ABDRUCK_VORHER` darauf
// zeigen lassen. Der zweite Lauf vergleicht und schlägt fehl, wenn ein
// Modell anders rechnet.
//
// Dazu zählt die Probe die Fäden, die eine Sitzung anlegt. ONNX Runtime
// legt beim Öffnen einen Pool mit `intraOpNumThreads - 1` Fäden an. Kommt die
// Zahl aus `modelloptionen` nicht an, nimmt es sich so viele, wie der
// Rechner Kerne hat; dann ist die Oberfläche während eines Laufs blockiert
// (siehe `modellthreads.dart`).
//
//   PV_MODELLE=~/pv_probe_modelle PV_ABDRUCK=~/pv_abdruck_alt.json \
//     flutter test integration_test/onnx_wechsel_test.dart -d linux
//
// Auf den Testrechnern immer mit PV_MODELLE; Modelle gehören dort nie in
// den Datenordner der App (siehe `modell_haelt_an_test.dart`).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:kern/services/clip_service.dart';
import 'package:kern/services/eye_state_service.dart';
import 'package:kern/services/face_engine_service.dart';
import 'package:kern/services/florence_captioning_service.dart';
import 'package:photo_vault/services/inpainting_service.dart';
import 'package:photo_vault/services/kolorieren.dart';
import 'package:kern/services/kratzermodell.dart';
import 'package:kern/services/ocr_service.dart';
import 'package:photo_vault/services/restore_service.dart';
import 'package:photo_vault/services/segmentation_service.dart';
import 'package:kern/services/translation_service.dart';

/// Ein Bild, das jeder Lauf gleich erzeugt: Verläufe mit etwas Struktur.
img.Image _pruefbild(int kante) {
  final b = img.Image(width: kante, height: kante);
  for (var y = 0; y < kante; y++) {
    for (var x = 0; x < kante; x++) {
      b.setPixelRgb(x, y, (x * 7 + y * 3) % 256, (x * 5) % 256, (y * 11) % 256);
    }
  }
  return b;
}

/// Schwarze Schrift auf hellem Grund, für die Texterkennung.
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

/// Höchstens 512 Werte, gleichmässig über den Vektor verteilt.
List<double> _stichprobe(List<double> v) {
  final schritt = math.max(1, v.length ~/ 512);
  return [for (var i = 0; i < v.length; i += schritt) v[i]];
}

/// Das Bild auf 16 × 16 Punkte, als RGB-Werte 0..255.
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

double _kosinus(List<num> a, List<num> b) {
  var ab = 0.0, aa = 0.0, bb = 0.0;
  for (var i = 0; i < a.length; i++) {
    ab += a[i] * b[i];
    aa += a[i] * a[i];
    bb += b[i] * b[i];
  }
  if (aa == 0 && bb == 0) return 1;
  return ab / math.sqrt(aa * bb);
}

/// Wie viele Fäden der Prozess gerade hat; `null`, wo es sich nicht messen
/// lässt (macOS: der Sandkasten verbietet das Starten von `ps`).
Future<int?> _faeden() async {
  if (Platform.isLinux) {
    return Directory('/proc/self/task').listSync().length;
  }
  if (Platform.isWindows) {
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      '(Get-Process -Id $pid).Threads.Count',
    ]);
    return int.tryParse((r.stdout as String).trim());
  }
  return null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String modelle;
  late File ausgabe;

  setUpAll(() async {
    final support = await getApplicationSupportDirectory();
    modelle =
        Platform.environment['PV_MODELLE'] ??
        p.join(support.path, 'PhotoVault', 'models');
    ausgabe = File(
      Platform.environment['PV_ABDRUCK'] ??
          p.join(support.path, 'onnx_abdruck.json'),
    );
    print('Modelle: $modelle\nAbdruck: ${ausgabe.path}');
  });

  test('die Fadenzahl aus den Sitzungsoptionen kommt an', () async {
    final datei = p.join(modelle, 'face_detection_yunet.onnx');
    if (!File(datei).existsSync()) {
      markTestSkipped('$datei fehlt');
      return;
    }
    if (await _faeden() == null) {
      markTestSkipped('Fäden lassen sich hier nicht zählen');
      return;
    }
    final ort = OnnxRuntime();
    // Eine erste Sitzung weckt den Arbeitsfaden des Plugins und die
    // Umgebung von ONNX Runtime; sie zählt nicht mit.
    final erste = await ort.createSession(
      datei,
      options: OrtSessionOptions(intraOpNumThreads: 1, interOpNumThreads: 1),
    );
    final zuwachs = <String, int>{};
    final sitzungen = [erste];
    for (final (name, zahl) in [('zwei', 2), ('vier', 4), ('ohne', null)]) {
      final vorher = (await _faeden())!;
      sitzungen.add(
        await ort.createSession(
          datei,
          options: zahl == null
              ? OrtSessionOptions()
              : OrtSessionOptions(
                  intraOpNumThreads: zahl,
                  interOpNumThreads: 1,
                ),
        ),
      );
      zuwachs[name] = (await _faeden())! - vorher;
    }
    for (final s in sitzungen) {
      await s.close();
    }
    print(
      'FAEDEN Kerne=${Platform.numberOfProcessors} '
      'intra2:+${zuwachs['zwei']} intra4:+${zuwachs['vier']} '
      'ohne:+${zuwachs['ohne']}',
    );
    expect(zuwachs['zwei'], 1, reason: 'intraOpNumThreads 2 = ein Poolfaden');
    expect(zuwachs['vier'], 3, reason: 'intraOpNumThreads 4 = drei Poolfäden');
  });

  test('jedes Modell rechnet wie mit der vorigen Runtime', () async {
    final abdruck = <String, Object>{};
    final zeiten = <String, int>{};
    final uhr = Stopwatch();

    Future<void> miss(String name, Future<Object?> Function() rechne) async {
      uhr
        ..reset()
        ..start();
      final ergebnis = await rechne();
      zeiten[name] = uhr.elapsedMilliseconds;
      if (ergebnis == null) {
        print('$name: nicht installiert');
        return;
      }
      abdruck[name] = ergebnis;
      final kurz = ergebnis is List
          ? '${ergebnis.length} Werte'
          : '"$ergebnis"';
      print('$name: $kurz (${zeiten[name]} ms)');
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

    await miss('sam', () async {
      if (!SegmentationService.isAvailable(modelle)) return null;
      final d = await SegmentationService.load(modelle);
      final e = await d.encodeImage(bild);
      final m = await d.decodeMask(
        e,
        foregroundPoints: const [Offset(256, 256)],
      );
      await d.dispose();
      return [
        ..._stichprobe(e.embeddings),
        m.iouScore,
        ..._stichprobe(m.logits).take(64),
      ];
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

    await miss('restaurierung', () async {
      if (!RestoreService.isAvailable(modelle)) return null;
      final d = await RestoreService.load(modelle);
      final r = await d.restore(_pruefbild(96));
      await d.dispose();
      return _kleinbild(r);
    });

    await miss('einfaerben', () async {
      if (!KolorierService.isAvailable(modelle)) return null;
      final d = await KolorierService.load(modelle);
      final r = await d.faerbe(img.grayscale(_pruefbild(256)));
      await d.dispose();
      return _kleinbild(r);
    });

    await miss('objektentfernung', () async {
      if (!InpaintingService.isAvailable(modelle)) return null;
      final d = await InpaintingService.load(modelle);
      final maske = img.Image(width: 512, height: 512);
      img.fillRect(
        maske,
        x1: 200,
        y1: 200,
        x2: 300,
        y2: 280,
        color: img.ColorRgb8(255, 255, 255),
      );
      final r = await d.entferne(bild, maske);
      await d.dispose();
      return r == null ? null : _kleinbild(r);
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

    await ausgabe.parent.create(recursive: true);
    await ausgabe.writeAsString(
      const JsonEncoder.withIndent(' ').convert({
        'plattform': Platform.operatingSystem,
        'zeiten': zeiten,
        'abdruck': abdruck,
      }),
    );
    print('Abdruck geschrieben: ${ausgabe.path}');

    final vorherPfad = Platform.environment['PV_ABDRUCK_VORHER'];
    if (vorherPfad == null) return;
    final vorher =
        jsonDecode(await File(vorherPfad).readAsString())
            as Map<String, dynamic>;
    final alt = vorher['abdruck'] as Map<String, dynamic>;
    final altZeiten = vorher['zeiten'] as Map<String, dynamic>;
    final abweichungen = <String>[];
    for (final MapEntry(:key, :value) in abdruck.entries) {
      final a = alt[key];
      final zeit = '${altZeiten[key]} → ${zeiten[key]} ms';
      if (a == null) {
        print('VERGLEICH $key: vorher nicht gerechnet ($zeit)');
        continue;
      }
      if (value is String) {
        final gleich = value == a;
        print(
          'VERGLEICH $key: ${gleich ? 'gleich' : '"$a" → "$value"'} '
          '($zeit)',
        );
        // Die Bildbeschreibung wird nur berichtet: Ihr Bildteil ist int8
        // dynamisch quantisiert, und solche Modelle hängen daran, wie die
        // Runtime rundet und Knoten zusammenfasst. Schon die
        // Optimierungsstufe derselben Fassung verschiebt die Merkmale auf
        // einen Kosinus von 0,87, und von 1.23 auf 1.28 änderte sich der
        // Satz bei 9 von 17 Fotos – gleichwertig, nur anders formuliert
        // (Issue #60). Geprüft wird hier, dass ein Satz herauskommt.
        if (key == 'florence') {
          expect(
            RegExp(r'^[A-Z][a-z]*( [a-z,-]+){3,}\.$').hasMatch(value),
            isTrue,
            reason: 'kein Satz: "$value"',
          );
          continue;
        }
        if (!gleich) abweichungen.add(key);
        continue;
      }
      final neu = (value as List<double>);
      final altListe = (a as List).cast<num>();
      if (neu.length != altListe.length) {
        print('VERGLEICH $key: Länge ${altListe.length} → ${neu.length}');
        abweichungen.add(key);
        continue;
      }
      var groesste = 0.0;
      for (var i = 0; i < neu.length; i++) {
        groesste = math.max(groesste, (neu[i] - altListe[i]).abs());
      }
      final kos = _kosinus(neu, altListe);
      // Bilder: höchstens drei Stufen von 255 im 16×16-Mittel; Vektoren:
      // Kosinus über 0,999 – das, was eine andere Summationsreihenfolge
      // in fp32 ausmacht, aber kein anderes Ergebnis.
      final bild =
          key == 'restaurierung' ||
          key == 'einfaerben' ||
          key == 'objektentfernung' ||
          key == 'kratzer';
      final ok = bild ? groesste <= 3 : kos > 0.999;
      print(
        'VERGLEICH $key: Kosinus ${kos.toStringAsFixed(6)}, '
        'grösste Abweichung ${groesste.toStringAsPrecision(3)} '
        '${ok ? 'ok' : 'ABWEICHUNG'} ($zeit)',
      );
      if (!ok) abweichungen.add(key);
    }
    expect(abweichungen, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 20)));
}
