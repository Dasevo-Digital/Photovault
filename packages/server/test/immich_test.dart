import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:image/image.dart' as img;
import 'package:kern/abgleich/tus.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

/// Die Übernahme aus Immich (#305) gegen einen nachgebauten Immich-Server,
/// dessen Antworten dem Schema von Immich 3.x folgen.
void main() {
  late Directory ordner;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late HttpServer server;
  late HttpServer immich;
  late Serververbindung v;
  late Serververbindung nichtVerwalter;
  late AppDatabase db;
  late _Immich fake;
  late Map<String, String> ids;
  late Map<String, String> sha1s;
  late String erikaId;

  File bild(String name, int rot) {
    final b = img.Image(width: 640, height: 480);
    img.fill(b, color: img.ColorRgb8(rot, 90, 240 - rot));
    return File('${ordner.path}/$name')..writeAsBytesSync(img.encodeJpg(b));
  }

  Future<void> lade(String name, int rot, {DateTime? zeit}) async {
    final datei = bild(name, rot);
    final kopf = await TusHochladen(v).lade(datei, 'api/v1/hochladen', {
      'filename': name,
      if (zeit != null) 'geaendert': '${zeit.millisecondsSinceEpoch}',
    });
    ids[name] = kopf['pv-aufnahme']!;
    sha1s[name] = base64.encode(sha1.convert(datei.readAsBytesSync()).bytes);
  }

  setUp(() async {
    ordner = Directory.systemTemp.createTempSync('pv_immich_test_');
    ids = {};
    sha1s = {};
    sdb = Serverdatenbank.imSpeicher();
    konten = Kontodienst(
      sdb,
      Tresorschluessel(List.filled(32, 9)),
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: false,
    );
    bibliotheken = Bibliotheken(
      wurzel: Directory('${ordner.path}/bibliotheken'),
      eingang: Directory('${ordner.path}/eingang'),
      ruhe: const Duration(hours: 1),
    );
    final api = baueApi(konten: konten, bibliotheken: bibliotheken);
    server = await shelf_io.serve(api, InternetAddress.loopbackIPv4, 0);
    final erika = await konten.legeAn(
      'erika',
      'ein langes passwort',
      verwalter: true,
    );
    erikaId = erika.id;
    v = Serververbindung(
      Uri.parse('http://127.0.0.1:${server.port}/'),
      konten.meldeAn(erika.id, 'Rechner', 'x').token,
    );
    final otto = await konten.legeAn('otto', 'noch ein langes passwort');
    nichtVerwalter = Serververbindung(
      Uri.parse('http://127.0.0.1:${server.port}/'),
      konten.meldeAn(otto.id, 'Rechner', 'x').token,
    );
    db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
    fake = _Immich();
    immich = await shelf_io.serve(
      fake.antworte,
      InternetAddress.loopbackIPv4,
      0,
    );
  });

  tearDown(() async {
    v.schliesse();
    nichtVerwalter.schliesse();
    await server.close(force: true);
    await immich.close(force: true);
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    ordner.deleteSync(recursive: true);
  });

  Future<Map> warte() async {
    for (var i = 0; i < 400; i++) {
      final s = await v.hole('api/v1/immich');
      if (!const {
        'laden',
        'pruefsummen',
        'gesichter',
        'uebernehmen',
      }.contains(s['stufe'])) {
        return s;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail('läuft nicht zu Ende');
  }

  Future<Map> pruefe({String schluessel = _Immich.schluessel}) async {
    await v.schicke('api/v1/immich/pruefen', {
      'adresse': 'http://127.0.0.1:${immich.port}',
      'schluessel': schluessel,
    });
    return warte();
  }

  Future<Map> uebernimm([Map<String, Object?> teile = const {}]) async {
    await v.schicke('api/v1/immich/uebernehmen', teile);
    return warte();
  }

  Future<String> gesicht(
    String aufnahme, {
    required double x,
    double y = 0.1,
    String? person,
  }) async {
    final id = 'gesicht-${x}_$aufnahme';
    await db
        .into(db.faces)
        .insert(
          FacesCompanion.insert(
            id: id,
            assetId: aufnahme,
            personId: Value(person),
            boxX: x,
            boxY: y,
            boxW: 0.2,
            boxH: 0.3,
          ),
        );
    return id;
  }

  Future<AssetData> zeile(String name) async =>
      (await db.assetById(ids[name]!))!;
  Future<FaceData> faceZeile(String id) async =>
      (db.select(db.faces)..where((f) => f.id.equals(id))).getSingle();

  final zeit0 = DateTime.utc(2024, 5, 1, 10);

  group('Bericht und Übernahme', () {
    late String freiesGesicht;

    setUp(() async {
      final zeit = zeit0;
      await lade('a.jpg', 20, zeit: zeit);
      await lade('b.jpg', 90, zeit: zeit.add(const Duration(hours: 1)));
      await lade('c.jpg', 160, zeit: zeit.add(const Duration(hours: 2)));
      // Eine Person, die es schon gibt, und ein freies Gesicht.
      await db.fuehreAus(const PersonAnlegen('p-anna', 'Anna'));
      await gesicht(ids['a.jpg']!, x: 0.1, person: 'p-anna');
      await gesicht(ids['b.jpg']!, x: 0.1, person: 'p-anna');
      freiesGesicht = await gesicht(ids['c.jpg']!, x: 0.1);
      // In Photo Vault steht schon etwas: bleibt.
      await db.fuehreAus(BeschreibungSetzen([ids['b.jpg']!], 'von Hand'));

      const anna = {'id': 'i-anna', 'name': 'Anna', 'isHidden': false};
      const tom = {
        'id': 'i-tom',
        'name': 'Tom',
        'birthDate': '1980-05-02',
        'isHidden': false,
      };
      const heimlich = {'id': 'i-h', 'name': 'Heimlich', 'isHidden': true};
      fake.aufnahmen.addAll([
        _aufnahme(
          'ia',
          sha1s['a.jpg']!,
          'a.jpg',
          zeit,
          favorit: true,
          beschreibung: 'Ein Tag am See',
          leute: [anna],
        ),
        _aufnahme(
          'ib',
          sha1s['b.jpg']!,
          'b.jpg',
          zeit.add(const Duration(hours: 1)),
          beschreibung: 'Anders',
          leute: [anna],
        ),
        // Dieselbe Aufnahme mit anderen Metadaten.
        _aufnahme(
          'ic',
          'YW5kZXJlLXByw7xmc3VtbWU=',
          'C.JPG',
          zeit.add(const Duration(hours: 2, seconds: 1)),
          sichtbarkeit: 'archive',
          leute: [tom],
        ),
        // Liegt nur in Immich.
        _aufnahme('ix', 'ZmVobHQ=', 'weg.jpg', zeit),
        // Wird nicht übernommen.
        _aufnahme('it', 'dHJhc2g=', 'korb.jpg', zeit, papierkorb: true),
        _aufnahme('iv', 'dmlkZW8=', 'a.mov', zeit, sichtbarkeit: 'hidden'),
        _aufnahme('il', 'bG9jaw==', 'l.jpg', zeit, leute: [heimlich]),
      ]);
      fake.alben['al'] = ('Urlaub', ['ia', 'ic', 'ix']);
      fake.alben['al2'] = ('Urlaub', ['ib']);
      fake.gesichter['ia'] = [_rahmen('i-anna', 0.11)];
      fake.gesichter['ib'] = [_rahmen('i-anna', 0.12)];
      fake.gesichter['ic'] = [_rahmen('i-tom', 0.1)];
    });

    test('die Prüfung ändert nichts und nennt, was fehlt', () async {
      final s = await pruefe();
      expect(s['stufe'], 'bereit', reason: '${s['fehler']}');
      final b = s['bericht'] as Map;
      expect(b['fassung'], '3.3.5');
      final z = b['zuordnung'] as Map;
      expect(z['bitgleich'], 2);
      expect(z['aehnlich'], 1);
      expect(z['fehlen'], 2, reason: 'weg.jpg und l.jpg');
      expect(
        (z['beispiele'] as List).map((e) => (e as Map)['name']),
        unorderedEquals(['weg.jpg', 'l.jpg']),
      );
      final p = b['vorhaben'] as Map;
      expect(p['albenNeu'], 2, reason: 'zwei Alben namens Urlaub');
      expect(p['favoriten'], 1);
      expect(p['beschreibungen'], 1);
      expect(p['beschreibungenAbweichend'], 1);
      expect(p['personenNeu'], 1, reason: 'Tom');
      expect(p['gesichter'], 1);
      expect(p['geburtstage'], 1);
      expect(p['archiv'], 1);

      expect(await db.alleAlben(), isEmpty);
      expect((await zeile('a.jpg')).isFavorite, isFalse);
      expect((await faceZeile(freiesGesicht)).personId, isNull);
      expect(fake.schreibend, isEmpty, reason: 'Immich wird nur gelesen');
    });

    test('übernimmt, ohne Vorhandenes anzufassen', () async {
      await pruefe();
      final s = await uebernimm();
      expect(s['stufe'], 'fertig', reason: '${s['fehler']}');
      expect((s['ergebnis'] as Map)['favoriten'], 1);

      final alben = {for (final a in await db.alleAlben()) a.name: a.id};
      expect(alben.keys, unorderedEquals(['Urlaub', 'Urlaub (2)']));
      Future<Set<String>> inhalt(String name) async => {
        for (final a in await db.assetsInAlbumOnce(alben[name]!)) a.id,
      };
      final mitLauter = {await inhalt('Urlaub'), await inhalt('Urlaub (2)')};
      expect(
        mitLauter,
        unorderedEquals([
          {ids['a.jpg'], ids['c.jpg']},
          {ids['b.jpg']},
        ]),
      );
      // Archiviert in Immich: im Archiv der Bibliothek, nicht in einem Album.
      expect((await zeile('c.jpg')).isArchived, isTrue);
      expect((await zeile('a.jpg')).isArchived, isFalse);

      final a = await zeile('a.jpg');
      expect(a.isFavorite, isTrue);
      expect(a.description, 'Ein Tag am See');
      expect((await zeile('b.jpg')).description, 'von Hand');

      final tom = (await db.allePersonen()).singleWhere((p) => p.name == 'Tom');
      expect((await faceZeile(freiesGesicht)).personId, tom.id);
      expect(tom.geburtsdatum?.year, 1980);
      // Wiederholt ändert sich nichts mehr.
      expect(((s['bericht'] as Map)['vorhaben'] as Map)['aenderungen'], 0);
      await pruefe();
      final zweite = await uebernimm();
      expect((zweite['ergebnis'] as Map)['favoriten'], 0);
      expect(await db.alleAlben(), hasLength(2));
      expect(await db.allePersonen(), hasLength(2));
    });

    test('nur die gewählten Teile', () async {
      await pruefe();
      final s = await uebernimm({
        'alben': false,
        'personen': false,
        'archiv': false,
        'beschreibungen': false,
      });
      expect(s['stufe'], 'fertig');
      expect(await db.alleAlben(), isEmpty);
      expect((await zeile('a.jpg')).isFavorite, isTrue);
      expect((await zeile('a.jpg')).description, isNot('Ein Tag am See'));
      expect(await db.allePersonen(), hasLength(1));
    });

    test('ein anderer Name bleibt und steht im Bericht', () async {
      fake.gesichter['ic'] = [_rahmen('i-anna', 0.1)];
      fake.aufnahmen.firstWhere((a) => a['id'] == 'ia')['people'] = [
        {'id': 'i-anna', 'name': 'Anna Muster', 'isHidden': false},
      ];
      fake.aufnahmen.firstWhere((a) => a['id'] == 'ib')['people'] = [
        {'id': 'i-anna', 'name': 'Anna Muster', 'isHidden': false},
      ];
      fake.aufnahmen.firstWhere((a) => a['id'] == 'ic')['people'] = [
        {'id': 'i-anna', 'name': 'Anna Muster', 'isHidden': false},
      ];
      final s = await pruefe();
      final p = (s['bericht'] as Map)['vorhaben'] as Map;
      expect(p['abweichendeNamen'], [
        {'immich': 'Anna Muster', 'bibliothek': 'Anna'},
      ]);
      expect(p['personenNeu'], 0);
      await uebernimm();
      expect((await faceZeile(freiesGesicht)).personId, 'p-anna');
      expect((await db.allePersonen()).single.name, 'Anna');
    });

    test('ein Gesicht ohne Überlappung bleibt frei', () async {
      fake.gesichter['ic'] = [_rahmen('i-tom', 0.7)];
      await pruefe();
      await uebernimm();
      expect((await faceZeile(freiesGesicht)).personId, isNull);
      expect(await db.allePersonen(), hasLength(1), reason: 'kein leerer Tom');
    });

    test('Fotos von Partnern zählen nicht (#362)', () async {
      fake.aufnahmen.add(
        _aufnahme(
          'ip',
          sha1s['c.jpg']!,
          'c.jpg',
          zeit0,
          favorit: true,
          beschreibung: 'vom Partner',
          besitzer: 'partner',
        ),
      );
      fake.aufnahmen.add(
        _aufnahme('iq', 'cGFydG5lcjI=', 'q.jpg', zeit0, besitzer: 'partner'),
      );
      final s = await pruefe();
      final b = s['bericht'] as Map;
      expect((b['immich'] as Map)['partner'], 2);
      expect((b['zuordnung'] as Map)['fehlen'], 2, reason: 'q.jpg zählt nicht');
      expect((b['vorhaben'] as Map)['favoriten'], 1, reason: 'nur a.jpg');
    });

    test('ohne user.read eine klare Meldung', () async {
      fake.ohneNutzerrecht = true;
      final s = await pruefe();
      expect(s['stufe'], 'fehler');
      expect('${s['fehler']}', contains('user.read'));
    });

    test('Kameratexte werden keine Beschreibung (#362)', () async {
      fake.aufnahmen.firstWhere((a) => a['id'] == 'ia')['exifInfo'] = {
        'description': 'OLYMPUS DIGITAL CAMERA',
      };
      final s = await pruefe();
      final p = (s['bericht'] as Map)['vorhaben'] as Map;
      expect(p['beschreibungen'], 0);
      expect(p['kameratexte'], 1);
    });

    test('zwei Immich-Personen gleichen Namens werden eine (#362)', () async {
      await lade('d.jpg', 220, zeit: zeit0.add(const Duration(hours: 3)));
      final zweites = await gesicht(ids['d.jpg']!, x: 0.1);
      const tom2 = {'id': 'i-tom2', 'name': 'Tom', 'isHidden': false};
      fake.aufnahmen.add(
        _aufnahme(
          'id',
          sha1s['d.jpg']!,
          'd.jpg',
          zeit0.add(const Duration(hours: 3)),
          leute: [tom2],
        ),
      );
      fake.gesichter['id'] = [_rahmen('i-tom2', 0.1)];
      final s = await pruefe();
      final p = (s['bericht'] as Map)['vorhaben'] as Map;
      expect(p['personenNeu'], 1);
      expect(p['gesichter'], 2);
      await uebernimm();
      final toms = (await db.allePersonen()).where((p) => p.name == 'Tom');
      expect(toms, hasLength(1));
      expect((await faceZeile(zweites)).personId, toms.single.id);
      expect((await faceZeile(freiesGesicht)).personId, toms.single.id);
    });

    test('verdeckte Stapelmitglieder: Album an die oberste, einmal', () async {
      await db.fuehreAus(
        SerieBilden('s', [ids['a.jpg']!, ids['c.jpg']!], ids['c.jpg']!),
      );
      await pruefe();
      await uebernimm({'personen': false});
      final alben = {for (final a in await db.alleAlben()) a.name: a.id};
      expect(
        await db.imAlbum(alben['Urlaub']!, [ids['a.jpg']!, ids['c.jpg']!]),
        {ids['c.jpg']},
      );
      expect((await zeile('c.jpg')).isFavorite, isTrue, reason: 'von a.jpg');
      final zweite = await pruefe();
      final v = (zweite['bericht'] as Map)['vorhaben'] as Map;
      expect(v['albumAufnahmen'], 0);
      expect(v['favoriten'], 0);
    });

    test('ein kaputter Zwischenspeicher wird neu gerechnet', () async {
      final bibliothek = (await bibliotheken.fuer(erikaId)).bibliothek;
      File(
        '${bibliothek.ordner.path}/immich-sha1.json',
      ).writeAsStringSync('{kaputt');
      final s = await pruefe();
      expect(s['stufe'], 'bereit', reason: '${s['fehler']}');
      expect(((s['bericht'] as Map)['zuordnung'] as Map)['bitgleich'], 2);
    });

    test('ein in Immich gelöschtes Foto bricht die Prüfung nicht ab', () async {
      fake.gesichterWeg.add('ia');
      final s = await pruefe();
      expect(s['stufe'], 'bereit', reason: '${s['fehler']}');
    });

    test(
      'ein neues gleichnamiges Album benennt kein altes um (#362)',
      () async {
        await pruefe();
        await uebernimm();
        final vorher = {for (final a in await db.alleAlben()) a.id: a.name};
        fake.alben['a0'] = ('Urlaub', ['ib']);
        fake.albumAngelegt['a0'] = '2020-01-01T00:00:00.000Z';
        await pruefe();
        await uebernimm();
        final nachher = {for (final a in await db.alleAlben()) a.id: a.name};
        for (final MapEntry(key: id, value: name) in vorher.entries) {
          expect(nachher[id], name);
        }
        expect(nachher.values, contains('Urlaub (3)'));
      },
    );

    test('der Bericht zählt alle nicht Zugeordneten', () async {
      final s = await pruefe();
      final z = (s['bericht'] as Map)['zuordnung'] as Map;
      expect(z['ohneAnzahl'], 2);
      expect(z['mehrdeutig'], 0);
    });

    test('Stimmen ohne klare Mehrheit: unklar, keine Änderung', () async {
      await db.fuehreAus(const PersonAnlegen('p-berta', 'Berta'));
      await gesicht(ids['c.jpg']!, x: 0.6, person: 'p-berta');
      fake.aufnahmen.firstWhere((a) => a['id'] == 'ic')['people'] = [
        {'id': 'i-anna', 'name': 'Anna', 'isHidden': false},
      ];
      fake.gesichter['ic'] = [_rahmen('i-anna', 0.6)];
      fake.gesichter['ib'] = [];
      final s = await pruefe();
      final p = (s['bericht'] as Map)['vorhaben'] as Map;
      expect(p['unklar'], ['Anna']);
    });
  });

  test('Seiten über Nummern und über Zeiger', () async {
    await lade('a.jpg', 20);
    for (final zeiger in [false, true]) {
      fake
        ..aufnahmen.clear()
        ..seitengroesse = 2
        ..mitZeiger = zeiger;
      for (var i = 0; i < 5; i++) {
        fake.aufnahmen.add(
          _aufnahme('i$i', 'c3VtbWU$i', 'x$i.jpg', DateTime.utc(2020)),
        );
      }
      final s = await pruefe();
      expect(
        (s['bericht'] as Map)['immich']['aufnahmen'],
        5,
        reason: '$zeiger',
      );
    }
  });

  test('die Prüfsummen rechnet sie nur einmal', () async {
    await lade('a.jpg', 20);
    await pruefe();
    final bibliothek = (await bibliotheken.fuer(erikaId)).bibliothek;
    final ablage = File('${bibliothek.ordner.path}/immich-sha1.json');
    expect(jsonDecode(ablage.readAsStringSync()), hasLength(1));
  });

  group('Fehler', () {
    test('falscher Schlüssel', () async {
      final s = await pruefe(schluessel: 'falsch');
      expect(s['stufe'], 'fehler');
      expect(s['fehler'], contains('lehnt den API-Schlüssel ab'));
    });

    test('keine Immich-Adresse', () async {
      fake.keinImmich = true;
      final s = await pruefe();
      expect(s['stufe'], 'fehler');
      expect(s['fehler'], contains('kein Immich'));
    });

    test('unverschlüsselt nur im eigenen Netz', () async {
      final a = await v.anfrage(
        'POST',
        'api/v1/immich/pruefen',
        inhalt: utf8.encode(
          jsonEncode({
            'adresse': 'http://immich.example.org',
            'schluessel': 'x',
          }),
        ),
      );
      expect(a.statusCode, 400);
      expect(a.body, contains('https'));
    });

    test('Umleitungen werden nicht verfolgt', () async {
      fake.umleiten = true;
      final s = await pruefe();
      expect(s['stufe'], 'fehler');
      expect(s['fehler'], contains('leitet weiter'));
      expect(fake.umgeleitetGefragt, isFalse);
    });

    test('nur für Verwalter', () async {
      final a = await nichtVerwalter.anfrage('GET', 'api/v1/immich');
      expect(a.statusCode, 403);
    });

    test('der Schlüssel steht nirgends im Stand', () async {
      await lade('a.jpg', 20);
      final s = await pruefe();
      expect(jsonEncode(s), isNot(contains(_Immich.schluessel)));
    });

    test('übernehmen ohne Prüfung', () async {
      final a = await v.anfrage(
        'POST',
        'api/v1/immich/uebernehmen',
        inhalt: utf8.encode('{}'),
      );
      expect(a.statusCode, 409);
    });
  });

  test('Adresse: Schrägstriche und /api', () {
    for (final eingabe in [
      'https://immich.example.org',
      'https://immich.example.org/',
      'https://immich.example.org/api',
      'https://immich.example.org/api/',
    ]) {
      expect(
        '${Immichverbindung.basisAus(eingabe)}',
        'https://immich.example.org/api/',
      );
    }
    expect(
      '${Immichverbindung.basisAus('http://localhost:2283/photos/')}',
      'http://localhost:2283/photos/api/',
    );
  });
}

Map<String, Object?> _aufnahme(
  String id,
  String sha1,
  String name,
  DateTime zeit, {
  bool favorit = false,
  bool papierkorb = false,
  String sichtbarkeit = 'timeline',
  String? beschreibung,
  List<Map<String, Object?>> leute = const [],
  String besitzer = 'ich',
}) => {
  'id': id,
  'checksum': sha1,
  'originalFileName': name,
  'type': 'IMAGE',
  'fileCreatedAt': zeit.toIso8601String(),
  'isFavorite': favorit,
  'isTrashed': papierkorb,
  'isArchived': sichtbarkeit == 'archive',
  'visibility': sichtbarkeit,
  'exifInfo': {'description': beschreibung ?? ''},
  'people': leute,
  'ownerId': besitzer,
};

/// Ein Rahmen an der Stelle [x] auf einem Bild von 1000 mal 800 Punkten; passt
/// zu den Gesichtern der Tests (0,2 breit, 0,3 hoch, oben bei 0,1).
Map<String, Object?> _rahmen(String person, double x) => {
  'id': 'f-$person-$x',
  'imageWidth': 1000,
  'imageHeight': 800,
  'boundingBoxX1': x * 1000,
  'boundingBoxX2': (x + 0.2) * 1000,
  'boundingBoxY1': 80,
  'boundingBoxY2': 320,
  'person': {'id': person, 'name': person, 'isHidden': false},
};

/// Antwortet wie Immich 3.x.
class _Immich {
  static const schluessel = 'der-schluessel';

  final aufnahmen = <Map<String, Object?>>[];
  final alben = <String, (String, List<String>)>{};
  final gesichter = <String, List<Map<String, Object?>>>{};
  final schreibend = <String>[];
  var seitengroesse = 1000;
  var mitZeiger = false;
  var keinImmich = false;
  var umleiten = false;
  var umgeleitetGefragt = false;
  var ohneNutzerrecht = false;
  final gesichterWeg = <String>{};
  final albumAngelegt = <String, String>{};

  Response _json(Object? j, {int status = 200}) => Response(
    status,
    body: jsonEncode(j),
    headers: {'content-type': 'application/json'},
  );

  Future<Response> antworte(Request r) async {
    final pfad = r.url.path;
    if (pfad == 'woanders') {
      umgeleitetGefragt = true;
      return _json({});
    }
    if (umleiten) {
      return Response.found('/woanders');
    }
    if (keinImmich) return Response.ok('<html>Hallo</html>');
    if (pfad == 'api/server/version') {
      return _json({'major': 3, 'minor': 3, 'patch': 5});
    }
    if (r.headers['x-api-key'] != schluessel) {
      return _json({'message': 'Invalid API key'}, status: 401);
    }
    if (r.method == 'GET' && pfad == 'api/albums') {
      final nurGeteilt = r.url.queryParameters['isShared'] == 'true';
      return _json([
        for (final MapEntry(key: id, value: (name, _)) in alben.entries)
          if (!nurGeteilt)
            {
              'id': id,
              'albumName': name,
              'createdAt': albumAngelegt[id] ?? '2024-01-01T00:00:00.000Z',
              'assetCount': 1,
            },
      ]);
    }
    if (r.method == 'GET' && pfad == 'api/users/me') {
      return ohneNutzerrecht
          ? _json({'message': 'Missing permission'}, status: 403)
          : _json({'id': 'ich', 'name': 'Erika'});
    }
    if (r.method == 'GET' && pfad == 'api/faces') {
      final id = r.url.queryParameters['id'];
      if (gesichterWeg.contains(id)) {
        return _json({
          'message': 'Not found or no face.read access',
        }, status: 400);
      }
      return _json(gesichter[id] ?? const []);
    }
    if (r.method == 'POST' && pfad == 'api/search/metadata') {
      final k = jsonDecode(await r.readAsString()) as Map;
      var liste = aufnahmen;
      if (k['albumIds'] != null) {
        final inhalt = alben[(k['albumIds'] as List).single]!.$2;
        liste = [
          for (final a in aufnahmen)
            if (inhalt.contains(a['id'])) a,
        ];
      }
      if (k['visibility'] != null) {
        liste = [
          for (final a in liste)
            if (a['visibility'] == k['visibility']) a,
        ];
      }
      final beginn = k['cursor'] != null
          ? int.parse('${k['cursor']}')
          : ((k['page'] as int?) ?? 1) * seitengroesse - seitengroesse;
      final ende = beginn + seitengroesse < liste.length
          ? beginn + seitengroesse
          : liste.length;
      final weiter = ende < liste.length;
      return _json({
        'albums': {'items': []},
        'assets': {
          'items': liste.sublist(beginn, ende),
          'nextPage': !mitZeiger && weiter
              ? '${(beginn ~/ seitengroesse) + 2}'
              : null,
          'nextCursor': mitZeiger && weiter ? '$ende' : null,
        },
      });
    }
    schreibend.add('${r.method} $pfad');
    return _json({'message': 'nicht gefunden'}, status: 404);
  }
}
