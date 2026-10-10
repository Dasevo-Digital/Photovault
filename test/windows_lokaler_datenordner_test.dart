// Unter Windows liegen die Daten seit 3.28 lokal, nicht im Roaming-Profil
// (#7). Geprüft wird, woher die ausgepackte Fassung sie holt und wo die
// Paketfassung sie danach findet – reine Pfadarbeit, und der Umzug selbst
// an echten Ordnern.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/library_location.dart';

void main() {
  setUpAll(() => LibraryLocation.pfadPruefungErzwingen = true);
  tearDownAll(() => LibraryLocation.pfadPruefungErzwingen = false);

  test('die Vorgänger im Roaming-Profil: heutige Kennung, dann frühere', () {
    final orte = LibraryLocation.windowsVorgaenger(
      r'C:\Users\X\AppData\Roaming\de.dasevo\photovault',
    );
    expect(
      [for (final o in orte) o.path],
      [
        r'C:\Users\X\AppData\Roaming\de.dasevo\photovault\PhotoVault',
        r'C:\Users\X\AppData\Roaming\com.example\photo_vault\PhotoVault',
      ],
    );
  });

  test('die Paketfassung kennt auch den lokalen Ort der ausgepackten', () {
    const imPaket =
        r'C:\Users\X\AppData\Local\Packages\PV_abc'
        r'\LocalCache\Roaming\de.dasevo\photovault';
    expect(
      LibraryLocation.klassischerLokalerDatenordner(imPaket),
      r'C:\Users\X\AppData\Local\de.dasevo\photovault',
    );
    expect(
      LibraryLocation.klassischerLokalerDatenordner(
        r'C:\Users\X\AppData\Roaming\de.dasevo\photovault',
      ),
      isNull,
      reason: 'ohne Paket gibt es nichts umzuleiten',
    );
  });

  group('der Umzug an echten Ordnern', () {
    late Directory wurzel;
    setUp(() => wurzel = Directory.systemTemp.createTempSync('pv_lokal_'));
    tearDown(() => wurzel.deleteSync(recursive: true));

    Directory ordner(String name) => Directory(p.join(wurzel.path, name));

    test('die Bibliothek wandert samt Inhalt nach lokal', () async {
      final roaming = ordner('Roaming/de.dasevo/photovault/PhotoVault')
        ..createSync(recursive: true);
      File(p.join(roaming.path, 'library.sqlite')).writeAsStringSync('db');
      Directory(p.join(roaming.path, 'models')).createSync();
      final lokal = ordner('Local/de.dasevo/photovault/PhotoVault');
      // Der Kachelspeicher der Karte legt den Elternordner schon vorher an.
      Directory(
        p.join(lokal.parent.path, 'fm_cache'),
      ).createSync(recursive: true);

      final gewaehlt = await LibraryLocation.uebernimmFruehereKennung(lokal, [
        roaming,
        ordner('Roaming/com.example/photo_vault/PhotoVault'),
      ]);

      expect(gewaehlt.path, lokal.path);
      expect(
        File(p.join(lokal.path, 'library.sqlite')).readAsStringSync(),
        'db',
      );
      expect(Directory(p.join(lokal.path, 'models')).existsSync(), isTrue);
      expect(roaming.existsSync(), isFalse);
    });

    test('Daten unter der früheren Kennung kommen ebenfalls mit', () async {
      final alt = ordner('Roaming/com.example/photo_vault/PhotoVault')
        ..createSync(recursive: true);
      File(p.join(alt.path, 'location.json')).writeAsStringSync('{}');
      final lokal = ordner('Local/de.dasevo/photovault/PhotoVault');

      final gewaehlt = await LibraryLocation.uebernimmFruehereKennung(lokal, [
        ordner('Roaming/de.dasevo/photovault/PhotoVault'),
        alt,
      ]);

      expect(gewaehlt.path, lokal.path);
      expect(File(p.join(lokal.path, 'location.json')).existsSync(), isTrue);
    });

    test(
      'liegt lokal schon etwas, bleibt das Roaming-Profil unberührt',
      () async {
        final roaming = ordner('Roaming/de.dasevo/photovault/PhotoVault')
          ..createSync(recursive: true);
        File(p.join(roaming.path, 'library.sqlite')).writeAsStringSync('alt');
        final lokal = ordner('Local/de.dasevo/photovault/PhotoVault')
          ..createSync(recursive: true);
        File(p.join(lokal.path, 'library.sqlite')).writeAsStringSync('neu');

        final gewaehlt = await LibraryLocation.uebernimmFruehereKennung(lokal, [
          roaming,
        ]);

        expect(gewaehlt.path, lokal.path);
        expect(
          File(p.join(roaming.path, 'library.sqlite')).existsSync(),
          isTrue,
        );
      },
    );
  });
}
