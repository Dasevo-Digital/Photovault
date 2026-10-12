import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late Directory ordner;
  late Bibliothek bibliothek;
  late Handler api;
  final schluessel = 'k' * 43;
  final mitSchluessel = {'authorization': 'Bearer $schluessel'};
  const tus = {'tus-resumable': '1.0.0'};

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_server_');
    bibliothek = await Bibliothek.oeffne(Directory('${ordner.path}/bib'));
    api = baueApi(
      bibliothek: bibliothek,
      hochladen: Hochladen(Directory('${ordner.path}/eingang'), bibliothek),
      zugang: Zugang(schluessel),
    );
  });
  tearDown(() async {
    await bibliothek.schliesse();
    await ordner.delete(recursive: true);
  });

  Future<Response> frag(
    String methode,
    String pfad, {
    Map<String, String> kopf = const {},
    Object? inhalt,
    bool schluessel = true,
  }) async => api(
    Request(
      methode,
      Uri.parse('http://server$pfad'),
      headers: {if (schluessel) ...mitSchluessel, ...kopf},
      body: inhalt,
    ),
  );

  Future<Map<String, Object?>> jsonAus(Response r) async =>
      (jsonDecode(await r.readAsString()) as Map).cast<String, Object?>();

  Uint8List jpeg(int farbe) {
    final bild = img.Image(width: 64, height: 48);
    img.fill(bild, color: img.ColorRgb8(farbe, 90, 200 - farbe));
    return Uint8List.fromList(img.encodeJpg(bild));
  }

  String meta(Map<String, String> werte) => [
    for (final e in werte.entries)
      '${e.key} ${base64.encode(utf8.encode(e.value))}',
  ].join(',');

  /// Lädt [bytes] in zwei Stücken hoch und gibt die Antwort aufs letzte.
  Future<Response> hochladen(
    Uint8List bytes,
    String name, {
    DateTime? geaendert,
  }) async {
    final angelegt = await frag(
      'POST',
      '/api/v1/hochladen',
      kopf: {
        ...tus,
        'upload-length': '${bytes.length}',
        'upload-metadata': meta({
          'filename': name,
          if (geaendert != null)
            'geaendert': '${geaendert.millisecondsSinceEpoch}',
        }),
      },
    );
    expect(angelegt.statusCode, 201);
    final ort = angelegt.headers['location']!;
    final mitte = bytes.length ~/ 2;
    final erstes = await frag(
      'PATCH',
      ort,
      kopf: {
        ...tus,
        'content-type': 'application/offset+octet-stream',
        'upload-offset': '0',
      },
      inhalt: bytes.sublist(0, mitte),
    );
    expect(erstes.statusCode, 204);
    expect(erstes.headers['upload-offset'], '$mitte');
    return frag(
      'PATCH',
      ort,
      kopf: {
        ...tus,
        'content-type': 'application/offset+octet-stream',
        'upload-offset': '$mitte',
      },
      inhalt: bytes.sublist(mitte),
    );
  }

  test('ohne Schlüssel nur das Lebenszeichen', () async {
    expect(
      (await frag('GET', '/api/v1/zustand', schluessel: false)).statusCode,
      200,
    );
    final ohne = await frag('GET', '/api/v1/aufnahmen', schluessel: false);
    expect(ohne.statusCode, 401);
    final falsch = await frag(
      'GET',
      '/api/v1/aufnahmen',
      schluessel: false,
      kopf: {'authorization': 'Bearer ${'x' * 43}'},
    );
    expect(falsch.statusCode, 401);
    expect((await frag('GET', '/api/v1/aufnahmen')).statusCode, 200);
  });

  test('hochladen in Stücken, importieren, Dublette erkennen', () async {
    final bytes = jpeg(40);
    final datum = DateTime(2019, 5, 17, 14, 30);
    final r = await hochladen(bytes, 'strand.jpg', geaendert: datum);
    expect(r.statusCode, 204);
    expect(r.headers['pv-ausgang'], 'imported');
    final id = r.headers['pv-aufnahme']!;

    final seite = await jsonAus(await frag('GET', '/api/v1/aufnahmen'));
    final liste = (seite['aufnahmen']! as List).cast<Map>();
    expect(liste, hasLength(1));
    expect(liste.single['id'], id);
    expect(liste.single['name'], 'strand.jpg');
    expect(
      DateTime.parse(liste.single['aufgenommen']! as String),
      datum,
      reason: 'ohne EXIF zählt die Änderungszeit aus den Metadaten',
    );

    final nochmal = await hochladen(bytes, 'kopie.jpg');
    expect(nochmal.headers['pv-ausgang'], 'duplicateSkipped');
    expect(nochmal.headers['pv-aufnahme'], id);
  });

  test('ein Stück an falscher Stelle wird abgewiesen, Stand bleibt', () async {
    final bytes = jpeg(80);
    final angelegt = await frag(
      'POST',
      '/api/v1/hochladen',
      kopf: {
        ...tus,
        'upload-length': '${bytes.length}',
        'upload-metadata': meta({'filename': 'a.jpg'}),
      },
    );
    final ort = angelegt.headers['location']!;
    final falsch = await frag(
      'PATCH',
      ort,
      kopf: {
        ...tus,
        'content-type': 'application/offset+octet-stream',
        'upload-offset': '10',
      },
      inhalt: bytes,
    );
    expect(falsch.statusCode, 409);
    final stand = await frag('HEAD', ort, kopf: tus);
    expect(stand.headers['upload-offset'], '0');
    expect(stand.headers['upload-length'], '${bytes.length}');
  });

  test('Dateien: Miniatur, Original im Teilabruf', () async {
    final bytes = jpeg(120);
    final id = (await hochladen(bytes, 'b.jpg')).headers['pv-aufnahme']!;
    final miniatur = await frag('GET', '/api/v1/aufnahmen/$id/miniatur');
    expect(miniatur.statusCode, 200);
    expect(miniatur.headers['content-type'], 'image/jpeg');

    final teil = await frag(
      'GET',
      '/api/v1/aufnahmen/$id/original',
      kopf: {'range': 'bytes=2-9'},
    );
    expect(teil.statusCode, 206);
    expect(teil.headers['content-range'], 'bytes 2-9/${bytes.length}');
    final gelesen = await teil.read().expand((x) => x).toList();
    expect(gelesen, bytes.sublist(2, 10));
  });

  test('ein Befehl über die Schnittstelle', () async {
    final id = (await hochladen(jpeg(160), 'c.jpg')).headers['pv-aufnahme']!;
    final r = await frag(
      'POST',
      '/api/v1/befehle',
      inhalt: jsonEncode({
        'art': 'bewertungSetzen',
        'werte': {
          'ids': [id],
          'bewertung': 4,
        },
      }),
    );
    expect(r.statusCode, 200);
    final seite = await jsonAus(await frag('GET', '/api/v1/aufnahmen'));
    expect(((seite['aufnahmen']! as List).single as Map)['bewertung'], 4);

    final kaputt = await frag(
      'POST',
      '/api/v1/befehle',
      inhalt: '{"art":"gibtEsNicht","werte":{}}',
    );
    expect(kaputt.statusCode, 400);
  });

  test('blättern über das Lesezeichen', () async {
    for (var i = 0; i < 5; i++) {
      await hochladen(
        jpeg(10 + i * 30),
        'f$i.jpg',
        geaendert: DateTime(2020, 1, 1 + i),
      );
    }
    final gesehen = <String>[];
    String? nach;
    do {
      final seite = await jsonAus(
        await frag(
          'GET',
          '/api/v1/aufnahmen?anzahl=2${nach == null ? '' : '&nach=$nach'}',
        ),
      );
      gesehen.addAll([
        for (final a in (seite['aufnahmen']! as List).cast<Map>())
          a['name']! as String,
      ]);
      nach = seite['weiter'] as String?;
    } while (nach != null);
    expect(gesehen, ['f4.jpg', 'f3.jpg', 'f2.jpg', 'f1.jpg', 'f0.jpg']);
  });
}
