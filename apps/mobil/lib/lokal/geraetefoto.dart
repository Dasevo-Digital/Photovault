import 'package:kern/db/database.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../bilder.dart';
import '../sicherung/dienst.dart';

/// Fotos, die noch auf diesem Telefon liegen, zeigt der Betrachter von dort
/// (#330): Sie sind sofort da, in voller Auflösung und ohne Netz. Vom Server
/// kämen erst die Vorschau und beim Zoomen eine Wandlung.
///
/// Welches Foto des Telefons zu einer Aufnahme gehört, weiss die Sicherung.
/// Vom Server kommt es weiterhin, wenn
/// - es dort entwickelt oder restauriert ist: gezeigt wird die neue Fassung;
/// - es hier seit der Sicherung bearbeitet wurde: Die Gesichtsrahmen und alle
///   Angaben gehören zum Foto auf dem Server;
/// - sein Original nur in iCloud liegt: Vom Server ist es dann schneller als
///   aus iCloud.
class Geraetefotos {
  Geraetefotos(this._sicherung);

  final Sicherungsdienst _sicherung;

  /// Woher der Betrachter [a] nimmt, wenn es hier liegt, sonst `null`.
  /// [kante] ist die lange Seite des Bildschirms in Pixeln.
  Future<Bildquelle?> quelle(AssetData a, int kante) async {
    if (!kommtInFrage(a)) return null;
    final g = _sicherung.gesichertAls(a.id);
    if (g == null) return null;
    try {
      final e = await AssetEntity.fromId(g.lokal);
      if (e == null || e.type != AssetType.image) return null;
      if (e.modifiedDateTime.millisecondsSinceEpoch != g.geaendert) return null;
      if (!await e.isLocallyAvailable()) return null;
      return Bildquelle(
        ansicht: AssetEntityImageProvider(
          e,
          isOriginal: false,
          thumbnailSize: ThumbnailSize.square(kante),
        ),
        zoom: AssetEntityImageProvider(e),
      );
    } on Object {
      // Kein Zugriff auf die Mediathek oder ein Foto, das gerade verschwand.
      return null;
    }
  }

  /// Ob das Foto auf dem Telefon dasselbe zeigte wie der Server.
  static bool kommtInFrage(AssetData a) =>
      a.type == 'IMAGE' &&
      a.restoredRelativePath == null &&
      a.developedRelativePath == null;
}
