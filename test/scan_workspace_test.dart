import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/services/scan_workspace.dart';

void main() {
  test('trennt zwei Papierfotos an der Scannerfuge', () {
    final scan = img.Image(width: 600, height: 300);
    img.fill(scan, color: img.ColorRgb8(245, 245, 240));
    img.fillRect(
      scan,
      x1: 30,
      y1: 30,
      x2: 270,
      y2: 270,
      color: img.ColorRgb8(40, 90, 150),
    );
    img.fillRect(
      scan,
      x1: 330,
      y1: 25,
      x2: 570,
      y2: 275,
      color: img.ColorRgb8(160, 70, 40),
    );

    final bereiche = erkenneScanBereiche(scan);

    expect(bereiche, hasLength(2));
    expect(bereiche.first.x, lessThan(50));
    expect(bereiche.last.x, greaterThan(300));
  });

  test('dreht den bestätigten Ausschnitt ohne den Scan zu verändern', () {
    final scan = img.Image(width: 100, height: 80);
    img.fill(scan, color: img.ColorRgb8(255, 255, 255));
    final bereich = const ScanBereich(x: 10, y: 20, breite: 60, hoehe: 30);

    final ausschnitt = rendereScanBereich(scan, bereich, vierteldrehungen: 1);

    expect(ausschnitt.width, 30);
    expect(ausschnitt.height, 60);
    expect(scan.width, 100);
    expect(scan.height, 80);
  });
}
