import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/video_metadaten.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Gäste laden über einen Link hoch (Issue #106): Ihre Dateien laufen in
/// einem eigenen Prozess ohne Netz durch die Decoder, kommen neu
/// geschrieben heraus – nur mit Zeit, Ort und Kamera – und erst das Ja des
/// Besitzers nimmt sie in die Bibliothek.

/// Ein JPEG mit Aufnahmezeit, Ort und Dingen, die nicht mitkommen dürfen.
Uint8List _fotoVomGast() {
  final bild = img.Image(width: 80, height: 60);
  img.fill(bild, color: img.ColorRgb8(200, 80, 40));
  bild.exif.imageIfd['Make'] = 'Gastkamera';
  bild.exif.imageIfd['ImageDescription'] = 'Geheimnis-im-Kommentar';
  bild.exif.exifIfd['DateTimeOriginal'] = '2024:06:01 14:30:00';
  final gps = bild.exif.gpsIfd;
  gps[1] = img.IfdValueAscii('N');
  gps[2] = img.IfdValueRational(52, 1)
    ..value.addAll(img.IfdValueRational(31, 1).value)
    ..value.addAll(img.IfdValueRational(12, 1).value);
  gps[3] = img.IfdValueAscii('E');
  gps[4] = img.IfdValueRational(13, 1)
    ..value.addAll(img.IfdValueRational(24, 1).value)
    ..value.addAll(img.IfdValueRational(0, 1).value);
  return Uint8List.fromList(img.encodeJpg(bild));
}

bool _hatFfmpeg() {
  try {
    return Process.runSync('ffmpeg', ['-version']).exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Der Server als Prüfprozess, wie unter `dart run`.
final _aufruf = [
  Platform.resolvedExecutable,
  File('bin/photo_vault_server.dart').absolute.path,
];

void main() {
  late Directory ordner;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_gast_');
  });

  tearDown(() => ordner.delete(recursive: true));

  group('Prüfprozess', () {
    test('ein Foto: neu geschrieben, nur Zeit, Ort und Kamera', () async {
      final ein = File('${ordner.path}/gast.jpg')
        ..writeAsBytesSync(_fotoVomGast());
      final ziel = Directory('${ordner.path}/aus')..createSync();
      expect(await gastPruefen([ein.path, ziel.path]), 0);
      final befund =
          jsonDecode(File('${ziel.path}/befund.json').readAsStringSync())
              as Map;
      expect(befund['art'], 'bild');
      expect(befund['endung'], '.jpg');
      expect(befund['breite'], 80);
      expect(befund['aufgenommen'], '2024:06:01 14:30:00');
      expect((befund['ort'] as Map)['breite'], closeTo(52.52, 0.001));
      expect(befund['kamera'], 'Gastkamera');
      final sauber = File('${ziel.path}/sauber.jpg').readAsBytesSync();
      expect(latin1.decode(sauber), isNot(contains('Geheimnis-im-Kommentar')));
      final tags = await readExifFromBytes(sauber);
      expect(tags['EXIF DateTimeOriginal']?.printable, '2024:06:01 14:30:00');
      expect(tags['GPS GPSLatitudeRef']?.printable, 'N');
      expect(tags['Image Make']?.printable, 'Gastkamera');
      expect(File('${ziel.path}/vorschau.jpg').existsSync(), isTrue);
    });

    test('keine Bild- und keine Videodatei: abgewiesen', () async {
      final ein = File('${ordner.path}/boese.jpg')
        ..writeAsStringSync('#!/bin/sh\necho hallo\n');
      final ziel = Directory('${ordner.path}/aus')..createSync();
      expect(await gastPruefen([ein.path, ziel.path]), 2);
      final befund =
          jsonDecode(File('${ziel.path}/befund.json').readAsStringSync())
              as Map;
      expect(befund['grund'], isNotEmpty);
      expect(File('${ziel.path}/sauber.jpg').existsSync(), isFalse);
    });

    test('ein kaputtes JPEG: abgewiesen, nicht abgestürzt', () async {
      final heil = _fotoVomGast();
      final ein = File('${ordner.path}/kaputt.jpg')
        ..writeAsBytesSync(heil.sublist(0, heil.length ~/ 3));
      final ziel = Directory('${ordner.path}/aus')..createSync();
      final code = await gastPruefen([ein.path, ziel.path]);
      expect(code, anyOf(0, 2));
    });

    test('ein Video: H.264 mit Zeit und Ort', () async {
      final ein = File('${ordner.path}/gast.mov');
      final r = await Process.run('ffmpeg', [
        '-v', 'error', '-y', //
        '-f', 'lavfi', '-i', 'testsrc=duration=2:size=320x240:rate=25',
        '-c:v', 'libx264',
        '-metadata', 'creation_time=2024-05-01T10:00:00Z',
        '-metadata', 'location=+52.5200+013.4050/',
        '-movflags', 'use_metadata_tags',
        ein.path,
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final ziel = Directory('${ordner.path}/aus')..createSync();
      expect(await gastPruefen([ein.path, ziel.path]), 0);
      final befund =
          jsonDecode(File('${ziel.path}/befund.json').readAsStringSync())
              as Map;
      expect(befund['art'], 'video');
      expect(befund['endung'], '.mp4');
      expect(befund['dauer'] as double, closeTo(2, 0.2));
      final meta = await leseVideoMetadaten(File('${ziel.path}/sauber.mp4'));
      final vorher = await leseVideoMetadaten(ein);
      expect(vorher.zeit, isNotNull);
      expect(meta.zeit?.zeitpunkt, vorher.zeit!.zeitpunkt);
      expect(meta.ort?.breite, closeTo(52.52, 0.001));
      expect(File('${ziel.path}/vorschau.jpg').existsSync(), isTrue);
    }, skip: _hatFfmpeg() ? false : 'ohne ffmpeg');
  });

  test('die Abschottung sperrt das Netz', () async {
    final a = await Abschottung.erkenne();
    if (!a.ohneNetz) {
      markTestSkipped('dieses System erlaubt keine Netzsperre');
      return;
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) => r.response.close());
    try {
      // Draussen erreichbar …
      expect(
        (await Process.run('curl', [
          '-s',
          '-m',
          '3',
          'http://127.0.0.1:${server.port}/',
        ])).exitCode,
        0,
      );
      // … drinnen nicht.
      final drinnen = await Process.run(a.vorsatz.first, [
        ...a.vorsatz.skip(1),
        'curl',
        '-s',
        '-m',
        '3',
        'http://127.0.0.1:${server.port}/',
      ]);
      expect(drinnen.exitCode, isNot(0));
    } finally {
      await server.close(force: true);
    }
  });

  group('über den Link', () {
    late Serverdatenbank sdb;
    late Kontodienst konten;
    late Bibliotheken bibliotheken;
    late Konto erika;
    late Handler api;
    late String erikaToken;

    setUp(() async {
      sdb = Serverdatenbank.imSpeicher();
      konten = Kontodienst(
        sdb,
        Tresorschluessel(List.filled(32, 7)),
        passwort: const Passwort(speicher: 64, durchgaenge: 1),
        totpPflicht: false,
      );
      bibliotheken = Bibliotheken(
        wurzel: Directory('${ordner.path}/bibliotheken'),
        eingang: Directory('${ordner.path}/eingang'),
        ruhe: const Duration(hours: 1),
      );
      final web = Directory('${ordner.path}/web')..createSync();
      File('${web.path}/teilen.html').writeAsStringSync('<html></html>');
      api = baueApi(
        konten: konten,
        bibliotheken: bibliotheken,
        web: web,
        gastpruefung: Gastpruefung(aufruf: _aufruf),
      );
      erika = await konten.legeAn('erika', 'ein langes passwort');
      erikaToken = konten.meldeAn(erika.id, 'Rechner', 'x').token;
    });

    tearDown(() async {
      await bibliotheken.schliesseAlle();
      sdb.schliesse();
    });

    Future<Response> frag(
      String methode,
      String pfad, {
      String? token,
      Map<String, String> kopf = const {},
      Object? inhalt,
    }) async => api(
      Request(
        methode,
        Uri.parse('http://fotos.example$pfad'),
        headers: {if (token != null) 'authorization': 'Bearer $token', ...kopf},
        body: inhalt,
      ),
    );

    Future<Map<String, Object?>> jsonAus(Response r) async =>
        (jsonDecode(await r.readAsString()) as Map).cast<String, Object?>();

    Future<Response> befehl(String art, Map<String, Object?> werte) => frag(
      'POST',
      '/api/v1/befehle',
      token: erikaToken,
      kopf: {'content-type': 'application/json'},
      inhalt: jsonEncode({'art': art, 'werte': werte}),
    );

    Future<String> teile(Map<String, Object?> werte, {int status = 201}) async {
      final r = await frag(
        'POST',
        '/api/v1/freigaben',
        token: erikaToken,
        kopf: {'content-type': 'application/json'},
        inhalt: jsonEncode(werte),
      );
      final text = await r.readAsString();
      expect(r.statusCode, status, reason: text);
      if (status != 201) return '';
      return Uri.parse(
        (jsonDecode(text) as Map)['link'] as String,
      ).pathSegments.last;
    }

    Future<Response> schicke(
      String link,
      List<int> bytes, {
      String name = 'IMG_0001.jpg',
      Map<String, String>? kopf,
    }) => frag(
      'POST',
      '/api/v1/teilen/$link/beitrag?name=${Uri.encodeQueryComponent(name)}'
          '&von=Tante%20Inge',
      kopf:
          kopf ??
          {
            'x-pv-teilen': '1',
            'sec-fetch-site': 'same-origin',
            'content-length': '${bytes.length}',
          },
      inhalt: bytes,
    );

    Future<List<Map<String, Object?>>> warteAufPruefung() async {
      for (var i = 0; i < 300; i++) {
        final d = await jsonAus(
          await frag('GET', '/api/v1/beitraege', token: erikaToken),
        );
        final liste = (d['beitraege']! as List).cast<Map<String, Object?>>();
        if (liste.every((b) => b['zustand'] != 'pruefung')) return liste;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      fail('Prüfung nach 30 s nicht fertig');
    }

    test('Gast lädt hoch, Besitzer nimmt an: Foto im Album', () async {
      expect(
        (await befehl('albumAnlegen', {
          'albumId': 'feier',
          'name': 'Feier',
          'angelegtAm': '2026-10-19T10:00:00Z',
        })).statusCode,
        200,
      );
      // Beiträge gibt es nur zu Alben.
      await teile({
        'titel': 'Auswahl',
        'ids': ['x'],
        'hochladen': true,
      }, status: 400);
      final ohne = await teile({'titel': 'Nur schauen', 'album': 'feier'});
      final link = await teile({
        'titel': 'Feier',
        'album': 'feier',
        'hochladen': true,
      });
      final foto = _fotoVomGast();
      // Ohne Erlaubnis keine Beiträge; ohne Kopf der Seite auch nicht.
      expect((await schicke(ohne, foto)).statusCode, 404);
      expect(
        (await schicke(
          link,
          foto,
          kopf: {'content-length': '${foto.length}'},
        )).statusCode,
        403,
      );
      expect(
        (await schicke(
          link,
          foto,
          kopf: {
            'x-pv-teilen': '1',
            'sec-fetch-site': 'cross-site',
            'content-length': '${foto.length}',
          },
        )).statusCode,
        403,
      );
      final inhalt = await jsonAus(await frag('GET', '/api/v1/teilen/$link'));
      expect(inhalt['hochladen'], isTrue);

      final r = await schicke(link, foto);
      expect(r.statusCode, 202, reason: await r.readAsString());
      final r2 = await schicke(
        link,
        utf8.encode('kein bild'),
        name: 'boese.jpg',
      );
      expect(r2.statusCode, 202);

      final liste = await warteAufPruefung();
      expect(liste, hasLength(2));
      final gut = liste.firstWhere((b) => b['name'] == 'IMG_0001.jpg');
      final schlecht = liste.firstWhere((b) => b['name'] == 'boese.jpg');
      expect(gut['zustand'], 'bereit', reason: '$gut');
      expect(gut['von'], 'Tante Inge');
      expect(gut['art'], 'bild');
      expect((gut['freigabe']! as Map)['titel'], 'Feier');
      expect(schlecht['zustand'], 'abgewiesen');
      expect(schlecht['grund'], isNotEmpty);
      // Die Bytes des Gastes sind schon weg; nur die Prüfung bleibt.
      final b = (await bibliotheken.fuer(erika.id)).bibliothek;
      final gaeste = Directory('${b.ordner.path}/gaeste/${gut['id']}');
      expect(File('${gaeste.path}/eingang').existsSync(), isFalse);

      final vorschau = await frag(
        'GET',
        '/api/v1/beitraege/${gut['id']}/vorschau',
        token: erikaToken,
      );
      expect(vorschau.statusCode, 200);
      expect(vorschau.headers['content-type'], 'image/jpeg');

      // Noch ist nichts in der Bibliothek.
      expect(await b.db.albumAufnahmen('feier'), isEmpty);
      final an = await frag(
        'POST',
        '/api/v1/beitraege/${gut['id']}/annehmen',
        token: erikaToken,
      );
      expect(an.statusCode, 200, reason: await an.readAsString());
      final im = await b.db.albumAufnahmen('feier');
      expect(im, hasLength(1));
      expect(im.single.originalFileName, 'IMG_0001.jpg');
      expect(im.single.fileCreatedAt.year, 2024);
      expect(im.single.latitude, closeTo(52.52, 0.001));
      expect(gaeste.existsSync(), isFalse);

      expect(
        (await frag(
          'DELETE',
          '/api/v1/beitraege/${schlecht['id']}',
          token: erikaToken,
        )).statusCode,
        200,
      );
      expect(await warteAufPruefung(), isEmpty);
    });

    test('Freigabe gelöscht: offene Beiträge gehen mit', () async {
      await befehl('albumAnlegen', {
        'albumId': 'a',
        'name': 'A',
        'angelegtAm': '2026-10-19T10:00:00Z',
      });
      final link = await teile({'titel': 'A', 'album': 'a', 'hochladen': true});
      expect((await schicke(link, _fotoVomGast())).statusCode, 202);
      final liste = await warteAufPruefung();
      final freigabe =
          ((await jsonAus(
                    await frag('GET', '/api/v1/freigaben', token: erikaToken),
                  ))['freigaben']!
                  as List)
              .cast<Map>()
              .single;
      expect(freigabe['beitraege'], 1);
      await frag(
        'DELETE',
        '/api/v1/freigaben/${freigabe['id']}',
        token: erikaToken,
      );
      expect(await warteAufPruefung(), isEmpty);
      final b = (await bibliotheken.fuer(erika.id)).bibliothek;
      expect(
        Directory('${b.ordner.path}/gaeste/${liste.single['id']}').existsSync(),
        isFalse,
      );
      // Und der Link nimmt nichts mehr an.
      expect((await schicke(link, _fotoVomGast())).statusCode, 404);
    });
  });
}
