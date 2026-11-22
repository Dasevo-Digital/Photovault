import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/screens/image_editor_screen.dart';

/// #434: Retusche und Einfärben dekodierten das volle Original und bauten
/// die Maske Punkt für Punkt im Isolat der Oberfläche. Beides läuft jetzt
/// über `compute()` – geprüft wird hier, dass die Vorbereitung in einem
/// anderen Isolat läuft und dort dieselbe Maske baut wie vorher im
/// Bildschirm.
void main() {
  test('die Maske der Retusche entsteht im Hintergrund-Isolat', () async {
    final jpeg = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 40, height: 30)),
    );
    // Der Vorschlag der Kratzersuche in halber Auflösung, ein Punkt.
    final auto = img.Image(width: 20, height: 15)
      ..setPixelRgb(2, 2, 255, 255, 255);
    final vorlage = await compute(retuscheVorbereiten, (
      bytes: jpeg,
      breite: 40,
      hoehe: 30,
      automaske: auto,
      // Anzeige in halber Grösse: (10, 10) ist im Bild (20, 20).
      striche: [
        [const Offset(10, 10), const Offset(10, 5)],
      ],
      radiert: [
        [const Offset(10, 5)],
      ],
      massstab: 0.5,
      radius: 1,
    ));

    expect(vorlage, isNotNull);
    final (:bild, :maske) = vorlage!;
    expect((bild.width, bild.height), (40, 30));
    expect((maske.width, maske.height), (40, 30));
    bool weiss(int x, int y) => maske.getPixel(x, y).r > 0;
    expect(weiss(4, 4), isTrue, reason: 'Vorschlag, hochskaliert');
    expect(weiss(5, 5), isTrue, reason: 'Vorschlag, hochskaliert');
    expect(weiss(20, 20), isTrue, reason: 'Pinselstrich');
    expect(weiss(20, 10), isFalse, reason: 'wieder wegradiert');
    expect(weiss(30, 25), isFalse);
  });

  test('ein unlesbares Bild ergibt keine Vorlage', () async {
    final vorlage = await compute(retuscheVorbereiten, (
      bytes: Uint8List.fromList([1, 2, 3]),
      breite: 4,
      hoehe: 4,
      automaske: null,
      striche: const <List<Offset>>[],
      radiert: const <List<Offset>>[],
      massstab: 1.0,
      radius: 1,
    ));
    expect(vorlage, isNull);
  });

  test('die rote Fläche der Maske entsteht im Hintergrund-Isolat', () async {
    final maske = img.Image(width: 2, height: 1)
      ..setPixelRgb(0, 0, 255, 255, 255);
    expect(await compute(rotePunkte, maske), [
      0xFF, 0x52, 0x52, 0x99, //
      0, 0, 0, 0,
    ]);
  });
}
