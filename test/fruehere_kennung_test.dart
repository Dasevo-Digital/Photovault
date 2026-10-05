// Der Umzug von der früheren Kennung (com.example.…) auf
// de.dasevo.photovault.
//
// An der Kennung hängt auf allen drei Plattformen der Datenordner. Ohne
// diesen Umzug stünde jeder bisherige Nutzer nach dem Update vor einer
// leeren App, während seine Bibliothek unauffindbar daneben liegt.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/library_location.dart';

void main() {
  group('Ableitung des früheren Ordners', () {
    String? frueher(String pfad, String plattform) =>
        LibraryLocation.fruehererSupportordner(pfad, plattform: plattform);

    test('macOS: Container und Ordner darin', () {
      expect(
        frueher(
          '/Users/x/Library/Containers/de.dasevo.photovault/Data/Library/'
              'Application Support/de.dasevo.photovault',
          'macos',
        ),
        '/Users/x/Library/Containers/com.example.photoVault/Data/Library/'
        'Application Support/com.example.photoVault',
      );
    });

    test('macOS: die Testvariante zieht aus der alten Testvariante um', () {
      expect(
        frueher(
          '/Users/x/Library/Containers/de.dasevo.photovault.test/Data/'
              'Library/Application Support/de.dasevo.photovault.test',
          'macos',
        ),
        '/Users/x/Library/Containers/com.example.photoVault.test/Data/'
        'Library/Application Support/com.example.photoVault.test',
      );
    });

    test('Windows: CompanyName und ProductName', () {
      expect(
        frueher(r'C:\Users\x\AppData\Roaming\de.dasevo\photovault', 'windows'),
        r'C:\Users\x\AppData\Roaming\com.example\photo_vault',
      );
    });

    test('Windows: auch im Paketbehälter, und ohne Rücksicht auf Gross- '
        'und Kleinschreibung', () {
      expect(
        frueher(
          r'C:\Users\x\AppData\Local\Packages\PV_abc\LocalCache\Roaming'
              r'\De.Dasevo\PhotoVault',
          'windows',
        ),
        r'C:\Users\x\AppData\Local\Packages\PV_abc\LocalCache\Roaming'
        r'\com.example\photo_vault',
      );
    });

    test('Linux: ausgepackt', () {
      expect(
        frueher('/home/x/.local/share/de.dasevo.photovault', 'linux'),
        '/home/x/.local/share/com.example.photo_vault',
      );
    });

    test('Linux: im Flatpak hiessen Behälter und Programm verschieden', () {
      expect(
        frueher(
          '/home/x/.var/app/de.dasevo.photovault/data/'
              'de.dasevo.photovault',
          'linux',
        ),
        '/home/x/.var/app/com.example.PhotoVault/data/com.example.photo_vault',
      );
    });

    test('ein fremder Pfad ergibt null', () {
      expect(frueher('/home/x/.local/share/irgendwas', 'linux'), isNull);
      expect(
        frueher(r'C:\Users\x\AppData\Roaming\de.dasevo\famio', 'windows'),
        isNull,
      );
      expect(
        frueher(
          '/Users/x/Library/Application Support/de.dasevo.famio',
          'macos',
        ),
        isNull,
      );
    });
  });

  group('Übernahme', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('pv_kennung'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Directory ordner(String name) => Directory(p.join(tmp.path, name));
    Directory mitDaten(String name) {
      final d = ordner(name)..createSync(recursive: true);
      File(p.join(d.path, 'library.sqlite')).writeAsStringSync('db');
      Directory(
        p.join(d.path, 'library', 'originals'),
      ).createSync(recursive: true);
      File(
        p.join(d.path, 'library', 'originals', 'a.jpg'),
      ).writeAsStringSync('bild');
      return d;
    }

    test('die Daten werden umbenannt, nicht kopiert', () async {
      final alt = mitDaten('alt/PhotoVault');
      final neu = ordner('neu/PhotoVault');

      final gewaehlt = await LibraryLocation.uebernimmFruehereKennung(neu, [
        alt,
      ]);

      expect(gewaehlt.path, neu.path);
      expect(
        File(
          p.join(neu.path, 'library', 'originals', 'a.jpg'),
        ).readAsStringSync(),
        'bild',
      );
      expect(
        alt.existsSync(),
        isFalse,
        reason: 'umbenannt, also keine zweite Kopie',
      );
    });

    test('ein leerer neuer Ordner steht dem Umzug nicht im Weg', () async {
      final alt = mitDaten('alt/PhotoVault');
      final neu = ordner('neu/PhotoVault')..createSync(recursive: true);

      final gewaehlt = await LibraryLocation.uebernimmFruehereKennung(neu, [
        alt,
      ]);
      expect(gewaehlt.path, neu.path);
      expect(File(p.join(neu.path, 'library.sqlite')).existsSync(), isTrue);
    });

    test('hat der neue Ort schon Daten, wird nichts angefasst', () async {
      final alt = mitDaten('alt/PhotoVault');
      final neu = mitDaten('neu/PhotoVault');

      final gewaehlt = await LibraryLocation.uebernimmFruehereKennung(neu, [
        alt,
      ]);
      expect(gewaehlt.path, neu.path);
      expect(alt.existsSync(), isTrue);
    });

    test('ohne Umbenennen arbeitet die App am alten Ort weiter', () async {
      final alt = mitDaten('alt/PhotoVault');
      final neu = ordner('neu/PhotoVault');

      final gewaehlt = await LibraryLocation.uebernimmFruehereKennung(neu, [
        alt,
      ], umbenennen: false);
      expect(gewaehlt.path, alt.path);
      expect(neu.existsSync(), isFalse);
    });

    test(
      'steht im neuen Ordner etwas anderes, bleibt es beim alten Ort',
      () async {
        // Etwa ein angefangener Geodaten-Download: kein Datenbestand, aber
        // auch nichts, was man wegwerfen dürfte.
        final alt = mitDaten('alt/PhotoVault');
        final neu = ordner('neu/PhotoVault');
        Directory(p.join(neu.path, 'geodata')).createSync(recursive: true);

        final gewaehlt = await LibraryLocation.uebernimmFruehereKennung(neu, [
          alt,
        ]);
        expect(gewaehlt.path, alt.path);
        expect(Directory(p.join(neu.path, 'geodata')).existsSync(), isTrue);
        expect(File(p.join(alt.path, 'library.sqlite')).existsSync(), isTrue);
      },
    );

    test('ohne frühere Daten bleibt es beim neuen Ort', () async {
      final neu = ordner('neu/PhotoVault');
      final gewaehlt = await LibraryLocation.uebernimmFruehereKennung(neu, [
        ordner('gibtsnicht'),
      ]);
      expect(gewaehlt.path, neu.path);
    });
  });

  group('Die Tabelle passt zu den Plattformdateien', () {
    // Ändert jemand eine Kennung, ohne die Tabelle nachzuziehen, fände
    // der erste Start die alten Daten nicht. Diese Prüfungen lesen die
    // Kennung dort, wo sie wirklich gesetzt wird.
    test('macOS: beide Bundle-Kennungen haben eine Herkunft, und die '
        'Entitlements erlauben genau deren Container', () {
      final xcconfig = File(
        'macos/Runner/Configs/AppInfo.xcconfig',
      ).readAsStringSync();
      final kennungen = RegExp(
        r'^PRODUCT_BUNDLE_IDENTIFIER(?:\[[^\]]*\])? = (\S+)',
        multiLine: true,
      ).allMatches(xcconfig).map((m) => m.group(1)!).toSet();
      expect(kennungen, {'de.dasevo.photovault', 'de.dasevo.photovault.test'});
      final freigaben = {
        'de.dasevo.photovault': 'macos/Runner/Release.entitlements',
        'de.dasevo.photovault.test': 'macos/Runner/DebugProfile.entitlements',
      };
      for (final k in kennungen) {
        final frueher = LibraryLocation.fruehererSupportordner(
          '/Users/x/Library/Containers/$k/Data/Library/Application Support/$k',
          plattform: 'macos',
        );
        expect(frueher, isNotNull, reason: k);
        final alt = RegExp(
          r'Containers/([^/]+)/',
        ).firstMatch(frueher!)!.group(1);
        expect(
          File(freigaben[k]!).readAsStringSync(),
          contains('<string>/Library/Containers/$alt/</string>'),
          reason:
              'ohne die Ausnahme darf die Sandbox den alten Container '
              'nicht lesen',
        );
      }
    });

    test('Linux: GTK- und Flatpak-Kennung', () {
      final cmake = File('linux/CMakeLists.txt').readAsStringSync();
      final gtk = RegExp(
        r'set\(APPLICATION_ID "([^"]+)"\)',
      ).firstMatch(cmake)!.group(1)!;
      final plan = File('packaging/flatpak/$gtk.yml').readAsStringSync();
      final flatpak = RegExp(
        r'^app-id: (\S+)',
        multiLine: true,
      ).firstMatch(plan)!.group(1)!;
      final frueher = LibraryLocation.fruehererSupportordner(
        '/home/x/.var/app/$flatpak/data/$gtk',
        plattform: 'linux',
      )!;
      final alterBehaelter = RegExp(
        r'\.var/app/([^/]+)/',
      ).firstMatch(frueher)!.group(1);
      expect(
        plan,
        contains('--filesystem=~/.var/app/$alterBehaelter\n'),
        reason:
            'ohne die Freigabe ist der alte Behälter im Sandkasten '
            'nicht vorhanden',
      );
    });

    test('Windows: CompanyName und ProductName', () {
      final rc = File('windows/runner/Runner.rc').readAsStringSync();
      String wert(String name) =>
          RegExp('VALUE "$name", "([^"]+)"').firstMatch(rc)!.group(1)!;
      expect(
        LibraryLocation.fruehererSupportordner(
          'C:\\Users\\x\\AppData\\Roaming\\${wert('CompanyName')}'
          '\\${wert('ProductName')}',
          plattform: 'windows',
        ),
        isNotNull,
      );
    });
  });
}
