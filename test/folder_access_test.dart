import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/platform/folder_access.dart';
import 'package:photo_vault/services/platform/folder_access_desktop.dart';

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('photo_vault_folder_access_');
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  group('DesktopFolderAccess (Linux/Windows)', () {
    const access = DesktopFolderAccess();

    test('braucht kein Zugriffs-Token – anders als macOS', () {
      expect(access.usesAccessToken, isFalse);
    });

    test('löst einen vorhandenen Ordner über den blanken Pfad auf', () async {
      final folder = Directory(p.join(tempRoot.path, 'bibliothek'))..createSync();

      expect(await access.resolveRoot(path: folder.path), folder.path);
    });

    test('ignoriert ein Token vollständig – der Pfad allein zählt', () async {
      final folder = Directory(p.join(tempRoot.path, 'bibliothek'))..createSync();

      // Ein (unter Linux/Windows sinnloses) macOS-Bookmark darf das Ergebnis
      // nicht verändern.
      expect(
        await access.resolveRoot(path: folder.path, token: 'Ym9va21hcms='),
        folder.path,
      );
    });

    test('liefert null für einen nicht mehr vorhandenen Ordner', () async {
      // Muster: externe Platte nicht eingebunden, Ordner gelöscht/umbenannt.
      final missing = p.join(tempRoot.path, 'gibt_es_nicht');

      expect(await access.resolveRoot(path: missing), isNull);
    });

    test('liefert null für fehlenden oder leeren Pfad', () async {
      expect(await access.resolveRoot(path: null), isNull);
      expect(await access.resolveRoot(path: ''), isNull);
      expect(await access.resolveRoot(path: null, token: 'irgendwas'), isNull);
    });
  });

  group('Plattformauswahl', () {
    test('wählt die zur laufenden Plattform passende Umsetzung', () {
      final access = FolderAccess.forCurrentPlatform();

      // Nur macOS kennt Security-Scoped Bookmarks; alle anderen
      // Desktop-Plattformen kommen mit dem blanken Pfad aus.
      expect(access.usesAccessToken, Platform.isMacOS);
    });
  });

  group('PickedFolder', () {
    test('hält Pfad und Token unverändert fest', () {
      const picked = PickedFolder('/pfad/zur/bibliothek', 'token123');

      expect(picked.path, '/pfad/zur/bibliothek');
      expect(picked.token, 'token123');
    });
  });
}
