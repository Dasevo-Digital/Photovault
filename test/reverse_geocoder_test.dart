import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/reverse_geocoder.dart';

/// Prüft die lokale/offline Umkehr-Geokodierung gegen einen kleinen,
/// synthetischen GeoNames-Auszug (statt des echten ~150.000-Zeilen-
/// Datensatzes) – Format identisch zu cities1000.txt/admin1CodesASCII.txt/
/// countryInfo.txt, nur mit zwei Städten.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('photo_vault_geocoder_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Future<ReverseGeocoder> loadSynthetic() async {
    final citiesFile = File(p.join(tempDir.path, 'cities1000.txt'));
    // Spalten: geonameid, name, asciiname, alternatenames, lat, lon,
    // feature class, feature code, country code, cc2, admin1, admin2,
    // admin3, admin4, population, elevation, dem, timezone, mod date.
    await citiesFile.writeAsString(
      '2988507\tParis\tParis\t\t48.85661\t2.35222\tP\tPPLC\tFR\t\t11\t75\t\t\t2138551\t\t42\tEurope/Paris\t2023-05-03\n'
      '2996944\tLyon\tLyon\t\t45.76\t4.84139\tP\tPPLA\tFR\t\t84\t69\t\t\t513275\t\t189\tEurope/Paris\t2023-05-03\n',
    );

    final admin1File = File(p.join(tempDir.path, 'admin1CodesASCII.txt'));
    await admin1File.writeAsString(
      'FR.11\tÎle-de-France\tIle-de-France\t3012874\n'
      'FR.84\tAuvergne-Rhône-Alpes\tAuvergne-Rhone-Alpes\t11071619\n',
    );

    final countryFile = File(p.join(tempDir.path, 'countryInfo.txt'));
    await countryFile.writeAsString(
      '# comment line, muss übersprungen werden\n'
      'FR\tFRA\t250\tFR\tFrance\tParis\t547030\t67059887\tEU\t.fr\tEUR\tEuro\t33\t#####\t^(\\d{5})\$\tfr-FR\t3017382\tAD,BE,DE,IT,LU,MC,ES,CH\t\n',
    );

    return ReverseGeocoder.loadFromFiles(
      citiesFile: citiesFile,
      admin1File: admin1File,
      countryFile: countryFile,
    );
  }

  test('findet die nächstgelegene Stadt samt Bundesland und Land', () async {
    final geocoder = await loadSynthetic();

    final nearParis = geocoder.lookup(48.86, 2.35);
    expect(nearParis?.city, 'Paris');
    expect(nearParis?.state, 'Île-de-France');
    expect(nearParis?.country, 'France');

    final nearLyon = geocoder.lookup(45.75, 4.85);
    expect(nearLyon?.city, 'Lyon');
    expect(nearLyon?.state, 'Auvergne-Rhône-Alpes');
    expect(nearLyon?.country, 'France');
  });

  test('gibt null zurück, wenn keine Stadt im Suchradius bekannt ist', () async {
    final geocoder = await loadSynthetic();

    // Golf von Guinea (0,0) – weit von beiden Testorten in Frankreich entfernt.
    final result = geocoder.lookup(0, 0);
    expect(result, isNull);
  });

  test('gibt bei leerem Datensatz immer null zurück', () async {
    final citiesFile = File(p.join(tempDir.path, 'empty_cities.txt'))..writeAsStringSync('');
    final admin1File = File(p.join(tempDir.path, 'empty_admin1.txt'))..writeAsStringSync('');
    final countryFile = File(p.join(tempDir.path, 'empty_country.txt'))..writeAsStringSync('');

    final geocoder = await ReverseGeocoder.loadFromFiles(
      citiesFile: citiesFile,
      admin1File: admin1File,
      countryFile: countryFile,
    );

    expect(geocoder.lookup(48.86, 2.35), isNull);
  });

  group('Verzeichnisauskunft für die Ortsansicht', () {
    test('nennt alle Regionen eines Landes, nach Namen sortiert', () async {
      final geocoder = await loadSynthetic();
      final regionen = geocoder.regionenVon('FR');
      expect(regionen.map((r) => r.schluessel), ['FR.84', 'FR.11']);
      expect(regionen.first.name, 'Auvergne-Rhône-Alpes');
    });

    test('Kleinschreibung findet dieselben Regionen', () async {
      final geocoder = await loadSynthetic();
      expect(geocoder.regionenVon('fr'), geocoder.regionenVon('FR'));
    });

    test('ein Land ohne verzeichnete Region gibt eine leere Liste', () async {
      // 24 der 252 Länder haben keine. Leer ist die Auskunft, nicht der
      // Fehlschlag – die Ortsansicht muss sie aushalten.
      final geocoder = await loadSynthetic();
      expect(geocoder.regionenVon('DE'), isEmpty);
    });

    test('„FR.1" ist keine Abkürzung für „FR.11"', () async {
      // Der Präfixvergleich muss den Punkt einschliessen, sonst zöge
      // „US.A" auch „US.AK" und „US.AL" an sich.
      final geocoder = await loadSynthetic();
      expect(geocoder.regionenVon('F'), isEmpty);
    });

    test('nennt die Orte einer Region mit dem Schlüssel der Ortsmarken',
        () async {
      final geocoder = await loadSynthetic();
      final orte = geocoder.orteIn('FR.11');
      expect(orte, hasLength(1));
      // „Land|Region|Ort" mit Namen – genau so schreibt die Weltkarte
      // eine Marke.
      expect(orte.single.schluessel, 'France|Île-de-France|Paris');
      expect(orte.single.name, 'Paris');
    });

    test('die grössten Orte zuerst', () async {
      final geocoder = await loadSynthetic();
      // Beide Städte in dieselbe Region legen, damit die Reihenfolge
      // etwas zu entscheiden hat: Paris hat viermal so viele Einwohner.
      final orte = geocoder.orteIn('FR.84');
      expect(orte.single.name, 'Lyon');
    });

    test('die Liste lässt sich deckeln', () async {
      // Für „US.TX" kennt der echte Datensatz über tausend Orte.
      final geocoder = await loadSynthetic();
      expect(geocoder.orteIn('FR.11', hoechstens: 0), isEmpty);
    });

    test('ein unbekannter Regionscode gibt eine leere Liste', () async {
      final geocoder = await loadSynthetic();
      expect(geocoder.orteIn('FR.99'), isEmpty);
      expect(geocoder.orteIn('Unsinn'), isEmpty);
      expect(geocoder.orteIn(''), isEmpty);
    });
  });

  test('das Einlesen laesst den Hauptstrang zwischendurch zu Wort kommen',
      () async {
    // Der Fund der 17. Pruefrunde. `readAsLines()` plus eine Schleife
    // ueber 170.584 Zeilen ist EIN Block Arbeit: gemessen 215 ms, in
    // denen die Oberflaeche steht - und zwar beim Programmstart, wo sie
    // gerade aufgebaut wird. Ueber den Strom sind es 5 ms.
    //
    // Gemessen wird hier nicht die Zeit (die haengt an der Maschine),
    // sondern die Eigenschaft dahinter: dass das Ereignisrad ueberhaupt
    // drankommt. Am Stueck gelesen waere die Antwort null.
    final grossesVerzeichnis = File(p.join(tempDir.path, 'viele.txt'));
    final zeilen = StringBuffer();
    for (var i = 0; i < 60000; i++) {
      zeilen.writeln('$i\tOrt$i\tOrt$i\t\t${48 + i % 5}.0\t${2 + i % 7}.0'
          '\tP\tPPL\tFR\t\t11\t\t\t\t1000');
    }
    await grossesVerzeichnis.writeAsString(zeilen.toString());

    var zugKamDran = 0;
    final takt = Timer.periodic(Duration.zero, (_) => zugKamDran++);
    final geocoder = await ReverseGeocoder.loadFromFiles(
      citiesFile: grossesVerzeichnis,
      admin1File: File(p.join(tempDir.path, 'admin1CodesASCII.txt'))
        ..writeAsStringSync(''),
      countryFile: File(p.join(tempDir.path, 'countryInfo.txt'))
        ..writeAsStringSync(''),
    );
    takt.cancel();

    expect(geocoder.lookup(48.0, 2.0), isNotNull,
        reason: 'sonst pruefte der Test ein leeres Verzeichnis');
    // Der Strom liefert je 64-kB-Stueck ein Ereignis, bei 4 MB also rund
    // 64 Zuege - eine Zahl, die an der Dateigroesse haengt und nicht an
    // der Maschine. Am Stueck gelesen kommen nur die Zuege zusammen, die
    // das asynchrone Lesen selbst uebriglaesst; gemessen 21 bis 31.
    // Fuenfzig trennt beides mit Abstand.
    expect(zugKamDran, greaterThan(50),
        reason: 'am Stueck gelesen stuende die Oberflaeche waehrend der '
            'ganzen Schleife still - gemessen 215 ms bei 170.584 Orten');
  });
}
