import 'package:path/path.dart' as p;

import '../db/database.dart';

/// Kurzes, für Menschen lesbares Format-Kürzel eines Assets (z.B. "JPG",
/// "DNG", "CR3", "HEIC") – für kleine Format-Hinweise in Timeline/
/// Rasteransichten und der Vollbildvorschau. Leer für Videos: dort zeigt
/// bereits ein eigenes Icon "Video"/"Live Photo" an (siehe
/// AssetThumbnailTile), ein zusätzliches Format-Kürzel wäre redundant. Für
/// RAW-Formate (siehe raw_formats.dart) genügt die Dateiendung selbst als
/// Antwort auf "welches RAW-Format" – der generische Fallback unten deckt
/// sie automatisch ab, ohne dass hier ein eigener `case` nötig wäre.
String assetFormatLabel(AssetData asset) =>
    formatKuerzel(asset.type, asset.relativePath);

/// Dasselbe aus den beiden Angaben, die es wirklich braucht.
///
/// Getrennt, seit es neben `AssetData` auch die schmale [Rasterzeile]
/// gibt: Die Rechnung soll einmal dastehen und nicht zweimal.
String formatKuerzel(String type, String relativePath) {
  if (type != 'IMAGE') return '';
  final ext = p.extension(relativePath).toLowerCase();
  switch (ext) {
    case '.jpg':
    case '.jpeg':
      return 'JPG';
    case '.png':
      return 'PNG';
    case '.heic':
    case '.heif':
      return 'HEIC';
    case '.avif':
    case '.avifs':
      return 'AVIF';
    case '.webp':
      return 'WEBP';
    case '.gif':
      return 'GIF';
    case '.bmp':
      return 'BMP';
    case '.tiff':
    case '.tif':
      return 'TIFF';
    case '.dng':
      return 'DNG';
    default:
      return ext.isEmpty ? '' : ext.substring(1).toUpperCase();
  }
}

bool assetHasLocation(AssetData asset) =>
    hatOrt(asset.latitude, asset.longitude);

/// Siehe [formatKuerzel] fuer den Grund der Trennung.
bool hatOrt(double? breite, double? laenge) =>
    breite != null && laenge != null;

/// Ob [asset] ein Panoramafoto ist (sehr breites Seitenverhältnis) – für die
/// Vollbildansicht, die solche Fotos pan-/zoombar statt mit großen
/// Letterbox-Rändern anzeigen soll (siehe AssetViewerScreen). Nutzt die
/// bereits beim Import gespeicherten Originalmaße statt eines eigenen
/// Dekodierens; alte Assets ohne gespeicherte Maße gelten bewusst nicht als
/// Panorama statt eine Annahme zu raten.
bool isPanorama(AssetData asset) =>
    istPanoramaMasse(asset.widthPx, asset.heightPx);

/// Siehe [formatKuerzel] fuer den Grund der Trennung.
bool istPanoramaMasse(int? width, int? height) {
  if (width == null || height == null || height == 0) return false;
  return width / height >= 2.5;
}

/// Enger gefasst als [isPanorama] (>= 2.5): erkennt speziell equirechteckige
/// 360°-Aufnahmen (Seitenverhältnis exakt ~2:1, wie sie 360°-Kameras
/// erzeugen), die eine echte Kugelprojektion statt eines nur horizontal
/// schwenkbaren Streifens brauchen (siehe Panorama360View). Ein solches Foto
/// läge mit 2.0 UNTER der [isPanorama]-Schwelle von 2.5 und würde sonst gar
/// nicht als Sonderfall erkannt.
///
/// Reine Seitenverhältnis-Heuristik – es wird keine GPano-XMP-Metadaten
/// (`GPano:ProjectionType` & Co., das verlässlichere, kamera-geschriebene
/// Signal) ausgewertet, das würde das Extrahieren eingebetteter XMP-Pakete
/// aus JPEGs voraussetzen, was hier (noch) nicht existiert. Bekannte Grenze:
/// ein zufällig exakt 2:1 zugeschnittenes, aber nicht-equirechteckiges Foto
/// würde fälschlich erkannt.
bool isEquirectangular360(AssetData asset) {
  final width = asset.widthPx;
  final height = asset.heightPx;
  if (width == null || height == null || height == 0) return false;
  final ratio = width / height;
  return ratio >= 1.9 && ratio <= 2.1;
}

