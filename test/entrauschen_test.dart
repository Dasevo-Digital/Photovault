import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/services/model_catalog.dart';
import 'package:photo_vault/services/restore_service.dart';

/// KI-Entrauschen (#275): das Auffüllen der Kacheln auf Vielfache von 16,
/// das Mischen nach Stärke und der Eintrag im Modellkatalog. Das Netz
/// selbst rechnet hier nicht – ONNX Runtime läuft nur in der App.
void main() {
  test('eine krumme Kachel wird mit ihren Randpixeln aufgefüllt', () {
    final k = img.Image(width: 20, height: 9);
    img.fill(k, color: img.ColorRgb8(10, 20, 30));
    k.setPixelRgb(19, 8, 200, 100, 50);
    final a = fuelleAuf(k, 16);
    expect((a.width, a.height), (32, 16));
    expect(a.getPixel(31, 15).r, 200, reason: 'die Ecke wiederholt');
    expect(a.getPixel(25, 3).g, 20, reason: 'der rechte Rand wiederholt');
    expect(identical(fuelleAuf(a, 16), a), isTrue, reason: 'passt schon');
  });

  test('die Stärke mischt das Ergebnis über das Original', () {
    final original = img.Image(width: 2, height: 1);
    img.fill(original, color: img.ColorRgb8(100, 100, 100));
    final ergebnis = img.Image(width: 2, height: 1);
    img.fill(ergebnis, color: img.ColorRgb8(200, 0, 100));
    mische(original, ergebnis, 0.7);
    final p = ergebnis.getPixel(0, 0);
    expect((p.r, p.g, p.b), (170, 30, 100));
  });

  test('das Modell steht im Katalog, festgelegt auf einen Commit', () {
    final e = ModelCatalog.all.singleWhere(
      (m) => m.id == 'denoise_nafnet_sidd_w32',
    );
    final f = e.files.single;
    expect(f.fileName, Entrauschdienst.datei);
    expect(
      f.url,
      contains('/resolve/d55684db2a6d43c29bed6223c6bbf0fb11bbcdae/'),
    );
    expect(f.sha256, hasLength(64));
  });
}
