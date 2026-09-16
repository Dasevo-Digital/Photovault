import 'package:flutter/services.dart';

/// Ergebnis von [SecurityScopedBookmark.pickFolderAndCreateBookmark].
class PickedFolder {
  final String path;
  final String bookmark;
  const PickedFolder(this.path, this.bookmark);
}

/// Dart-Anbindung an `LibraryLocationChannel` (macOS/Swift): zeigt einen
/// nativen Ordnerauswahl-Dialog und löst gespeicherte "Security-Scoped
/// Bookmarks" wieder auf – die von Apple vorgesehene Methode, um den
/// Sandbox-Zugriff auf einen vom Nutzer gewählten Ordner über einen
/// App-Neustart hinweg zu behalten (siehe
/// native/macos_library_location/LibraryLocationChannel.swift für Details,
/// insbesondere warum Auswahl und Bookmark-Erzeugung dort atomar in einem
/// nativen Aufruf passieren müssen).
class SecurityScopedBookmark {
  static const _channel = MethodChannel('photo_vault/library_location');

  /// Zeigt einen nativen Ordnerauswahl-Dialog und erzeugt in einem Schritt
  /// ein dauerhaftes Bookmark für den gewählten Ordner. Gibt `null` zurück,
  /// falls der Nutzer abgebrochen hat, die native Anbindung fehlt oder die
  /// Bookmark-Erzeugung scheitert.
  static Future<PickedFolder?> pickFolderAndCreateBookmark({String? message}) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'pickFolderAndCreateBookmark',
        {'message': message},
      );
      if (result == null) return null;
      final path = result['path'] as String?;
      final bookmark = result['bookmark'] as String?;
      if (path == null || bookmark == null) return null;
      return PickedFolder(path, bookmark);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Löst ein zuvor erzeugtes Bookmark auf und stellt den Sandbox-Zugriff
  /// wieder her – liefert den aufgelösten Pfad, oder `null`, falls das
  /// Bookmark ungültig geworden ist (z.B. Ordner gelöscht/umbenannt oder
  /// Laufwerk nicht eingebunden) oder die native Anbindung fehlt.
  static Future<String?> resolve(String bookmarkBase64) async {
    try {
      return await _channel.invokeMethod<String>('resolveBookmark', {'bookmark': bookmarkBase64});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
