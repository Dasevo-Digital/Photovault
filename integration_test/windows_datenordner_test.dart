// ignore_for_file: avoid_print
// **Der Umzug aus dem Roaming-Profil – auf einem echten Windows (#7).**
//
// Die Pfadlogik prüfen die Unittests auf jedem Rechner. Offen bleibt, ob
// `path_provider` die Orte wirklich so meldet und ob das Umbenennen von
// `%APPDATA%` nach `%LOCALAPPDATA%` auf einem echten Profil gelingt. Beides
// hier, mit Probeordnern neben den echten: Die Daten der eingespielten App
// werden nicht angefasst – der echte Umzug gehört dem ersten Start durch
// den Nutzer.
//
//   flutter test integration_test/windows_datenordner_test.dart -d windows
@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_vault/services/library_location.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('path_provider meldet Roaming und lokal wie erwartet', () async {
    final roaming = (await getApplicationSupportDirectory()).path;
    final lokal = (await getApplicationCacheDirectory()).path;
    print('Roaming: $roaming\nLokal:   $lokal');
    print('Vorgänger: ${LibraryLocation.windowsVorgaenger(roaming)}');
    expect(
      roaming.toLowerCase(),
      p
          .join(Platform.environment['APPDATA']!, 'de.dasevo', 'photovault')
          .toLowerCase(),
    );
    expect(
      lokal.toLowerCase(),
      p
          .join(
            Platform.environment['LOCALAPPDATA']!,
            'de.dasevo',
            'photovault',
          )
          .toLowerCase(),
    );
  });

  test('ein Ordner zieht von Roaming nach lokal um, samt Inhalt', () async {
    final probeR = Directory(
      p.join(Platform.environment['APPDATA']!, 'pv_umzug_probe'),
    );
    final probeL = Directory(
      p.join(Platform.environment['LOCALAPPDATA']!, 'pv_umzug_probe'),
    );
    addTearDown(() {
      for (final d in [probeR, probeL]) {
        if (d.existsSync()) d.deleteSync(recursive: true);
      }
    });
    final alt = Directory(p.join(probeR.path, 'PhotoVault'))
      ..createSync(recursive: true);
    File(p.join(alt.path, 'library.sqlite')).writeAsStringSync('db');
    Directory(
      p.join(alt.path, 'library', 'originals'),
    ).createSync(recursive: true);
    File(
      p.join(alt.path, 'library', 'originals', 'foto.jpg'),
    ).writeAsBytesSync(List<int>.filled(1 << 20, 7));
    final neu = Directory(p.join(probeL.path, 'PhotoVault'));

    final uhr = Stopwatch()..start();
    final gewaehlt = await LibraryLocation.uebernimmFruehereKennung(neu, [alt]);
    print('Umzug in ${uhr.elapsedMilliseconds} ms nach ${gewaehlt.path}');

    expect(gewaehlt.path, neu.path);
    expect(alt.existsSync(), isFalse, reason: 'umbenannt, nicht kopiert');
    expect(
      File(p.join(neu.path, 'library', 'originals', 'foto.jpg')).lengthSync(),
      1 << 20,
    );
  });
}
