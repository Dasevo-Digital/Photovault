import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'folder_access.dart';

/// Linux-/Windows-Umsetzung: dort gibt es keine App-Sandbox, die den Zugriff
/// auf einen gewählten Ordner nach einem Neustart entziehen würde – der
/// gespeicherte Pfad genügt, ein Zugriffs-Token wird nicht gebraucht.
///
/// Die Ordnerauswahl übernimmt `file_picker`, das auf beiden Plattformen den
/// jeweils systemeigenen Dialog nutzt (GTK bzw. den Windows-Shell-Dialog)
/// und dafür keinen plattformspezifischen Code im Projekt selbst braucht.
class DesktopFolderAccess implements FolderAccess {
  const DesktopFolderAccess();

  @override
  bool get usesAccessToken => false;

  @override
  Future<PickedFolder?> pickFolder({String? message}) async {
    try {
      final path = await FilePicker.platform.getDirectoryPath(dialogTitle: message);
      if (path == null) return null;
      return PickedFolder(path, '');
    } catch (_) {
      // Kein Dialog verfügbar (z.B. fehlendes GTK/Portal unter Linux) – wie
      // ein Abbruch behandeln, statt die aufrufende UI mit einem Fehler zu
      // belasten.
      return null;
    }
  }

  @override
  Future<String?> resolveRoot({String? path, String? token}) async {
    if (path == null || path.isEmpty) return null;
    // Ohne Sandbox zählt nur, ob der Ordner überhaupt (noch) existiert –
    // z.B. eine nicht eingehängte externe Platte liefert hier false, und der
    // Aufrufer fällt auf den Standardordner zurück.
    return await Directory(path).exists() ? path : null;
  }
}
