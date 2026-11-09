import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:photo_vault_server/src/fotokammer.dart';
import 'package:test/test.dart';

/// Die Schärfe, nach der in einer Serie das beste Foto gewählt wird (#348).
void main() {
  /// Feine Kacheln in der Bildmitte, drumherum ruhige Fläche.
  img.Image motiv() {
    final b = img.Image(width: 1200, height: 800);
    img.fill(b, color: img.ColorRgb8(120, 120, 120));
    for (var y = 200; y < 600; y++) {
      for (var x = 300; x < 900; x++) {
        final hell = ((x ~/ 6) + (y ~/ 6)).isEven;
        b.setPixelRgb(x, y, hell ? 230 : 20, hell ? 230 : 20, hell ? 230 : 20);
      }
    }
    return b;
  }

  Uint8List jpeg(img.Image b) => img.encodeJpg(b, quality: 95);

  test('das scharfe Foto misst mehr als das unscharfe', () {
    final scharf = schaerfeDerVorschau(jpeg(motiv()))!;
    final unscharf = schaerfeDerVorschau(
      jpeg(img.gaussianBlur(motiv(), radius: 6)),
    )!;
    expect(scharf, greaterThan(unscharf * 2));
  });

  test('Struktur am Rand zählt nicht', () {
    final mitRand = motiv();
    for (var y = 0; y < 800; y++) {
      for (var x = 0; x < 100; x++) {
        final hell = ((x ~/ 3) + (y ~/ 3)).isEven;
        mitRand.setPixelRgb(x, y, hell ? 255 : 0, hell ? 255 : 0, 0);
      }
    }
    expect(
      schaerfeDerVorschau(jpeg(mitRand))!,
      closeTo(schaerfeDerVorschau(jpeg(motiv()))!, 1),
    );
  });

  test('was kein Bild ist, hat keine Schärfe', () {
    expect(schaerfeDerVorschau(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
