import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/platform/folder_access.dart';
import 'package:photo_vault/services/platform/folder_access_macos.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const kanal = MethodChannel('photo_vault/library_location');
  late Directory temp;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('pv_unterordner_');
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kanal, null);
    temp.deleteSync(recursive: true);
  });
  test(
    'Unterordnerzugriff bleibt auf den freigegebenen Elternordner beschränkt',
    () async {
      final ziel = Directory(p.join(temp.path, 'sicherung', 'originals'))
        ..createSync(recursive: true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kanal, (call) async {
            expect(call.method, 'resolveBookmark');
            expect((call.arguments as Map)['bookmark'], 'basiszugriff');
            return temp.path;
          });
      final picked = PickedFolder(
        temp.path,
        'basiszugriff',
      ).unterordner('sicherung').unterordner('originals');
      expect(
        await const MacOsFolderAccess().resolveRoot(
          path: picked.path,
          token: picked.token,
        ),
        ziel.resolveSymbolicLinksSync(),
      );
      for (final name in ['../fremd', '/fremd', 'a\u0000b']) {
        expect(
          () => PickedFolder(temp.path, 'basiszugriff').unterordner(name),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'Verknüpfung aus dem freigegebenen Bereich wird nicht verfolgt',
    () async {
      final aussen = Directory.systemTemp.createTempSync('pv_aussen_');
      try {
        Link(p.join(temp.path, 'verweis')).createSync(aussen.path);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(kanal, (_) async => temp.path);
        final picked = PickedFolder(
          temp.path,
          'basiszugriff',
        ).unterordner('verweis');
        expect(
          await const MacOsFolderAccess().resolveRoot(
            path: picked.path,
            token: picked.token,
          ),
          isNull,
        );
      } finally {
        aussen.deleteSync(recursive: true);
      }
    },
    skip: Platform.isWindows ? 'Symlink benötigt eigene Berechtigung' : false,
  );
}
