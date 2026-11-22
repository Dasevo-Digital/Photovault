import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:photo_vault_server/src/ohne_ort.dart';
import 'package:test/test.dart';

/// Ein JPEG mit Ort, Drehung, Kamera und Aufnahmezeit – wie vom Telefon.
Uint8List jpegMitOrt({int orientation = 6}) {
  final bild = img.Image(width: 40, height: 24);
  img.fill(bild, color: img.ColorRgb8(30, 140, 220));
  bild.exif.imageIfd.make = 'Kamera-Hersteller';
  bild.exif.imageIfd.model = 'Kamera-Modell';
  bild.exif.imageIfd.orientation = orientation;
  bild.exif.exifIfd['DateTimeOriginal'] = img.IfdValueAscii(
    '2025:09:11 12:00:00',
  );
  final gps = bild.exif.gpsIfd;
  gps[1] = img.IfdValueAscii('N');
  gps[2] = img.IfdValueRational(54, 1)
    ..value.addAll(img.IfdValueRational(19, 1).value)
    ..value.addAll(img.IfdValueRational(123456, 10000).value);
  gps[3] = img.IfdValueAscii('E');
  gps[4] = img.IfdValueRational(10, 1)
    ..value.addAll(img.IfdValueRational(7, 1).value)
    ..value.addAll(img.IfdValueRational(654321, 10000).value);
  return Uint8List.fromList(img.encodeJpg(bild, quality: 90));
}

/// [jpeg] mit einem Segment [marker] direkt hinter SOI.
Uint8List mitSegment(Uint8List jpeg, int marker, List<int> inhalt) {
  final laenge = inhalt.length + 2;
  return Uint8List.fromList([
    0xFF,
    0xD8,
    0xFF,
    marker,
    laenge >> 8,
    laenge & 0xFF,
    ...inhalt,
    ...jpeg.sublist(2),
  ]);
}

/// Ob [nadel] in [heu] vorkommt.
bool enthaelt(List<int> heu, List<int> nadel) {
  outer:
  for (var i = 0; i + nadel.length <= heu.length; i++) {
    for (var k = 0; k < nadel.length; k++) {
      if (heu[i + k] != nadel[k]) continue outer;
    }
    return true;
  }
  return false;
}

void main() {
  test('der GPS-Teil ist leer, Drehung, Kamera und Zeit bleiben', () {
    final roh = jpegMitOrt();
    expect(img.decodeJpgExif(roh)!.gpsIfd.isEmpty, isFalse);
    final aus = jpegOhneOrt(roh);
    final exif = img.decodeJpgExif(aus)!;
    expect(exif.gpsIfd.isEmpty, isTrue);
    expect(exif.imageIfd.orientation, 6);
    expect(exif.imageIfd.make, 'Kamera-Hersteller');
    expect(exif.imageIfd.model, 'Kamera-Modell');
    expect(exif.exifIfd['DateTimeOriginal']?.toString(), '2025:09:11 12:00:00');
    // Die Bilddaten selbst: unverändert, nichts neu gerechnet.
    expect(aus.length, roh.length);
    final a = img.decodeJpg(aus)!, b = img.decodeJpg(roh)!;
    expect(a.getPixel(5, 5), b.getPixel(5, 5));
    // Die Grad stehen nirgends mehr (vorher in einer der beiden
    // Bytereihenfolgen).
    const mm = [0, 0, 0, 54, 0, 0, 0, 1], ii = [54, 0, 0, 0, 1, 0, 0, 0];
    expect(enthaelt(roh, mm) || enthaelt(roh, ii), isTrue);
    expect(enthaelt(aus, mm) || enthaelt(aus, ii), isFalse);
  });

  test('XMP, IPTC und angehängte Bilder gehen, das Farbprofil bleibt', () {
    final roh = jpegMitOrt();
    final xmp = utf8.encode(
      'http://ns.adobe.com/xap/1.0/\u0000'
      '<x:xmpmeta><exif:GPSLatitude>54,19.2N</exif:GPSLatitude></x:xmpmeta>',
    );
    final icc = [...utf8.encode('ICC_PROFILE\u0000'), 1, 1, 1, 2, 3, 4];
    final iptc = [
      ...utf8.encode('Photoshop 3.0\u0000'),
      ...utf8.encode('8BIM Beispielhausen'),
    ];
    var mit = mitSegment(roh, 0xE1, xmp);
    mit = mitSegment(mit, 0xE2, icc);
    mit = mitSegment(mit, 0xED, iptc);
    // Ein zweites Bild dahinter, wie die Tiefenkarte eines Telefons.
    mit = Uint8List.fromList([...mit, ...jpegMitOrt(orientation: 1)]);
    final aus = jpegOhneOrt(mit);
    expect(enthaelt(aus, utf8.encode('GPSLatitude')), isFalse);
    expect(enthaelt(aus, utf8.encode('Beispielhausen')), isFalse);
    expect(enthaelt(aus, utf8.encode('ICC_PROFILE')), isTrue);
    expect(aus.length, lessThan(roh.length + icc.length + 10));
    expect(aus.sublist(aus.length - 2), [0xFF, 0xD9]);
    expect(img.decodeJpgExif(aus)!.gpsIfd.isEmpty, isTrue);
    expect(img.decodeJpg(aus), isNotNull);
  });

  test('Motorola-Reihenfolge (MM) und ein JPEG ohne EXIF', () {
    // Ein EXIF-Block in grosser Bytereihenfolge, von Hand gebaut: IFD0 mit
    // einem Verweis auf den GPS-Teil, darin Breite als RATIONAL[3].
    final tiff = <int>[
      0x4D, 0x4D, 0, 42, 0, 0, 0, 8, // Kopf, IFD0 bei 8
      0, 1, // ein Eintrag
      0x88, 0x25, 0, 4, 0, 0, 0, 1, 0, 0, 0, 26, // GPSInfo → 26
      0, 0, 0, 0, // kein weiteres IFD
      0, 1, // GPS: ein Eintrag (bei 26)
      0, 2, 0, 5, 0, 0, 0, 3, 0, 0, 0, 44, // GPSLatitude → 44
      0, 0, 0, 0,
      0, 0, 0, 54, 0, 0, 0, 1, 0, 0, 0, 19, 0, 0, 0, 1, 0, 0, 0, 7, 0, 0, 0, 1,
    ];
    final ohne = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 8, height: 8)),
    );
    final mit = mitSegment(ohne, 0xE1, [
      0x45, 0x78, 0x69, 0x66, 0, 0, //
      ...tiff,
    ]);
    final aus = jpegOhneOrt(mit);
    expect(enthaelt(aus, const [0, 0, 0, 54, 0, 0, 0, 1]), isFalse);
    expect(enthaelt(aus, const [0x88, 0x25]), isTrue, reason: 'Verweis bleibt');
    expect(jpegOhneOrt(ohne), ohne);
  });

  test('kein JPEG oder abgeschnitten: FormatException', () {
    expect(
      () => jpegOhneOrt(Uint8List.fromList(utf8.encode('kein Bild'))),
      throwsFormatException,
    );
    final roh = jpegMitOrt();
    expect(
      () => jpegOhneOrt(Uint8List.sublistView(roh, 0, roh.length ~/ 2)),
      throwsFormatException,
    );
  });
}
