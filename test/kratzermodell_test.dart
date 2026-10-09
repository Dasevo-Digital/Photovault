import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/services/kratzermodell.dart';
import 'package:photo_vault/services/model_catalog.dart';

/// Vor- und Nachbereitung des Kratzer-Netzes – ohne das Netz selbst, das
/// nur im Zielprozess läuft (siehe integration_test/kratzermodell_test.dart).
void main() {
  test('Arbeitsgrösse: kurze Seite 512, Vielfache von 16, nie vergrössert', () {
    // 4000 × 3000 → 682,7 × 512 → 688 × 512 (gerundet auf 16).
    expect(kratzerArbeitsmasse(4000, 3000), (688, 512));
    final (b, h) = kratzerArbeitsmasse(3000, 4000);
    expect(b, 512);
    expect(h % 16, 0);
    expect(kratzerArbeitsmasse(300, 200), (304, 208));
  });

  test('die Eingabe ist Graustufe nach PIL, auf -1..1 gestreckt', () {
    final bild = img.Image(width: 32, height: 16)
      ..clear(img.ColorRgb8(255, 0, 0));
    final e = kratzereingabe(bild, 32, 16);
    expect(e.length, 32 * 16);
    expect(e[0], closeTo(0.299 * 2 - 1, 0.01));
    final weiss = kratzereingabe(
      img.Image(width: 16, height: 16)..clear(img.ColorRgb8(255, 255, 255)),
      16,
      16,
    );
    expect(weiss[5], closeTo(1, 1e-6));
  });

  test('die Maske folgt der Schwelle und hat die Zielgrösse', () {
    final grenze = math.log(kratzerSchwelle / (1 - kratzerSchwelle));
    final logits = Float32List(16 * 16)..fillRange(0, 16 * 16, -5);
    // Eine senkrechte Linie in Spalte 8, knapp über der Schwelle.
    for (var y = 0; y < 16; y++) {
      logits[y * 16 + 8] = grenze + 0.01;
    }
    // Ein einzelner Punkt knapp darunter zählt nicht.
    logits[3] = grenze - 0.01;
    final f = kratzermaske(logits, 16, 16, 64, 64);
    expect(f.kratzer, 1);
    expect(f.maske.width, 64);
    expect(f.maske.getPixel(8 * 4 + 1, 20).r, 255);
    expect(f.maske.getPixel(3 * 4, 0).r, 0);
    expect(f.maske.getPixel(50, 20).r, 0);
  });

  test('der Katalog kennt das Modell mit Prüfsumme und Grösse', () {
    final e = ModelCatalog.all.singleWhere(
      (e) => e.id == 'scratch_detection_bopbtl',
    );
    expect(e.files.single.fileName, KratzerModellService.datei);
    expect(e.files.single.sha256, hasLength(64));
  });
}
