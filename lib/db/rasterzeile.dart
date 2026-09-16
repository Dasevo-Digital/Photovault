/// **Eine Aufnahme, so schmal wie ein Raster sie braucht.**
///
/// `assets` führt 56 Spalten. Eine Kachelwand fasst zwanzig davon an –
/// die übrigen sechsunddreissig reisen bei jeder Abfrage mit, werden auf
/// ein `AssetData` abgebildet und über die Isolat-Grenze getragen, damit
/// niemand sie ansieht.
///
/// **Gemessen an der gewachsenen Bibliothek** (7307 Zeilen, Schema 71):
///
/// ```
///                                    im Isolat   über die Grenze
/// SELECT * , auf AssetData abgebildet   71,7 ms        80,9 ms
/// SELECT * , roh                        47,0 ms        53,0 ms
/// 19 Spalten, roh                       19,4 ms        27,1 ms
/// nur id, roh                            3,7 ms         4,6 ms
/// ```
///
/// Die überzähligen Spalten kosten also rund achtundzwanzig
/// Millisekunden, das Abbilden auf `AssetData` noch einmal fünfundzwanzig.
/// Beides fällt nicht nur beim Scrollen an, sondern bei **jeder** Änderung
/// an der Tabelle – also während eines Imports oder eines
/// Hintergrundlaufs immer wieder.
///
/// **Warum eine eigene Klasse und kein zurechtgestutztes `AssetData`.**
/// Ein `AssetData`, dessen ungelesene Felder mit Platzhaltern gefüllt
/// wären, sähe an jeder Stelle der App aus wie ein vollständiges – und
/// wer eines der Felder läse, bekäme lautlos eine Lüge. Ein eigener Typ
/// kann gar nicht mehr hergeben, als er weiss.
library;

import 'package:drift/drift.dart' show QueryRow;

import '../services/asset_format.dart';
import 'database.dart';

/// Genau die Spalten, die [Rasterzeile] trägt – als SQL-Liste.
///
/// Sie stehen hier und nicht in der Abfrage, damit Spaltenliste und
/// Klasse nebeneinander liegen: Wer ein Feld ergänzt, sieht beides.
const String rasterSpalten = 'id, type, original_file_name, relative_path, '
    'thumbnail_relative_path, file_created_at, duration_seconds, '
    'is_favorite, is_stack_cover, stack_id, stack_size, linked_asset_id, '
    'rating, color_label, width_px, height_px, latitude, longitude, '
    'camera_make, is_locked';

/// Wer im Raster eigenständig sichtbar ist – als SQL-Bedingung.
///
/// **Das Gegenstück zu `_isPrimaryGridEntry`, und es gehört hierher.**
/// Die Bedingung hat zwei Hälften: kein Live-Photo-Partner (das .mov zu
/// einem Standbild) **und** kein Stapelmitglied ausser dem Titelbild.
/// Von Hand nachgeschrieben stand hier nur die erste – 144 Aufnahmen
/// dieser Bibliothek erschienen dadurch im Raster, obwohl sie hinter
/// ihrem Titelbild liegen sollten, und die Listenansicht daneben
/// blendete dieselben 144 korrekt aus. Eine Bedingung, die an zwei
/// Stellen geschrieben wird, verliert irgendwann an einer davon ihre
/// Hälfte; deshalb steht sie jetzt einmal da.
const String rasterSichtbar = 'is_trashed = 0 AND is_locked = 0 '
    "AND (type = 'IMAGE' OR linked_asset_id IS NULL) "
    'AND (stack_id IS NULL OR is_stack_cover = 1)';

/// Eine Zeile für die Kachelwand.
class Rasterzeile {
  const Rasterzeile({
    required this.id,
    required this.type,
    required this.originalFileName,
    required this.relativePath,
    required this.thumbnailRelativePath,
    required this.fileCreatedAt,
    required this.durationSeconds,
    required this.isFavorite,
    required this.isStackCover,
    required this.stackId,
    required this.stackSize,
    required this.linkedAssetId,
    required this.rating,
    required this.colorLabel,
    required this.widthPx,
    required this.heightPx,
    required this.latitude,
    required this.longitude,
    required this.cameraMake,
    required this.isLocked,
  });

