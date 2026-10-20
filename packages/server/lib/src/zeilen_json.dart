import 'package:kern/db/database.dart' show FaceData;
import 'package:kern/db/listenangaben.dart';
import 'package:kern/db/rasterzeile.dart';

/// Was die Liste über die Kachel hinaus zeigt (Issue #195) – nur, wenn
/// der Browser die Liste zeigt (`voll=1`).
Map<String, Object?> listenangabenAlsJson(Listenangaben l) => {
  'modell': ?l.kameramodell,
  'objektiv': ?l.objektiv,
  'brennweite': ?l.brennweite,
  'blende': ?l.blende,
  'zeit': ?l.zeit,
  'iso': ?l.iso,
  if (l.bytes > 0) 'bytes': l.bytes,
  'stadt': ?l.stadt,
  'land': ?l.land,
  if (l.geschaetzt) 'geschaetzt': true,
};

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

/// Wo ein Gesicht im Foto sitzt: links, oben, Breite, Höhe – als Anteile
/// des Bildes (0..1), wie in der Datenbank. Gilt für Vorschau und Original
/// gleichermassen.
List<double> gesichtskasten(FaceData f) => [f.boxX, f.boxY, f.boxW, f.boxH];
