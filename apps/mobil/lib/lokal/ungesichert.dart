import 'package:flutter/widgets.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../sicherung/kamerarolle.dart';

/// Eine Aufnahme, die nur auf dem Telefon liegt – noch nicht auf dem
/// Server (Issue #127). In der Zeitleiste steht sie zwischen den anderen,
/// mit einer Wolke, die ihr fehlt.
class LokaleAufnahme {
  const LokaleAufnahme({
    required this.id,
    required this.aufgenommen,
    required this.video,
    this.entity,
  });

  factory LokaleAufnahme.aus(Rolleneintrag e) => LokaleAufnahme(
    id: e.id,
    aufgenommen: e.aufgenommen,
    video: e.video,
    entity: e.quelle is AssetEntity ? e.quelle! as AssetEntity : null,
  );

  /// Die Kennung auf dem Telefon.
  final String id;
  final DateTime aufgenommen;
  final bool video;

  /// Der Eintrag der Fotomediathek dahinter; `null` ohne Telefon (Tests).
  final AssetEntity? entity;

  /// Womit Zeilen aus dem Telefon in einer Liste von Server-Zeilen
  /// beginnen – so stossen die Kennungen nie zusammen.
  static const vorsatz = 'lokal:';

  String get kennung => '$vorsatz$id';

  /// Die Miniatur aus der Fotomediathek; `null` ohne Telefon.
  ImageProvider? get bild => entity == null
      ? null
      : AssetEntityImageProvider(
          entity!,
          isOriginal: false,
          thumbnailSize: const ThumbnailSize.square(400),
        );

  /// Als Zeile fürs Raster – ohne Pfade, die gibt es für sie nicht.
  Rasterzeile get zeile => Rasterzeile(
    id: kennung,
    type: video ? 'VIDEO' : 'IMAGE',
    originalFileName: '',
    relativePath: '',
    thumbnailRelativePath: null,
    fileCreatedAt: aufgenommen,
    durationSeconds: null,
    isFavorite: false,
    isStackCover: false,
    stackId: null,
    stackSize: null,
    linkedAssetId: null,
    rating: 0,
    colorLabel: null,
    widthPx: null,
    heightPx: null,
    latitude: null,
    longitude: null,
    cameraMake: null,
    isLocked: false,
  );
}

/// Was von [alle] noch nicht sicher ist: nicht erledigt, oder seit der
/// Sicherung bearbeitet. Abgelehntes zählt mit – es liegt ja wirklich
/// nicht auf dem Server.
List<LokaleAufnahme> nochNichtGesichert(
  List<Rolleneintrag> alle,
  Map<String, int> erledigt,
) => [
  for (final e in alle)
    if (erledigt[e.id] != e.geaendert.millisecondsSinceEpoch)
      LokaleAufnahme.aus(e),
];

/// Reiht Telefon-Aufnahmen zwischen die Server-Zeilen, beide nach Datum
/// absteigend. Liefert die Zeilen und dazu, welche vom Telefon sind.
({List<Rasterzeile> zeilen, Map<String, LokaleAufnahme> lokal}) mischeMitServer(
  List<Rasterzeile> server,
  List<LokaleAufnahme> lokal,
) {
  if (lokal.isEmpty) return (zeilen: server, lokal: const {});
  final sortiert = [...lokal]
    ..sort((a, b) => b.aufgenommen.compareTo(a.aufgenommen));
  final zeilen = <Rasterzeile>[];
  var i = 0;
  var j = 0;
  while (i < server.length || j < sortiert.length) {
    final s = i < server.length ? server[i] : null;
    final l = j < sortiert.length ? sortiert[j] : null;
    if (l == null || (s != null && !s.fileCreatedAt.isBefore(l.aufgenommen))) {
      zeilen.add(s!);
      i++;
    } else {
      zeilen.add(l.zeile);
      j++;
    }
  }
  return (zeilen: zeilen, lokal: {for (final l in sortiert) l.kennung: l});
}
