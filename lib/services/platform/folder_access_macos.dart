import '../security_scoped_bookmark.dart' as native;
import 'folder_access.dart';

/// macOS-Umsetzung: Ordnerauswahl und Zugriff laufen über Security-Scoped
/// Bookmarks (siehe macos/Runner/LibraryLocationChannel.swift).
///
/// Der gespeicherte Pfad allein genügt hier NICHT – die App-Sandbox entzieht
/// den Zugriff bei jedem Neustart, nur das Bookmark stellt ihn wieder her.
/// Deshalb wird [path] hier bewusst ignoriert.
class MacOsFolderAccess implements FolderAccess {
  const MacOsFolderAccess();

  @override
  bool get usesAccessToken => true;

  @override
  Future<PickedFolder?> pickFolder({String? message}) async {
    final picked = await native.SecurityScopedBookmark.pickFolderAndCreateBookmark(message: message);
    if (picked == null) return null;
    return PickedFolder(picked.path, picked.bookmark);
  }

  @override
  Future<String?> resolveRoot({String? path, String? token}) async {
    if (token == null || token.isEmpty) return null;
    return native.SecurityScopedBookmark.resolve(token);
  }
}
