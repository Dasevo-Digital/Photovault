import 'dart:typed_data';

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

  group('Vorder- und Rückseiten (#218)', () {
    test('Paare nach der Auswahl, nicht nach dem, was übrig blieb', () {
      expect(scanPaare(['a', 'b', 'c', 'd']).paare, [('a', 'b'), ('c', 'd')]);
      final eins = scanPaare(['a', null, 'c', 'd']);
      expect(eins.paare, [('c', 'd')]);
      expect(eins.unvollstaendig, 1);
      // Bis 3.48.0 rückten die übrigen nach: a und d wurden ein Paar.
      final zwei = scanPaare(['a', null, null, 'd']);
      expect(zwei.paare, isEmpty);
      expect(zwei.unvollstaendig, 2);
      final ganz = scanPaare([null, null, 'c', 'd']);
      expect(ganz.paare, [('c', 'd')]);
      expect(
        ganz.unvollstaendig,
        0,
        reason: 'ein ganz fehlendes Paar fehlt nur',
      );
    });
  });

  group('Ausschneiden (#218)', () {
    img.Image verlauf() {
      final bild = img.Image(width: 120, height: 90);
      for (final px in bild) {
        px
          ..r = px.x * 2
          ..g = px.y * 2
          ..b = (px.x + px.y) % 256;
      }
      return bild;
    }

    const bereich = ScanBereich(x: 10, y: 15, breite: 70, hoehe: 40);

    test('aus PNG bildpunktgenau als PNG, mit Farbprofil', () {
      final scan = verlauf()
        ..iccProfile = img.IccProfile(
          'Scanner',
          img.IccProfileCompression.none,
          Uint8List.fromList(List.generate(64, (i) => i)),
        );
      final aus = erzeugeScanAusschnitte(img.encodePng(scan), [
        (bereich: bereich, drehungen: 0),
      ], verlustfrei: true);
      expect(aus.single.endung, '.png');
      final bild = img.decodePng(aus.single.bytes)!;
      expect((bild.width, bild.height), (70, 40));
      for (final (x, y) in [(0, 0), (69, 39), (33, 17)]) {
        expect(
          bild.getPixel(x, y),
          scan.getPixel(x + 10, y + 15),
          reason: 'verlustfrei heisst: derselbe Bildpunkt',
        );
      }
      expect(bild.iccProfile, isNotNull);
    });

    test('mehrere Ausschnitte aus einem Scan, gedreht und ungedreht', () {
      final aus = erzeugeScanAusschnitte(img.encodePng(verlauf()), [
        (bereich: bereich, drehungen: 0),
        (bereich: bereich, drehungen: 1),
      ], verlustfrei: true);
      expect(aus, hasLength(2));
      final gedreht = img.decodePng(aus.last.bytes)!;
      expect((gedreht.width, gedreht.height), (40, 70));
    });

    test('ein JPEG-Scan bleibt JPEG', () {
      final aus = erzeugeScanAusschnitte(img.encodeJpg(verlauf()), [
        (bereich: bereich, drehungen: 0),
      ], verlustfrei: scanVerlustfrei('Scan.JPG'));
      expect(aus.single.endung, '.jpg');
      expect(img.decodeJpg(aus.single.bytes), isNotNull);
      expect(scanVerlustfrei('Scan.tif'), isTrue);
      expect(scanVerlustfrei('Scan.png'), isTrue);
      expect(scanVerlustfrei('scan.jpeg'), isFalse);
    });
  });
}
