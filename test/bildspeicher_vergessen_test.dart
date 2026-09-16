import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/bilddekodierung.dart';

/// **Nach dem Speichern stand das alte Bild da.**
///
/// Bearbeiten schreibt ein gedrehtes JPEG unter genau denselben Pfad,
/// Entwickeln sein Ergebnis unter `developed/{id}.jpg`, die
/// KI-Restaurierung unter `restored/{id}.jpg` – alle drei sind je
/// Aufnahme fest. Flutter merkt sich dekodierte Bilder aber nach Pfad
/// und Zielgrösse, nicht nach Inhalt: Die Datei ändert sich, der
/// Schlüssel nicht, und das Vollbild zeigt weiter das ungedrehte Bild.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Ein fertiges Bild in den Speicher legen, ohne eine Datei zu
  /// dekodieren – geprüft wird das Vergessen, nicht das Laden.
  Future<void> lege(Object schluessel) async {
    final bild = await _einBild();
    final abgeschlossen = Completer<void>();
    final strom = PaintingBinding.instance.imageCache.putIfAbsent(
      schluessel,
      () => OneFrameImageStreamCompleter(
          Future.value(ImageInfo(image: bild))),
    )!;
    late ImageStreamListener horcher;
    horcher = ImageStreamListener((_, __) {
      if (!abgeschlossen.isCompleted) abgeschlossen.complete();
    });
    strom.addListener(horcher);
    await abgeschlossen.future;
    // Erst nach dem Abmelden zählt das Bild nicht mehr als „gerade in
    // Benutzung" – genau der Zustand, in dem `clear` allein greift.
    strom.removeListener(horcher);
  }

  test('vergissAlleBilder raeumt beide Listen', () async {
    final speicher = PaintingBinding.instance.imageCache;
    vergissAlleBilder();
    expect(speicher.currentSize + speicher.liveImageCount, 0);

    await lege('originals/a1.jpg');
    await lege('developed/a1.jpg');
    expect(speicher.currentSize + speicher.liveImageCount, greaterThan(0),
        reason: 'ohne einen gefuellten Speicher prueft der Test nichts');

    vergissAlleBilder();
    expect(speicher.currentSize, 0);
    // Auch die gerade gezeichneten: `clear` allein fasst sie nicht an,
    // und ausgerechnet das Bild, auf das man sieht, bliebe stehen.
    expect(speicher.liveImageCount, 0);
  });
}

Future<ui.Image> _einBild() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 1, 1), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  return recorder.endRecording().toImage(1, 1);
}
