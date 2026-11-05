import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/services/collage.dart';

/// Collagen (#301): Vorlagen und das Zeichnen.
void main() {
  Uint8List farbbild(int r, int g, int b, {int w = 120, int h = 80}) {
    final bild = img.Image(width: w, height: h);
    img.fill(bild, color: img.ColorRgb8(r, g, b));
    return Uint8List.fromList(img.encodeJpg(bild, quality: 95));
  }

  test('für 2 bis 9 Fotos gibt es Vorlagen, jede mit einem Feld je Foto', () {
    expect(collagevorlagen(1), isEmpty);
    expect(collagevorlagen(10), isEmpty);
    for (var n = 2; n <= 9; n++) {
      final v = collagevorlagen(n);
      expect(v, isNotEmpty, reason: '$n');
      for (final x in v) {
        expect(x.felder, hasLength(n), reason: '${x.id} bei $n');
        // Die Felder füllen die Fläche genau.
        final flaeche = x.felder.fold<double>(0, (s, f) => s + f.b * f.h);
        expect(flaeche, closeTo(1, 1e-9), reason: '${x.id} bei $n');
        expect({for (final y in v) y.id}, hasLength(v.length));
      }
    }
    expect(
      [for (final x in collagevorlagen(3)) x.id],
      ['raster', 'reihe', 'stapel', 'gross_links', 'gross_oben'],
    );
    expect(collagevorlage(4, 'gibtsnicht').id, 'raster');
  });

  test('zwei Fotos nebeneinander, mit Lücke in der Hintergrundfarbe', () {
    final jpeg = zeichneCollageJetzt(
      Collageauftrag(
        bilder: [farbbild(255, 0, 0), farbbild(0, 0, 255)],
        vorlage: collagevorlage(2, 'raster'),
        breite: 200,
        hoehe: 100,
        abstand: 0.05,
        hintergrund: 0x00FF00,
        zeit: DateTime(2024, 5, 1, 12),
      ),
    );
    final bild = img.decodeJpg(jpeg)!;
    expect(bild.width, 200);
    expect(bild.height, 100);
    final links = bild.getPixel(50, 50);
    final rechts = bild.getPixel(150, 50);
    final mitte = bild.getPixel(100, 50);
    final rand = bild.getPixel(1, 1);
    expect(links.r, greaterThan(200));
    expect(links.b, lessThan(60));
    expect(rechts.b, greaterThan(200));
    expect(rechts.r, lessThan(60));
    expect(mitte.g, greaterThan(200), reason: 'Lücke zwischen den Feldern');
    expect(rand.g, greaterThan(200), reason: 'Rand aussen');
    // Die Aufnahmezeit steht in der Datei.
    expect(
      img.decodeJpgExif(jpeg)!.exifIfd['DateTimeOriginal']!.toString(),
      '2024:05:01 12:00:00',
    );
  });

  test('runde Ecken zeigen den Hintergrund', () {
    final jpeg = zeichneCollageJetzt(
      Collageauftrag(
        bilder: [farbbild(255, 0, 0), farbbild(255, 0, 0)],
        vorlage: collagevorlage(2, 'stapel'),
        breite: 200,
        hoehe: 200,
        abstand: 0,
        ecken: 0.1,
        hintergrund: 0xFFFFFF,
      ),
    );
    final bild = img.decodeJpg(jpeg)!;
    expect(bild.getPixel(0, 0).g, greaterThan(200), reason: 'Ecke weiss');
    expect(bild.getPixel(100, 50).g, lessThan(60), reason: 'Mitte rot');
  });

  test('Farben aus „#rrggbb“', () {
    expect(collagefarbe('#102030'), 0x102030);
    expect(collagefarbe('zzz'), 0xFFFFFF);
    expect(collagefarbe(null), 0xFFFFFF);
  });
}
