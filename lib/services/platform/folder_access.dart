import 'dart:io';

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