/// Kamera-Hersteller + -Modell kombiniert – viele Kameras (v.a. Nikon/Canon)
/// wiederholen den Hersteller bereits im Modellnamen (z.B. "Canon EOS R5"),
/// dann reicht die Anzeige des Modells allein.
String? cameraLabel(AssetData asset) {
  final make = asset.cameraMake?.trim();
  final model = asset.cameraModel?.trim();
  if (make == null || make.isEmpty) return (model == null || model.isEmpty) ? null : model;
  if (model == null || model.isEmpty) return make;
  return model.toLowerCase().startsWith(make.toLowerCase()) ? model : '$make $model';
}

String formatFocalLength(double mm) {
  final isWhole = (mm - mm.roundToDouble()).abs() < 0.05;
  return '${isWhole ? mm.toStringAsFixed(0) : mm.toStringAsFixed(1)} mm';
}

String formatFNumber(double f) {
  final isWhole = (f - f.roundToDouble()).abs() < 0.05;
  return 'f/${isWhole ? f.toStringAsFixed(0) : f.toStringAsFixed(1)}';
}

String formatExposureTime(double seconds) {
  if (seconds <= 0) return '$seconds s';
  if (seconds >= 1) {
    final isWhole = (seconds - seconds.roundToDouble()).abs() < 0.01;
    return '${isWhole ? seconds.toStringAsFixed(0) : seconds.toStringAsFixed(1)} s';
  }
  return '1/${(1 / seconds).round()} s';
}

/// Belichtungskorrektur, so geschrieben wie in den Informationen von
/// macOS Fotos: „0 ev", „+0.7 ev", „-1 ev".
///
/// Das Vorzeichen steht auch bei null nicht da – „+0 ev" gäbe es an keiner
/// Kamera. Die Zahl bleibt beim Punkt als Trennzeichen, wie [formatFNumber]
/// und [formatFocalLength] auch: In einer Zeile stünde sonst „f/1.6" neben
/// „0,7 ev".
String formatExposureBias(double ev) {
  final gerundet = (ev * 10).roundToDouble() / 10;
  if (gerundet == 0) return '0 ev';
  final betrag = gerundet.abs();
  final istGanz = (betrag - betrag.roundToDouble()).abs() < 0.05;
  final zahl = istGanz ? betrag.toStringAsFixed(0) : betrag.toStringAsFixed(1);
  return '${gerundet < 0 ? '-' : '+'}$zahl ev';
}

/// Die Aufnahmewerte eines Fotos in der Reihenfolge, in der sie auch macOS
/// Fotos zeigt: ISO, Brennweite, Belichtungskorrektur, Blende, Zeit.
///
/// Als eigene Funktion, nicht in der Ansicht: Welche Angaben eine Kamera
/// überhaupt schreibt, ist von Gerät zu Gerät verschieden – die Reihenfolge
/// und das Auslassen des Fehlenden gehören damit zu den Dingen, die ein Test
/// festhalten sollte.
///
/// Für die Brennweite hat die Kleinbild-äquivalente Angabe Vorrang: Bei
/// Telefonen ist die echte Brennweite (5,7 mm) eine Zahl, mit der niemand
/// etwas anfangen kann.
List<String> aufnahmewerte(AssetData asset) => [
      if (asset.iso != null) 'ISO ${asset.iso}',
      if (asset.focalLength35mm != null)
        formatFocalLength(asset.focalLength35mm!)
      else if (asset.focalLengthMm != null)
        formatFocalLength(asset.focalLengthMm!),
      if (asset.exposureBiasEv != null) formatExposureBias(asset.exposureBiasEv!),
      if (asset.fNumber != null) formatFNumber(asset.fNumber!),
      if (asset.exposureTimeSeconds != null) formatExposureTime(asset.exposureTimeSeconds!),
    ];

/// Kehrt [formatExposureTime] um – akzeptiert sowohl Brüche ("1/125") als
/// auch Dezimalwerte ("0.5" oder "0,5"), für das Belichtungszeit-Feld im
/// Metadaten-Editor. Gibt `null` zurück, wenn der Text leer oder nicht
/// interpretierbar ist.
double? parseExposureTimeInput(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.contains('/')) {
    final parts = trimmed.split('/');
    if (parts.length != 2) return null;
    final a = double.tryParse(parts[0].trim());
    final b = double.tryParse(parts[1].trim());
    if (a == null || b == null || b == 0) return null;
    return a / b;
  }
  return double.tryParse(trimmed.replaceAll(',', '.'));
}
