import 'package:kern/db/rasterzeile.dart';

/// Eine Zeile des Rasters, wie die Schnittstelle sie ausgibt – für die
/// Zeitleiste, Alben, Personen und die Suche dieselbe Form.
Map<String, Object?> zeileAlsJson(Rasterzeile r) => {
  'id': r.id,
  'art': r.type == 'VIDEO' ? 'video' : 'bild',
  'name': r.originalFileName,
  'aufgenommen': r.fileCreatedAt.toIso8601String(),
  if (r.durationSeconds != null) 'dauer': r.durationSeconds,
  if (r.isFavorite) 'favorit': true,
  if (r.rating > 0) 'bewertung': r.rating,
  if (r.colorLabel != null) 'farbe': r.colorLabel,
  if (r.widthPx != null) 'breite': r.widthPx,
  if (r.heightPx != null) 'hoehe': r.heightPx,
  if (r.latitude != null && r.longitude != null)
    'ort': {'breite': r.latitude, 'laenge': r.longitude},
  if (r.cameraMake != null) 'kamera': r.cameraMake,
  if (r.stackId != null)
    'serie': {'id': r.stackId, 'titel': r.isStackCover, 'groesse': r.stackSize},
  if (r.linkedAssetId != null) 'partner': r.linkedAssetId,
  // Das Kürzel oben rechts auf der Kachel, wie am Rechner.
  if (r.kuerzel.isNotEmpty) 'format': r.kuerzel,
  'miniatur': r.thumbnailRelativePath != null,
};