  final String id;
  final String type;
  final String originalFileName;
  final String relativePath;
  final String? thumbnailRelativePath;
  final DateTime fileCreatedAt;
  final double? durationSeconds;
  final bool isFavorite;
  final bool isStackCover;
  final String? stackId;
  final int? stackSize;
  final String? linkedAssetId;
  final int rating;
  final String? colorLabel;
  final int? widthPx;
  final int? heightPx;
  final double? latitude;
  final double? longitude;
  final String? cameraMake;
  final bool isLocked;

  /// Aus einer vollen Zeile – für die Bildschirme, die ohnehin schon
  /// `AssetData` in der Hand halten (Alben, Suche, Personen und die
  /// anderen). Sie gewinnen nichts, verlieren aber auch nichts: Die
  /// Umwandlung ist ein Feldzugriff je Spalte.
  factory Rasterzeile.aus(AssetData a) => Rasterzeile(
        id: a.id,
        type: a.type,
        originalFileName: a.originalFileName,
        relativePath: a.relativePath,
        thumbnailRelativePath: a.thumbnailRelativePath,
        fileCreatedAt: a.fileCreatedAt,
        durationSeconds: a.durationSeconds,
        isFavorite: a.isFavorite,
        isStackCover: a.isStackCover,
        stackId: a.stackId,
        stackSize: a.stackSize,
        linkedAssetId: a.linkedAssetId,
        rating: a.rating,
        colorLabel: a.colorLabel,
        widthPx: a.widthPx,
        heightPx: a.heightPx,
        latitude: a.latitude,
        longitude: a.longitude,
        cameraMake: a.cameraMake,
        isLocked: a.isLocked,
      );

  /// Aus einer rohen Abfragezeile – der Weg, um dessentwillen es diese
  /// Klasse gibt.
  ///
  /// `file_created_at` liegt als **Sekunden** in der Datenbank, nicht als
  /// Millisekunden; drift legt `DateTimeColumn` standardmässig so ab. Wer
  /// hier `fromMillisecondsSinceEpoch` schriebe, bekäme das Jahr 1970 –
  /// und alle Aufnahmen in einer einzigen Monatsgruppe.
  factory Rasterzeile.ausZeile(QueryRow r) => Rasterzeile(
        id: r.read<String>('id'),
        type: r.read<String>('type'),
        originalFileName: r.read<String>('original_file_name'),
        relativePath: r.read<String>('relative_path'),
        thumbnailRelativePath: r.readNullable<String>('thumbnail_relative_path'),
        fileCreatedAt: DateTime.fromMillisecondsSinceEpoch(
            r.read<int>('file_created_at') * 1000),
        durationSeconds: r.readNullable<double>('duration_seconds'),
        isFavorite: r.read<int>('is_favorite') != 0,
        isStackCover: r.read<int>('is_stack_cover') != 0,
        stackId: r.readNullable<String>('stack_id'),
        stackSize: r.readNullable<int>('stack_size'),
        linkedAssetId: r.readNullable<String>('linked_asset_id'),
        rating: r.read<int>('rating'),
        colorLabel: r.readNullable<String>('color_label'),
        widthPx: r.readNullable<int>('width_px'),
        heightPx: r.readNullable<int>('height_px'),
        latitude: r.readNullable<double>('latitude'),
        longitude: r.readNullable<double>('longitude'),
        cameraMake: r.readNullable<String>('camera_make'),
        isLocked: r.read<int>('is_locked') != 0,
      );

  /// Das Format-Kürzel für die Kachel – dieselbe Rechnung wie für eine
  /// volle Zeile, siehe [formatKuerzel].
  String get kuerzel => formatKuerzel(type, relativePath);

  /// Ob ein Ort hinterlegt ist.
  bool get verortet => hatOrt(latitude, longitude);

  // **Kein eigenes `==`.** Es laege nahe, zwei Zeilen mit derselben
  // Kennung gleich zu nennen – und genau das waere die Falle: Nach dem
  // Setzen eines Favoritensterns kaeme eine neue Zeile mit demselben `id`
  // und anderem `isFavorite`, und ein Vergleich zweier Listen fiele auf
  // „nichts geaendert" herein. Die Auswahl arbeitet ohnehin mit
  // Kennungen (siehe Rasterbedienung), nicht mit Objekten.
}
