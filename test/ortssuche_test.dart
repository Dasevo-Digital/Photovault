import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/reverse_geocoder.dart';

/// Die Vorwärtssuche: Ortsname zu Koordinate.
///
/// Anlass sind die Lebensereignisse im Stammbaum. Sie führen ihren Ort
/// als **Text** und landen deshalb auf keiner Karte. Der GeoNames-Auszug
/// für die Umkehr-Geokodierung der Fotos liegt bereits im Speicher – die
/// Suche in die andere Richtung läuft auf derselben Liste.
///
/// Geprüft wird gegen einen kleinen, synthetischen Auszug im Format von
/// `cities1000.txt`, wie in reverse_geocoder_test.dart. Die Zeilen sind
/// bewusst so gewählt, dass Mehrdeutigkeit vorkommt: zwei Paris, zwei
/// Springfield.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pv_ortssuche_');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  Future<ReverseGeocoder> lade() async {
    final citiesFile = File(p.join(tempDir.path, 'cities1000.txt'));
    // Spalten: geonameid, name, asciiname, alternatenames, lat, lon,
    // feature class, feature code, country code, cc2, admin1, admin2,
    // admin3, admin4, population, ...
    await citiesFile.writeAsString(
      '2988507\tParis\tParis\t\t48.85661\t2.35222\tP\tPPLC\tFR\t\t11\t75\t\t\t2138551\t\t42\tEurope/Paris\t2023\n'
      '4717560\tParis\tParis\t\t33.66094\t-95.55551\tP\tPPLA2\tUS\t\t TX\t277\t\t\t24782\t\t184\tAmerica/Chicago\t2023\n'
      '4250542\tSpringfield\tSpringfield\t\t39.79172\t-89.64371\tP\tPPLA\tUS\t\tIL\t167\t\t\t114230\t\t180\tAmerica/Chicago\t2023\n'
      '4409896\tSpringfield\tSpringfield\t\t37.21533\t-93.29824\tP\tPPLA2\tUS\t\tMO\t077\t\t\t169176\t\t395\tAmerica/Chicago\t2023\n'
      '2950159\tBerlin\tBerlin\t\t52.52437\t13.41053\tP\tPPLC\tDE\t\t16\t\t\t\t3426354\t\t74\tEurope/Berlin\t2023\n'
      '2867714\tMünchen\tMunchen\t\t48.13743\t11.57549\tP\tPPLA\tDE\t\t02\t091\t\t\t1260391\t\t519\tEurope/Berlin\t2023\n',
    );

    final admin1File = File(p.join(tempDir.path, 'admin1CodesASCII.txt'));
    await admin1File.writeAsString(
      'FR.11\tÎle-de-France\tIle-de-France\t3012874\n'
      'US.IL\tIllinois\tIllinois\t4896861\n'
      'US.MO\tMissouri\tMissouri\t4398678\n'
      'DE.16\tBerlin\tBerlin\t2950157\n'
      'DE.02\tBayern\tBayern\t2951839\n',
    );

    final countryFile = File(p.join(tempDir.path, 'countryInfo.txt'));
    await countryFile.writeAsString(
      '# Kommentar, muss übersprungen werden\n'
      'FR\tFRA\t250\tFR\tFrankreich\tParis\t547030\t67059887\tEU\t.fr\tEUR\tEuro\t33\t\t\tfr-FR\t3017382\t\t\n'
      'US\tUSA\t840\tUS\tVereinigte Staaten\tWashington\t9629091\t327167434\tNA\t.us\tUSD\tDollar\t1\t\t\ten-US\t6252001\t\t\n'
      'DE\tDEU\t276\tDE\tDeutschland\tBerlin\t357021\t82927922\tEU\t.de\tEUR\tEuro\t49\t\t\tde-DE\t2921044\t\t\n',
    );

    return ReverseGeocoder.loadFromFiles(
      citiesFile: citiesFile,
      admin1File: admin1File,
      countryFile: countryFile,
    );
  }

  group('Der einfache Fall', () {
    test('ein eindeutiger Name liefert die Koordinate', () async {
      final geo = await lade();
      final treffer = geo.sucheOrt('Berlin');
      expect(treffer, isNotNull);
      expect(treffer!.breite, closeTo(52.524, 0.001));
      expect(treffer.laenge, closeTo(13.411, 0.001));
      expect(treffer.land, 'Deutschland');
      expect(treffer.mehrdeutig, isFalse);
    });

    test('Gross- und Kleinschreibung sowie Leerzeichen sind egal', () async {
      final geo = await lade();
      expect(geo.sucheOrt('  bErLiN ')?.name, 'Berlin');
    });

    test('ein unbekannter Name liefert null statt eines geratenen Punktes',
        () async {
      // Der wichtigste Rückgabewert der ganzen Datei. Ein Ort, den die
      // Liste nicht kennt, muss ohne Koordinate bleiben – sonst stünde
      // eine Erfindung auf der Karte, und niemand könnte sie von einer
      // Tatsache unterscheiden.
      final geo = await lade();
      expect(geo.sucheOrt('Entenhausen'), isNull);
      expect(geo.sucheOrt(''), isNull);
      expect(geo.sucheOrt('   '), isNull);
    });

    test('der Name ohne diakritische Zeichen findet ebenfalls', () async {
      // GeoNames liefert beide Schreibweisen mit; wer ohne Sonderzeichen
      // tippt, soll nicht ins Leere laufen.
      final geo = await lade();
      expect(geo.sucheOrt('Munchen')?.name, 'München');
      expect(geo.sucheOrt('München')?.name, 'München');
    });
  });

  group('Mehrdeutigkeit', () {
    test('ohne Anhaltspunkt gewinnt der groessere Ort', () async {
      final geo = await lade();
      final treffer = geo.sucheOrt('Paris');
      expect(treffer!.land, 'Frankreich',
          reason: 'Paris/Texas hat 24.782 Einwohner, Paris/Frankreich 2,1 Mio');
      expect(treffer.mehrdeutig, isTrue);
      expect(treffer.weitere, 1);
    });

    test('ein Bezugspunkt schlaegt die Einwohnerzahl', () async {
      // Genau der Fall, für den der Bezugspunkt da ist: Wer seine Fotos
      // fast alle in Texas aufgenommen hat, meint mit „Paris" eher das
      // kleine – auch wenn das andere zehnmal so gross ist.
      final geo = await lade();
      final treffer = geo.sucheOrt('Paris', naheBreite: 32.8, naheLaenge: -96.8);
      expect(treffer!.land, 'Vereinigte Staaten');
      expect(treffer.mehrdeutig, isTrue);
    });

    test('ein Zusatz hinter dem Komma engt ein', () async {
      final geo = await lade();
      expect(geo.sucheOrt('Paris, Frankreich')?.land, 'Frankreich');
      expect(geo.sucheOrt('Paris, Vereinigte Staaten')?.land,
          'Vereinigte Staaten');
      // Auch der Länderkürzel-Weg, wie er in alten Aufzeichnungen steht.
      expect(geo.sucheOrt('Paris, US')?.land, 'Vereinigte Staaten');
    });

    test('der Zusatz darf auch eine Region sein', () async {
      final geo = await lade();
      expect(geo.sucheOrt('Springfield, Illinois')!.breite,
          closeTo(39.79, 0.01));
      expect(geo.sucheOrt('Springfield, Missouri')!.breite,
          closeTo(37.22, 0.01));
    });

    test('ein eindeutiger Zusatz macht den Treffer eindeutig', () async {
      final geo = await lade();
      final treffer = geo.sucheOrt('Paris, Frankreich');
      expect(treffer!.mehrdeutig, isFalse,
          reason: 'nach dem Einengen bleibt genau einer uebrig');
    });

    test('ein unbrauchbarer Zusatz schliesst NICHT aus', () async {
      // Der Fall, der am leichtesten falsch herauskommt: „Berlin, Heimat"
      // darf nicht zu „nicht gefunden" führen. Ein Zusatz, auf den nichts
      // passt, ist keine Angabe – und keine Angabe ist kein Ausschluss.
      final geo = await lade();
      expect(geo.sucheOrt('Berlin, Heimat')?.name, 'Berlin');
      expect(geo.sucheOrt('Paris, Sommerurlaub 1974'), isNotNull);
    });
  });

  test('die Suche sagt, dass sie sich entschieden hat', () async {
    // `weitere` ist der Grund für die eigene Ergebnisklasse. Eine
    // Koordinate ohne diesen Hinweis sähe aus wie eine Tatsache, obwohl
    // sie eine Vermutung ist.
    final geo = await lade();
    expect(geo.sucheOrt('Springfield')!.weitere, 1);
    expect(geo.sucheOrt('Berlin')!.weitere, 0);
  });
}
