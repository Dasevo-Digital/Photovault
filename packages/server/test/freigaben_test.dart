import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Teilen nach aussen (Issue #106) – vor allem, was ein Besucher NICHT
/// bekommt: keine Metadaten, nichts ausserhalb der Freigabe, nichts ohne
/// Passwort, nichts nach Ablauf oder Widerruf, Originale nur mit Erlaubnis.
void main() {
  late Directory ordner;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late Konto erika;
  late Handler api;
  late String erikaToken;
  late String maxToken;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_freigaben_');
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
    File('${web.path}/teilen.html').writeAsStringSync('<html>Freigabe</html>');
    api = baueApi(konten: konten, bibliotheken: bibliotheken, web: web);
    erika = await konten.legeAn('erika', 'ein langes passwort');
    final max = await konten.legeAn('max', 'noch ein passwort');
    erikaToken = konten.meldeAn(erika.id, 'Rechner', 'x').token;
    maxToken = konten.meldeAn(max.id, 'Rechner', 'x').token;
  });

  tearDown(() async {
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
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

  Future<List<int>> bytesAus(Response r) => r.read().expand((b) => b).toList();

  /// Ein JPEG mit Metadaten, die nicht hinausgehen dürfen.
  Future<String> ladeHoch(String name, int farbe) async {
    final bild = img.Image(width: 64, height: 48);
    img.fill(bild, color: img.ColorRgb8(farbe, 120, 255 - farbe));
    bild.exif.imageIfd.make = 'Kamera-Geheim';
    bild.exif.imageIfd.imageDescription = 'Wohnort-Geheim';
    final bytes = Uint8List.fromList(img.encodeJpg(bild));
    expect(latin1.decode(bytes), contains('Wohnort-Geheim'));
    final tus = {'tus-resumable': '1.0.0'};
    final angelegt = await frag(
      'POST',
      '/api/v1/hochladen',
      token: erikaToken,
      kopf: {
        ...tus,
        'upload-length': '${bytes.length}',
        'upload-metadata': 'filename ${base64.encode(utf8.encode(name))}',
      },
    );
    final fertig = await frag(
      'PATCH',
      angelegt.headers['location']!,
      token: erikaToken,
      kopf: {
        ...tus,
        'content-type': 'application/offset+octet-stream',
        'upload-offset': '0',
      },
      inhalt: bytes,
    );
    expect(fertig.headers['pv-ausgang'], 'imported');
    return fertig.headers['pv-aufnahme']!;
  }

  Future<Map<String, Object?>> teile(Map<String, Object?> werte) async {
    final r = await frag(
      'POST',
      '/api/v1/freigaben',
      token: erikaToken,
      kopf: {'content-type': 'application/json'},
      inhalt: jsonEncode(werte),
    );
    expect(r.statusCode, 201, reason: await r.readAsString());
    return jsonAus(
      await frag('GET', '/api/v1/freigaben', token: erikaToken),
    ).then((d) => (d['freigaben']! as List).cast<Map<String, Object?>>().first);
  }

  String linkAus(Map<String, Object?> f) =>
      Uri.parse(f['link']! as String).pathSegments.last;

  test('Auswahl: nur die gewählten, Bilder ohne Metadaten', () async {
    final a = await ladeHoch('a.jpg', 10);
    final b = await ladeHoch('b.jpg', 90);
    final f = await teile({
      'titel': 'Urlaub',
      'ids': [a],
    });
    expect(f['link'], startsWith('http://fotos.example/teilen/'));
    expect(f['anzahl'], 1);
    final link = linkAus(f);

    // Die Seite – ohne Anmeldung, nicht für Suchmaschinen.
    final seite = await frag('GET', '/teilen/$link');
    expect(seite.statusCode, 200);
    expect(seite.headers['x-robots-tag'], contains('noindex'));
    expect(
      seite.headers['content-security-policy'],
      contains("script-src 'self'"),
    );

    final d = await jsonAus(await frag('GET', '/api/v1/teilen/$link'));
    expect(d['titel'], 'Urlaub');
    final aufnahmen = (d['aufnahmen']! as List).cast<Map>();
    expect(aufnahmen.map((x) => x['id']), [a]);
    // Keine Namen, keine Orte, keine Kamera.
    expect(aufnahmen.single.keys, isNot(contains('name')));
    expect(aufnahmen.single.keys, isNot(contains('ort')));

    for (final art in ['miniatur', 'ansicht']) {
      final r = await frag('GET', '/api/v1/teilen/$link/$a/$art');
      expect(r.statusCode, 200, reason: art);
      final text = latin1.decode(await bytesAus(r));
      expect(text, isNot(contains('Wohnort-Geheim')), reason: art);
      expect(text, isNot(contains('Kamera-Geheim')), reason: art);
      expect(text.codeUnits.take(2), [0xFF, 0xD8], reason: art);
    }
    // Was nicht dazugehört, gibt es nicht.
    expect(
      (await frag('GET', '/api/v1/teilen/$link/$b/ansicht')).statusCode,
      404,
    );
    // Original nur mit Erlaubnis.
    expect(
      (await frag('GET', '/api/v1/teilen/$link/$a/original')).statusCode,
      404,
    );
  });

  test(
    'Album: was beim Aufruf darin liegt, ohne Gesperrtes und Papierkorb',
    () async {
      final a = await ladeHoch('a.jpg', 10);
      final b = await ladeHoch('b.jpg', 90);
      final c = await ladeHoch('c.jpg', 170);
      Future<void> befehl(String art, Map<String, Object?> w) async => expect(
        (await frag(
          'POST',
          '/api/v1/befehle',
          token: erikaToken,
          kopf: {'content-type': 'application/json'},
          inhalt: jsonEncode({'art': art, 'werte': w}),
        )).statusCode,
        200,
      );
      await befehl('albumAnlegen', {
        'albumId': 'feier',
        'name': 'Feier',
        'angelegtAm': '2026-10-18T10:00:00Z',
      });
      await befehl('albumFuellen', {
        'albumId': 'feier',
        'ids': [a, b],
      });
      final f = await teile({
        'titel': 'Feier',
        'album': 'feier',
        'herunterladen': true,
      });
      final link = linkAus(f);
      Future<List<Object?>> ids() async => [
        for (final x
            in ((await jsonAus(
                      await frag('GET', '/api/v1/teilen/$link'),
                    ))['aufnahmen']!
                    as List)
                .cast<Map>())
          x['id'],
      ];
      expect((await ids()).toSet(), {a, b});
      // Später ins Album gelegt: dabei.
      await befehl('albumFuellen', {
        'albumId': 'feier',
        'ids': [c],
      });
      expect((await ids()).toSet(), {a, b, c});
      // Gesperrt oder im Papierkorb: weg, auch als Datei.
      final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
      await (db.update(db.assets)..where((t) => t.id.equals(c))).write(
        const AssetsCompanion(isLocked: Value(true)),
      );
      await befehl('inDenPapierkorb', {
        'ids': [b],
      });
      expect(await ids(), [a]);
      for (final x in [b, c]) {
        expect(
          (await frag('GET', '/api/v1/teilen/$link/$x/miniatur')).statusCode,
          404,
        );
      }
      // Mit Erlaubnis das Original – das trägt seine Metadaten, das weiss
      // der Besitzer beim Anlegen.
      final original = await frag('GET', '/api/v1/teilen/$link/$a/original');
      expect(original.statusCode, 200);
      expect(original.headers['content-disposition'], contains('attachment'));
      expect(
        latin1.decode(await bytesAus(original)),
        contains('Wohnort-Geheim'),
      );
    },
  );

  test('Passwort: ohne nichts, falsch gebremst, richtig mit Cookie', () async {
    final a = await ladeHoch('a.jpg', 10);
    final f = await teile({
      'titel': 'Privat',
      'ids': [a],
      'passwort': 'geheim123',
    });
    expect(f['passwort'], true);
    final link = linkAus(f);
    final ohne = await frag('GET', '/api/v1/teilen/$link');
    expect(ohne.statusCode, 401);
    expect(await jsonAus(ohne), {'passwort': true});
    expect(
      (await frag('GET', '/api/v1/teilen/$link/$a/miniatur')).statusCode,
      401,
    );

    Future<Response> versuch(String pw) => frag(
      'POST',
      '/api/v1/teilen/$link/passwort',
      kopf: {'content-type': 'application/json'},
      inhalt: jsonEncode({'passwort': pw}),
    );
    expect((await versuch('falsch')).statusCode, 401);
    final richtig = await versuch('geheim123');
    expect(richtig.statusCode, 204);
    final cookie = richtig.headers['set-cookie']!;
    expect(cookie, contains('HttpOnly'));
    final wert = cookie.split(';').first;
    final mit = await frag(
      'GET',
      '/api/v1/teilen/$link',
      kopf: {'cookie': wert},
    );
    expect(mit.statusCode, 200);
    expect(
      (await frag(
        'GET',
        '/api/v1/teilen/$link/$a/miniatur',
        kopf: {'cookie': wert},
      )).statusCode,
      200,
    );
    // Ein gefälschtes Cookie hilft nicht.
    final falsch = '${wert.substring(0, wert.length - 3)}abc';
    expect(
      (await frag(
        'GET',
        '/api/v1/teilen/$link',
        kopf: {'cookie': falsch},
      )).statusCode,
      401,
    );
    // Nach zehn Fehlversuchen wartet der Absender.
    for (var i = 0; i < 9; i++) {
      await versuch('falsch$i');
    }
    expect((await versuch('geheim123')).statusCode, 429);
  });

  test('Ablauf, Widerruf, fremde Konten', () async {
    final a = await ladeHoch('a.jpg', 10);
    final f = await teile({
      'titel': 'Kurz',
      'ids': [a],
      'tage': 7,
    });
    final link = linkAus(f);
    expect((await frag('GET', '/api/v1/teilen/$link')).statusCode, 200);
    // Abgelaufen – wie unbekannt.
    sdb.db.execute('UPDATE freigaben SET ablauf = ?', [
      DateTime.now()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch,
    ]);
    expect((await frag('GET', '/api/v1/teilen/$link')).statusCode, 404);
    sdb.db.execute('UPDATE freigaben SET ablauf = NULL');
    expect((await frag('GET', '/api/v1/teilen/$link')).statusCode, 200);

    // Ein anderes Konto sieht sie nicht und löscht sie nicht.
    final fremd = await jsonAus(
      await frag('GET', '/api/v1/freigaben', token: maxToken),
    );
    expect(fremd['freigaben'], isEmpty);
    expect(
      (await frag(
        'DELETE',
        '/api/v1/freigaben/${f['id']}',
        token: maxToken,
      )).statusCode,
      404,
    );
    // Ohne Anmeldung gibt es die Verwaltung nicht.
    expect((await frag('GET', '/api/v1/freigaben')).statusCode, 401);
    // Fremde Aufnahmen lassen sich nicht teilen.
    final r = await frag(
      'POST',
      '/api/v1/freigaben',
      token: maxToken,
      kopf: {'content-type': 'application/json'},
      inhalt: jsonEncode({
        'titel': 'Geklaut',
        'ids': [a],
      }),
    );
    expect(r.statusCode, 400);

    // Widerrufen: weg.
    expect(
      (await frag(
        'DELETE',
        '/api/v1/freigaben/${f['id']}',
        token: erikaToken,
      )).statusCode,
      200,
    );
    expect((await frag('GET', '/api/v1/teilen/$link')).statusCode, 404);
    expect(
      (await frag('GET', '/api/v1/teilen/$link/$a/miniatur')).statusCode,
      404,
    );
    // In der Datenbank steht der Link nicht im Klartext.
    expect(sdb.db.select('SELECT * FROM freigaben'), isEmpty);
  });

  test('Der Link steht nur verschlüsselt in der Datenbank', () async {
    final a = await ladeHoch('a.jpg', 10);
    final f = await teile({
      'titel': 'X',
      'ids': [a],
    });
    final link = linkAus(f);
    final z = sdb.db.select('SELECT * FROM freigaben').single;
    for (final wert in z.values) {
      expect('$wert', isNot(contains(link)));
    }
  });
}
