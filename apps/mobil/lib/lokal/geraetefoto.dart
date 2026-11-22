import 'dart:io';

import 'package:kern/db/database.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../bilder.dart';
import '../sicherung/dienst.dart';

/// Fotos, die noch auf diesem Telefon liegen, zeigt der Betrachter von dort
/// (#330): Sie sind sofort da, in voller Auflösung und ohne Netz. Vom Server
/// kämen erst die Vorschau und beim Zoomen eine Wandlung. Videos ebenso
/// ([videoQuelle], #437).
///
/// Welches Foto des Telefons zu einer Aufnahme gehört, weiss die Sicherung.
/// Vom Server kommt es weiterhin, wenn
/// - es dort entwickelt oder restauriert ist: gezeigt wird die neue Fassung;
/// - es dort bearbeitet wurde (zugeschnitten, gedreht, retuschiert): Die
///   Aufnahme behält ihre Kennung und bekommt eine neue Datei (#437);
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
    if (g == null || !zeigtDasselbe(a, g.pruefsumme)) return null;
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

  /// Woher der Spieler das Video [a] nimmt, wenn es unverändert und ganz
  /// auf diesem Telefon liegt, sonst `null` (#437): unter Android eine
  /// Content-URI, unter iOS eine Datei-URL – ohne Kopie in den
  /// Zwischenspeicher. Vom Server lief ein eigenes, frisch gesichertes
  /// 4K-Video sonst über den Upload daheim und das Datenvolumen, startete
  /// langsam, und schwere Videos fielen auf die leichte Fassung zurück.
  Future<Uri?> videoQuelle(AssetData a) async {
    final g = _sicherung.gesichertAls(a.id);
    if (g == null || !videoKommtInFrage(a, g.pruefsumme)) return null;
    try {
      final e = await AssetEntity.fromId(g.lokal);
      if (e == null || e.type != AssetType.video) return null;
      if (e.modifiedDateTime.millisecondsSinceEpoch != g.geaendert) return null;
      if (!await e.isLocallyAvailable(isOrigin: true)) return null;
      // In der Fotos-App bearbeitet: Die URL spielte die Bearbeitung, auf
      // dem Server liegt nur das Original.
      if (Platform.isIOS && await e.darwin.hasAdjustments) return null;
      final url = await e.getMediaUrl();
      return url == null ? null : Uri.parse(url);
    } on Object {
      return null;
    }
  }

  /// Ob das Video [a] vom Telefon kommen kann: nicht auf dem Server
  /// gekürzt und dort noch die Datei, die vom Telefon kam ([zeigtDasselbe]).
  static bool videoKommtInFrage(AssetData a, String? pruefsumme) =>
      a.type == 'VIDEO' &&
      a.trimmedRelativePath == null &&
      zeigtDasselbe(a, pruefsumme);

  /// Ob das Foto auf dem Telefon dasselbe zeigte wie der Server.
  static bool kommtInFrage(AssetData a) =>
      a.type == 'IMAGE' &&
      a.restoredRelativePath == null &&
      a.developedRelativePath == null;

  /// Ob die Datei auf dem Server noch die ist, die vom Telefon kam:
  /// dieselbe Prüfsumme wie bei der Sicherung ([pruefsumme]). Am Rechner
  /// oder im Browser bearbeitet, hat sie eine neue. Einträge von vor 0.20
  /// kennen keine Prüfsumme; dann verrät der Variantenstapel die
  /// Bearbeitung (das Original liegt als Variante dahinter, #248).
  static bool zeigtDasselbe(AssetData a, String? pruefsumme) =>
      pruefsumme == null
      ? !istVariantenstapel(a.stackId)
      : pruefsumme == a.checksum;
}
