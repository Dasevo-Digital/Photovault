import 'dart:convert';
import 'dart:io';

import 'package:kern/db/database.dart';
import 'package:kern/services/reverse_geocoder.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// „Ort setzen“ in Browser und Handy: Dort gibt es kein Ortsverzeichnis, also
/// fragen beide den Server. Die Namen gehen mit dem Befehl mit, denn am
/// Server füllt sie sonst niemand nach.
void main() {
  late Directory ordner;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late Konto erika;

  Future<ReverseGeocoder> verzeichnis() async {
    final staedte = File('${ordner.path}/cities1000.txt')
      ..writeAsStringSync(
        '2910831\tHannover\tHannover\t\t52.37052\t9.73322\tP\tPPLA\tDE\t\t06\t\t\t\t515140\t\t55\tEurope/Berlin\t2024-01-01\n'
        '2918632\tGoslar\tGoslar\t\t51.90425\t10.42766\tP\tPPLA3\tDE\t\t06\t\t\t\t50782\t\t255\tEurope/Berlin\t2024-01-01\n',
      );
    final regionen = File('${ordner.path}/admin1CodesASCII.txt')
      ..writeAsStringSync('DE.06\tLower Saxony\tLower Saxony\t2862926\n');
    final laender = File('${ordner.path}/countryInfo.txt')
      ..writeAsStringSync(
        '# Kopf\n'
        'DE\tDEU\t276\tDE\tGermany\tBerlin\t357021\t82927922\tEU\t.de\tEUR\tEuro\t49\t\t\tde-DE\t2921044\tCH,DK\t\n',
      );
    return ReverseGeocoder.loadFromFiles(
      citiesFile: staedte,
      admin1File: regionen,
      countryFile: laender,
    );
  }

  Bibliotheken neueBibliotheken(ReverseGeocoder? geo) => Bibliotheken(
    wurzel: Directory('${ordner.path}/bibliotheken'),
    eingang: Directory('${ordner.path}/eingang'),
    ruhe: const Duration(hours: 1),
    ortsverzeichnis: geo,
  );

  Future<Map<String, Object?>> suche(
    String text, {
    bool angemeldet = true,
  }) async {
    final api = baueApi(konten: konten, bibliotheken: bibliotheken);
    final r = await api(
      Request(
        'GET',
        Uri.parse(
          'http://server/api/v1/orte/suche?text=${Uri.encodeQueryComponent(text)}',
        ),
        headers: {
          if (angemeldet)
            'authorization':
                'Bearer ${konten.meldeAn(erika.id, 'Rechner', 'x').token}',
        },
      ),
    );
    if (r.statusCode != 200) return {'status': r.statusCode};
    return (jsonDecode(await r.readAsString()) as Map).cast<String, Object?>();
  }

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_orte_');
    sdb = Serverdatenbank.imSpeicher();
    konten = Kontodienst(
      sdb,
      Tresorschluessel(List.filled(32, 9)),
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: false,
    );
    erika = await konten.legeAn('erika', 'ein langes passwort');
  });

  tearDown(() async {
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  test('nur angemeldet', () async {
    bibliotheken = neueBibliotheken(await verzeichnis());
    expect((await suche('Goslar', angemeldet: false))['status'], 401);
  });

  test('ein Treffer bringt Koordinaten und die Namen mit', () async {
    bibliotheken = neueBibliotheken(await verzeichnis());
    final d = await suche('Goslar');
    expect(d['verzeichnis'], isTrue);
    final t = (d['treffer']! as List).single as Map;
    expect(t['name'], 'Goslar');
    expect(t['stadt'], 'Goslar');
    expect(t['region'], 'Lower Saxony');
    expect(t['land'], 'Germany');
    expect(t['breite'], closeTo(51.9, 0.01));
  });

  test('wer den Anfang tippt, bekommt den Namen vorgeschlagen', () async {
    bibliotheken = neueBibliotheken(await verzeichnis());
    final d = await suche('Gos');
    expect(((d['treffer']! as List).single as Map)['name'], 'Goslar');
  });

  test('zu kurz oder unbekannt: leer, ohne Fehler', () async {
    bibliotheken = neueBibliotheken(await verzeichnis());
    expect((await suche('G'))['treffer'], isEmpty);
    expect((await suche('Nirgendwostadt'))['treffer'], isEmpty);
  });

  test('ohne Verzeichnis sagt der Server das', () async {
    bibliotheken = neueBibliotheken(null);
    final d = await suche('Goslar');
    expect(d['verzeichnis'], isFalse);
    expect(d['treffer'], isEmpty);
  });

  test('der Befehl setzt Koordinate und Namen, auch für mehrere', () async {
    bibliotheken = neueBibliotheken(await verzeichnis());
    final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
    for (final id in ['a', 'b']) {
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.jpg',
              relativePath: 'originals/$id.jpg',
              checksum: 'p-$id',
              type: 'IMAGE',
              fileCreatedAt: DateTime(2026),
              importedAt: DateTime(2026),
            ),
          );
    }
    final o = Befehl.ausJson(
      const OrtSetzen(
        ['a', 'b'],
        51.9,
        10.4,
        land: 'Germany',
        region: 'Lower Saxony',
        stadt: 'Goslar',
      ).alsJson(),
    );
    await db.fuehreAus(o);
    final a = (await db.assetById('b'))!;
    expect(a.latitude, 51.9);
    expect(a.locationCity, 'Goslar');
    expect(a.locationCountry, 'Germany');
    expect(a.ortGeerbt, isFalse);

    // Ohne Namen, wie von einer älteren Fassung: Die alten bleiben nicht.
    await db.fuehreAus(const OrtSetzen(['b'], 48.0, 7.8));
    expect((await db.assetById('b'))!.locationCity, isNull);
    await db.fuehreAus(const OrtSetzen(['b'], null, null));
    expect((await db.assetById('b'))!.latitude, isNull);
  });
}
