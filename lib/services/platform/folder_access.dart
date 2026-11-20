import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;

import 'folder_access_desktop.dart';
import 'folder_access_macos.dart';

/// Ein vom Nutzer gewählter Bibliotheksordner.
///
/// [token] ist ein plattformabhängiges Zugriffs-Merkmal, das nötig ist, um
/// den Ordner nach einem App-Neustart wieder öffnen zu dürfen. Unter macOS
/// steht dort ein Security-Scoped Bookmark (Base64); unter Linux/Windows
/// gibt es kein Sandbox-Konzept dieser Art, dort bleibt es leer und allein
/// [path] zählt.
class PickedFolder {
  final String path;
  final String token;
  const PickedFolder(this.path, this.token);

  static const _praefix = 'pv-unterordner:1:';
  static bool _relativ(String wert) =>
      wert.isNotEmpty &&
      wert.length <= 4096 &&
      !p.isAbsolute(wert) &&
      !wert.contains('\u0000') &&
      !wert.contains(r'\') &&
      !wert.contains(':') &&
      !p.split(p.normalize(wert)).contains('..') &&
      p.normalize(wert) != '.';

  /// Ein neu angelegter Unterordner erbt ausschließlich den ausdrücklich
  /// gewählten Elternzugriff. Der gespeicherte Zielpfad bleibt eindeutig.
  PickedFolder unterordner(String relativ) {
    if (!_relativ(relativ)) throw const FormatException('pv_ordner_unterpfad');
    final vorher = teilzugriff(token);
    final ziel = p.normalize(p.join(vorher?.relativ ?? '', relativ));
    if (!_relativ(ziel)) throw const FormatException('pv_ordner_unterpfad');
    return PickedFolder(
      p.join(path, relativ),
      token.isEmpty
          ? ''
          : '$_praefix${base64Url.encode(utf8.encode(jsonEncode({'token': vorher?.token ?? token, 'relativ': ziel})))}',
    );
  }

  static ({String token, String relativ})? teilzugriff(String token) {
    if (!token.startsWith(_praefix)) return null;
    if (token.length > 1024 * 1024) {
      throw const FormatException('pv_ordner_zugriff');
    }
    final j =
        jsonDecode(
              utf8.decode(base64Url.decode(token.substring(_praefix.length))),
            )
            as Map;
    final basis = j['token'] as String, rel = j['relativ'] as String;
    if (j.length != 2 ||
        basis.isEmpty ||
        basis.startsWith(_praefix) ||
        !_relativ(rel)) {
      throw const FormatException('pv_ordner_zugriff');
    }
    return (token: basis, relativ: rel);
  }
}

/// Plattformabhängiger Zugriff auf einen frei gewählten Bibliotheksordner.
///
/// Diese Abstraktion existiert, weil macOS als einzige Zielplattform eine
/// App-Sandbox mit Security-Scoped Bookmarks verlangt: der Zugriff auf einen
/// Ordner außerhalb des App-Containers erlischt dort bei jedem Neustart und
/// muss aus einem gespeicherten Bookmark wiederhergestellt werden. Unter
/// Linux und Windows genügt der bloße Pfad.
///
/// Ohne diese Trennung würde [LibraryLocation] fest an den macOS-Kanal
/// gebunden bleiben – auf Linux/Windows ließe sich dann gar kein
/// Bibliotheksordner wählen, die App wäre dort unbenutzbar.
abstract class FolderAccess {
  /// Zeigt einen Ordnerauswahl-Dialog. Gibt `null` zurück, wenn der Nutzer
  /// abbricht oder die Auswahl fehlschlägt.
  Future<PickedFolder?> pickFolder({String? message});

  /// Stellt den Zugriff auf einen früher gewählten Ordner wieder her.
  ///
  /// Bekommt beides, was gespeichert wurde: den zuletzt bekannten [path] und
  /// das [token] aus [PickedFolder]. Liefert den nutzbaren Pfad, oder `null`,
  /// wenn der Ordner nicht mehr erreichbar ist (gelöscht, umbenannt,
  /// Laufwerk nicht eingebunden) – die Aufrufer fallen dann auf den
  /// Standardordner zurück, statt den Start zu verweigern.
  Future<String?> resolveRoot({String? path, String? token});

  /// Ob diese Plattform ein Zugriffs-Token braucht (nur macOS). Rein
  /// informativ, z.B. für Diagnoseausgaben.
  bool get usesAccessToken;

  /// Die zur laufenden Plattform passende Umsetzung.
  static FolderAccess forCurrentPlatform() {
    if (Platform.isMacOS) return const MacOsFolderAccess();
    return const DesktopFolderAccess();
  }
}
