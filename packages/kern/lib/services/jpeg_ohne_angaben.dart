import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// [bild] als JPEG ohne die Angaben seines Originals (#380).
///
/// `encodeJpg` schreibt den EXIF-Anhang wieder hinaus, den `decodeImage`
/// gelesen hat – samt Aufnahmeort, Kamera und Seriennummer. `copyResize`
/// und `copyCrop` reichen ihn weiter. Miniaturen, Vorschauen und
/// Gesichtsausschnitte gehen aber an andere Geräte, in den Browser und in
/// Sicherungen; dort hält sie niemand für das Foto selbst, und den Ort
/// trägt die Datenbank. Bis 3.67.5 kam er mit.
///
/// Die Lage wird vorher eingebacken, sonst stünde ein hochkant gehaltenes
/// Foto ohne EXIF quer. Das Farbprofil bleibt. [bild] selbst behält seine
/// Angaben.
Uint8List jpegOhneAngaben(img.Image bild, {required int quality}) {
  final lage = bild.exif.imageIfd;
  if (lage.hasOrientation && lage.orientation != 1) {
    final gedreht = img.bakeOrientation(bild)..exif = img.ExifData();
    return img.encodeJpg(gedreht, quality: quality);
  }
  final angaben = bild.exif;
  bild.exif = img.ExifData();
  try {
    return img.encodeJpg(bild, quality: quality);
  } finally {
    bild.exif = angaben;
  }
}
