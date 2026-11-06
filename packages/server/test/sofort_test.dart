import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:photo_vault_server/src/anfragegrenzen.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// `PUT /api/v1/sofort` (#308): Eine ganze Datei in einer Anfrage, wie iOS
/// sie im Hintergrund schickt, wenn die Handy-App nicht läuft.
void main() {
  late Directory ordner;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late Konto konto;
  late Handler api;
  late String token;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_sofort_');
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
    konto = await konten.legeAn('erika', 'ein langes passwort');
    token = konten.meldeAn(konto.id, 'Telefon', 'x').token;
    api = baueApi(konten: konten, bibliotheken: bibliotheken);
  });

  tearDown(() async {
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  Uint8List jpeg(int farbe) {
    final bild = img.Image(width: 64, height: 48);
    img.fill(bild, color: img.ColorRgb8(farbe, 90, 200 - farbe));
    return Uint8List.fromList(img.encodeJpg(bild));
  }

  Future<Response> schicke(
    Object? inhalt,
    String abfrage, {
    bool anmelden = true,
    Map<String, String> kopf = const {},
  }) async => api(
    Request(
      'PUT',
      Uri.parse('http://server/api/v1/sofort?$abfrage'),
      headers: {
        if (anmelden) 'authorization': 'Bearer $token',
        'content-type': 'application/octet-stream',
        ...kopf,
      },
      body: inhalt,
    ),
  );

  Future<Map<String, Object?>> jsonAus(Response r) async =>
      (jsonDecode(await r.readAsString()) as Map).cast<String, Object?>();

  Future<List<File>> reste() async {
    final eingang = Directory(p.join(ordner.path, 'eingang', konto.id));
    if (!await eingang.exists()) return const [];
    return [
      await for (final e in eingang.list())
        if (e is File) e,
    ];
  }

  test('nimmt das Foto auf und setzt die Aufnahmezeit', () async {
    final zeit = DateTime(2026, 11, 6, 9, 30);
    final r = await schicke(
      jpeg(40),
      'name=IMG_1.jpg&geaendert=${zeit.millisecondsSinceEpoch}',
    );
    expect(r.statusCode, 201);
    final j = await jsonAus(r);
    expect(j['ausgang'], 'imported');
    final id = j['aufnahme']! as String;

    final b = (await bibliotheken.fuer(konto.id)).bibliothek;
    final a = await b.db.assetById(id);
    expect(a!.originalFileName, 'IMG_1.jpg');
    expect(a.fileCreatedAt, zeit);
    expect(await reste(), isEmpty);
  });

  test('dieselbe Datei noch einmal ist ein Erfolg, keine zweite', () async {
    final bytes = jpeg(80);
    final erste = await jsonAus(await schicke(bytes, 'name=a.jpg'));
    final r = await schicke(bytes, 'name=b.jpg');
    expect(r.statusCode, 201);
    final zweite = await jsonAus(r);
    expect(zweite['ausgang'], 'duplicateSkipped');
    expect(zweite['aufnahme'], erste['aufnahme']);
  });

  test('dieselbe Datei zweimal gleichzeitig ist kein Fehler', () async {
    // App und Erweiterung schicken dasselbe Foto. Beide fragen die Datenbank,
    // bevor eine von ihnen dort angekommen ist.
    final bytes = jpeg(85);
    final antworten = await Future.wait([
      for (final name in ['x.jpg', 'y.jpg', 'z.jpg'])
        schicke(bytes, 'name=$name'),
    ]);
    expect(antworten.map((r) => r.statusCode), everyElement(201));
    final j = await Future.wait(antworten.map(jsonAus));
    expect(j.where((x) => x['ausgang'] == 'imported'), hasLength(1));
    expect(j.map((x) => x['aufnahme']).toSet(), hasLength(1));
  });

  test('ohne Anmeldung nimmt der Server nichts an', () async {
    final r = await schicke(jpeg(90), 'name=a.jpg', anmelden: false);
    expect(r.statusCode, 401);
    expect(await reste(), isEmpty);
  });

  test('ohne brauchbaren Namen oder mit fremdem Format abgelehnt', () async {
    expect((await schicke(jpeg(100), 'x=1')).statusCode, 400);
    expect((await schicke(jpeg(100), 'name=..')).statusCode, 400);
    expect((await schicke([1, 2, 3], 'name=bild.xyz')).statusCode, 415);
    expect(await reste(), isEmpty);
  });

  test('der Name kann keinen Pfad mitbringen', () async {
    final r = await schicke(
      jpeg(110),
      'name=${Uri.encodeQueryComponent('../../boese.jpg')}',
    );
    expect(r.statusCode, 201);
    final b = (await bibliotheken.fuer(konto.id)).bibliothek;
    final a = await b.db.assetById((await jsonAus(r))['aufnahme']! as String);
    expect(a!.originalFileName, 'boese.jpg');
    expect(File(p.join(ordner.path, 'boese.jpg')).existsSync(), isFalse);
  });

  test('eine unvollständige Datei bleibt nicht liegen', () async {
    final bytes = jpeg(120);
    final r = await schicke(
      Stream.value(bytes),
      'name=halb.jpg',
      kopf: {'content-length': '${bytes.length + 10}'},
    );
    expect(r.statusCode, 400);
    expect(await reste(), isEmpty);
  });

  test('was über der Grenze liegt, bleibt draussen', () async {
    final eingang = Directory(p.join(ordner.path, 'grenze'));
    final h = Hochladen(eingang, null, hoechstens: 10);
    final r = await h.inEinemStueck(
      Request(
        'PUT',
        Uri.parse('http://server/api/v1/sofort?name=gross.jpg'),
        body: Stream.fromIterable([List.filled(8, 1), List.filled(8, 2)]),
      ),
    );
    expect(r.statusCode, 413);
    expect(eingang.listSync(), isEmpty);
  });

  group('ein Upload, dessen Import verloren ging (#311)', () {
    Future<(Hochladen, String)> angekommen() async {
      final eingang = Directory(p.join(ordner.path, 'tus'))..createSync();
      final h = Hochladen(
        eingang,
        null,
        abschluss: (datei, _) async => {'ausgang': 'imported'},
      );
      final r = await h.anlegen(
        Request(
          'POST',
          Uri.parse('http://s/api/v1/hochladen'),
          headers: {
            'tus-resumable': '1.0.0',
            'upload-length': '5',
            'upload-metadata': 'pfad ${base64.encode(utf8.encode('a/b.jpg'))}',
          },
        ),
      );
      final id = p.basename(r.headers['location']!);
      // Wie nach einem Neustart mitten im Import: Die Datei ist fort, ein
      // Ergebnis gibt es nicht.
      File(p.join(eingang.path, '$id.teil')).deleteSync();
      return (h, id);
    }

    test('HEAD sagt 404, damit das Telefon neu beginnt', () async {
      final (h, id) = await angekommen();
      final r = await h.stand(
        Request('HEAD', Uri.parse('http://s/api/v1/hochladen/$id')),
        id,
      );
      expect(r.statusCode, 404);
      final zweite = await h.status(
        Request('GET', Uri.parse('http://s/api/v1/hochladen/$id')),
        id,
      );
      expect(zweite.statusCode, 404);
    });

    test('auch GET sagt es, und der Rest ist fort', () async {
      final (h, id) = await angekommen();
      final r = await h.status(
        Request('GET', Uri.parse('http://s/api/v1/hochladen/$id')),
        id,
      );
      expect(r.statusCode, 404);
      expect(Directory(p.join(ordner.path, 'tus')).listSync(), isEmpty);
    });

    test('raeumeAuf nimmt den Ordner eines abgebrochenen Imports', () async {
      final eingang = Directory(p.join(ordner.path, 'tus2'));
      Directory(
        p.join(eingang.path, '12345678-1234-1234-1234-123456789012'),
      ).createSync(recursive: true);
      expect(await Hochladen(eingang, null).raeumeAuf(), 1);
      expect(eingang.listSync(), isEmpty);
    });
  });

  test('eine leere Anfrage nimmt nichts auf', () async {
    final r = await schicke(const <int>[], 'name=leer.jpg');
    expect(r.statusCode, 400);
    expect(await reste(), isEmpty);
  });

  group('Live Photo', () {
    final zeit = DateTime(2026, 11, 6, 10);
    final ms = zeit.millisecondsSinceEpoch;

    /// Eine Datei, die als Video durchgeht: Geprüft wird hier die Zuordnung.
    List<int> film(int n) => List.generate(4096, (i) => (i * n) % 251);

    Future<Map<String, String?>> paar(String stamm) async {
      final b = (await bibliotheken.fuer(konto.id)).bibliothek;
      return {
        for (final a in await b.db.select(b.db.assets).get())
          if (a.originalFileName.startsWith(stamm))
            a.originalFileName: a.linkedAssetId,
      };
    }

    test('erst das Bild, dann das Video', () async {
      await schicke(jpeg(130), 'name=IMG_2.jpg&geaendert=$ms');
      await schicke(film(3), 'name=IMG_2.mov&geaendert=$ms');
      final p = await paar('IMG_2');
      expect(p.keys, unorderedEquals(['IMG_2.jpg', 'IMG_2.mov']));
      expect(p.values, everyElement(isNotNull));
    });

    test(
      'erst das Video, dann das Bild: Das System kennt keine Folge',
      () async {
        await schicke(film(5), 'name=IMG_3.mov&geaendert=$ms');
        await schicke(jpeg(140), 'name=IMG_3.jpg&geaendert=$ms');
        final p = await paar('IMG_3');
        expect(p.values, everyElement(isNotNull));
      },
    );

    test('beide gleichzeitig', () async {
      await Future.wait([
        schicke(film(7), 'name=IMG_4.mov&geaendert=$ms'),
        schicke(jpeg(150), 'name=IMG_4.jpg&geaendert=$ms'),
      ]);
      final p = await paar('IMG_4');
      expect(p.keys, hasLength(2));
      expect(p.values, everyElement(isNotNull));
    });
  });

  test('eine grosse Datei kommt am Budget für JSON vorbei', () async {
    final bytes = jpeg(160);
    final r = await anfragegrenzen(jsonBytes: 64)(api)(
      Request(
        'PUT',
        Uri.parse('http://server/api/v1/sofort?name=gross.jpg'),
        headers: {
          'authorization': 'Bearer $token',
          'content-length': '${bytes.length}',
        },
        body: bytes,
      ),
    );
    expect(r.statusCode, 201);
  });

  test('ohne Content-Length nimmt er die Datei auch an', () async {
    final r = await schicke(Stream.value(jpeg(170)), 'name=strom.jpg');
    expect(r.statusCode, 201);
    expect((await jsonAus(r))['ausgang'], 'imported');
  });

  test('der Server meldet, dass er es kann', () async {
    final r = await api(
      Request(
        'GET',
        Uri.parse('http://server/api/v1/zustand'),
        headers: {'authorization': 'Bearer $token'},
      ),
    );
    final f = (await jsonAus(r))['funktionen']! as Map;
    expect(f['sofort'], 1);
  });
}
