import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/reverse_geocoder.dart';

/// **Vorschlagen statt raten.**
///
/// `sucheOrt` entschied sich sofort und sagte erst hinterher, dass die
/// Wahl eine Vermutung war („Ort auf Springfield gesetzt – es gibt 23
/// weitere gleichen Namens"). Die Kandidaten lagen dabei immer schon
/// vor; sie wurden nur weggeworfen.
Future<ReverseGeocoder> _verzeichnis(Directory wurzel) async {
  final staedte = File(p.join(wurzel.path, 'cities1000.txt'));
  await staedte.writeAsString(
    // Zwei Berlin, zwei Springfield – die Fälle, um die es geht.
    '1\tBerlin\tBerlin\t\t52.52437\t13.41053\tP\tPPLC\tDE\t\t16\t\t\t\t3644826\t\t74\tEurope/Berlin\t2023\n'
    '2\tBerlin\tBerlin\t\t44.46853\t-71.18508\tP\tPPL\tUS\t\tNH\t\t\t\t10051\t\t305\tAmerica/New_York\t2023\n'
    '3\tSpringfield\tSpringfield\t\t39.80172\t-89.64371\tP\tPPLA\tUS\t\tIL\t\t\t\t116250\t\t180\tAmerica/Chicago\t2023\n'
    '4\tSpringfield\tSpringfield\t\t37.21533\t-93.29824\tP\tPPLA2\tUS\t\tMO\t\t\t\t169176\t\t396\tAmerica/Chicago\t2023\n'
    '5\tGoslar\tGoslar\t\t51.90425\t10.42766\tP\tPPLA3\tDE\t\t06\t\t\t\t50785\t\t255\tEurope/Berlin\t2023\n',
  );
  final regionen = File(p.join(wurzel.path, 'admin1CodesASCII.txt'));
  await regionen.writeAsString('DE.16\tBerlin\tBerlin\t1\n'
      'DE.06\tNiedersachsen\tNiedersachsen\t5\n'
      'US.NH\tNew Hampshire\tNew Hampshire\t2\n'
      'US.IL\tIllinois\tIllinois\t3\n'
      'US.MO\tMissouri\tMissouri\t4\n');
  final laender = File(p.join(wurzel.path, 'countryInfo.txt'));
  await laender.writeAsString('# Kopf\n'
      'DE\tDEU\t276\tDE\tDeutschland\tBerlin\t357021\t82927922\tEU\t.de\tEUR\tEuro\t49\t\t\tde-DE\t1\t\t\n'
      'US\tUSA\t840\tUS\tVereinigte Staaten\tWashington\t9629091\t327167434\tNA\t.us\tUSD\tDollar\t1\t\t\ten-US\t6252001\t\t\n');
  return ReverseGeocoder.loadFromFiles(
      citiesFile: staedte, admin1File: regionen, countryFile: laender);
}

void main() {
  late Directory wurzel;
  late ReverseGeocoder geo;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_ortsvorschlag_');
    geo = await _verzeichnis(wurzel);
  });

  tearDown(() => wurzel.deleteSync(recursive: true));

  test('nennt beide Berlin, nicht nur eines', () {
    final treffer = geo.sucheOrte('Berlin');
    expect(treffer.length, 2);
    expect(treffer.map((t) => t.land), containsAll(['Deutschland', 'Vereinigte Staaten']));
  });

  test('das grössere steht oben, wenn nichts anderes bekannt ist', () {
    expect(geo.sucheOrte('Berlin').first.land, 'Deutschland');
  });

  test('mit einem bekannten Ort entscheidet die Nähe', () {
    // Ein Foto, das schon in New Hampshire verortet war.
    final treffer =
        geo.sucheOrte('Berlin', naheBreite: 44.0, naheLaenge: -71.0);
    expect(treffer.first.land, 'Vereinigte Staaten');
  });

  test('jeder Vorschlag sagt, wo er liegt', () {
    final springfield = geo.sucheOrte('Springfield');
    expect(springfield.map((t) => t.herkunft),
        containsAll(['Illinois, Vereinigte Staaten', 'Missouri, Vereinigte Staaten']));
    expect(springfield.first.einwohner, greaterThan(0));
  });

  test('das Kürzel hinter dem Komma engt weiter ein', () {
    final treffer = geo.sucheOrte('Springfield, Illinois');
    expect(treffer.length, 1);
    expect(treffer.single.region, 'Illinois');
  });

  test('beim Tippen kommen Namen, nicht Orte', () {
    // „Springfield" steht einmal da, obwohl es den Namen zweimal gibt.
    expect(geo.namensvorschlaege('Spring'), ['Springfield']);
    expect(geo.namensvorschlaege('Gos'), ['Goslar']);
  });

  test('ein Buchstabe ist zu wenig', () {
    expect(geo.namensvorschlaege('B'), isEmpty);
  });

  test('unbekannt bleibt unbekannt – geraten wird nicht', () {
    expect(geo.sucheOrte('Atlantis'), isEmpty);
    expect(geo.namensvorschlaege('Atlant'), isEmpty);
  });

  test('der alte Weg gibt weiterhin den besten Treffer', () {
    // sucheOrt ruft jetzt sucheOrte – das Verhalten muss gleich bleiben,
    // die Ereignisorte hängen daran.
    final einer = geo.sucheOrt('Berlin');
    expect(einer!.name, 'Berlin');
    expect(einer.land, 'Deutschland');
    expect(einer.weitere, 1, reason: 'die Zahl der übrigen bleibt');
  });
}
