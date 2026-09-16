// ignore_for_file: avoid_print
// Sonde: Gibt fuer mehrere Modelle einen Fingerabdruck aus, damit sich zwei
// Laeufe vergleichen lassen.
//
// Anlass: Die Ursache des HardSwish-Fehlers war eine locale-abhaengige
// Textumwandlung in ONNX, die jeden funktionsdefinierten Operator mit
// gebrochener Konstante im Rumpf trifft. Fuer CLIP-Text ist bereits
// nachgemessen, dass 1.8.3 und 1.8.4 bitgleich rechnen; diese Sonde deckt
// die uebrigen Modelle ab, deren Ergebnisse in der Datenbank landen.
//
// Das Pruefbild wird BERECHNET, nicht geladen: Es geht nicht darum, ob das
// Ergebnis sinnvoll ist, sondern ob zwei Laeufe dasselbe ergeben. Eine
// erzeugte Vorlage ist dafuer verlaesslicher als eine Datei, die auf der
// Zielmaschine liegen muss.
//
//   flutter test integration_test/locale_modelle_probe_test.dart -d linux
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:photo_vault/services/face_engine_service.dart';
import 'package:photo_vault/services/florence_captioning_service.dart';
import 'package:photo_vault/services/segmentation_service.dart';
import 'package:photo_vault/services/translation_service.dart';

/// Ein Bild, das jeder Lauf identisch erzeugt.
img.Image pruefbild(int kante) {
  final b = img.Image(width: kante, height: kante);
  for (var y = 0; y < kante; y++) {
    for (var x = 0; x < kante; x++) {
      b.setPixelRgb(x, y, (x * 7 + y * 3) % 256, (x * 5) % 256, (y * 11) % 256);
    }
  }
  return b;
}

String abdruck(List<double> werte) {
  var summe = 0.0;
  for (final w in werte) {
    summe += w;
  }
  final anfang = werte.take(6).map((e) => e.toStringAsFixed(6)).join(' ');
  return '$anfang | n=${werte.length} summe=${summe.toStringAsFixed(6)}';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final ordner = Platform.environment['PV_MODELLE'] ??
      '${Platform.environment['HOME']}/.var/app/com.example.PhotoVault/data'
          '/com.example.photo_vault/PhotoVault/models';

  test('Fingerabdruecke der Modelle', () async {
    print('LC_NUMERIC=${Platform.environment['LC_NUMERIC'] ?? '(nicht gesetzt)'}');
    print('MODELLE=$ordner');

    // --- Uebersetzung: reiner Text, keine Bildabhaengigkeit ---------------
    if (TranslationService.isAvailable(ordner, Uebersetzungsrichtung.enDe)) {
      final d = await TranslationService.load(ordner, Uebersetzungsrichtung.enDe);
      final s = await d.translate('a red bicycle in front of a stone wall');
      await d.dispose();
      print('UEBERSETZUNG "$s"');
    } else {
      print('UEBERSETZUNG (nicht installiert)');
    }

    // --- Florence: Bildbeschreibung, landet in der Datenbank --------------
    if (FlorenceCaptioningService.isAvailable(ordner)) {
      final d = await FlorenceCaptioningService.load(ordner);
      final s = await d.generateCaption(pruefbild(512));
      await d.dispose();
      print('FLORENCE "$s"');
    } else {
      print('FLORENCE (nicht installiert)');
    }

    // --- SAM: Bild-Embedding, Zwischenergebnis der Maskenauswahl ----------
    if (SegmentationService.isAvailable(ordner)) {
      final d = await SegmentationService.load(ordner);
      final e = await d.encodeImage(pruefbild(512));
      await d.dispose();
      print('SAM ${abdruck(e.embeddings.toList())}');
    } else {
      print('SAM (nicht installiert)');
    }

    // --- Gesichter: die Einbettung landet dauerhaft in der Datenbank ------
    final gesichter = await FaceEngineService.load(ordner);
    if (gesichter != null && gesichter.canEmbed) {
      // Ohne echtes Gesicht: der Weg zaehlt, nicht der Sinn des Ergebnisses.
      final kasten = DetectedFace(0.25, 0.25, 0.5, 0.5, 1.0);
      final v = await gesichter.embedFace(pruefbild(256), kasten);
      print('GESICHT ${v == null ? '(null)' : abdruck(v.toList())}');
    } else {
      print('GESICHT (nicht installiert)');
    }
    await gesichter?.dispose();
  }, timeout: const Timeout(Duration(minutes: 15)));
}
