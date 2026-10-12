/// Ein Bild aus seinen Bytes, für die Auswertungen.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Reine Top-Level-Funktion für `berechne()` (siehe `Auswertungen.dekodiere`
/// – dasselbe Muster wie `decodeAndResizeThumbnail` in `import_service.dart`).
/// Das Decodieren einer vollen JPEG/HEIC-Vorschau ist für große Fotos die mit
/// Abstand teuerste Einzeloperation vor Gesichtserkennung/CLIP-Einbettung
/// (oft 100+ ms) – lief bisher synchron auf dem Haupt-Isolate und blockierte
/// damit beim Import oder Backfill vieler Fotos hintereinander spürbar die
/// UI. Gibt `null` zurück, wenn die Bytes nicht dekodierbar sind (z.B.
/// beschädigte Datei).
///
/// **Hier wird ohne Deckel dekodiert, und das ist Absicht.** Gemessen an der
/// Prüfbibliothek (19. Prüfrunde):
///
/// ```
/// 20383 × 4077  dekodieren 1442 ms   Arbeitssatz 301 -> 1205 MB
/// 16350 × 3788  dekodieren 1376 ms   Arbeitssatz      ->  981 MB
///  3456 × 5184  dekodieren  755 ms
/// laenger als 4096 Punkte: 1062 von 5784 Aufnahmen ohne Vorschaudatei
/// ```
///
/// Ein Deckel wie bei der Anzeige (`begrenztesBild`) würde diese Spitze
/// nehmen, aber die Ergebnisse ändern: YuNet fände auf einem verkleinerten
/// Bild andere – kleinere – Gesichter, und die Bibliothek bestünde danach
/// aus zwei Beständen, einem vor und einem nach dem Deckel. Die Spitze ist
/// vorübergehend, tritt je Foto einzeln auf und wird mit dem Isolat wieder
/// freigegeben; die Uneinheitlichkeit wäre dauerhaft. Deshalb gemessen,
/// notiert und nicht geändert.
///
/// Die Übergabe an ein weiteres `compute()` (etwa
/// `compute(computeBlurScore, decoded)`) ist dagegen kein Posten: gemessen
/// 28 ms Aufschlag bei 249 MB Bilddaten, bei kleineren Aufnahmen unter der
/// Messgenauigkeit.
img.Image? decodeImageBytes(Uint8List bytes) {
  try {
    return img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
}
