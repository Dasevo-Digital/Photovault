import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Der Nachlasskontakt (#300): Erika benennt Max. Verlangt Max Zugang und
/// widerspricht Erika nicht binnen der Frist, sieht Max ihre Bibliothek.
void main() {
  late Directory ordner;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late Konto erika;
  late Konto max;
  late Handler api;
  late String erikaToken;
  late String maxToken;
  late String moritzToken;
  var jetzt = DateTime(2026, 11, 5, 12);

  setUp(() async {
    jetzt = DateTime(2026, 11, 5, 12);
    ordner = await Directory.systemTemp.createTemp('pv_nachlass_');
    sdb = Serverdatenbank.imSpeicher();
    konten = Kontodienst(
      sdb,
      Tresorschluessel(List.filled(32, 5)),
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: false,
      uhr: () => jetzt,
    );
    bibliotheken = Bibliotheken(
      wurzel: Directory('${ordner.path}/bibliotheken'),
      eingang: Directory('${ordner.path}/eingang'),
      ruhe: const Duration(hours: 1),
    );
    api = baueApi(konten: konten, bibliotheken: bibliotheken);
    erika = await konten.legeAn('erika', 'ein langes passwort');
    max = await konten.legeAn('max', 'noch ein passwort');
    final moritz = await konten.legeAn('moritz', 'ein drittes passwort');
    erikaToken = konten.meldeAn(erika.id, 'Rechner', 'x').token;
    maxToken = konten.meldeAn(max.id, 'Telefon', 'x').token;
    moritzToken = konten.meldeAn(moritz.id, 'Telefon', 'x').token;
  });

  tearDown(() async {
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  Future<Response> frag(
    String methode,
    String pfad, {
    required String token,
    Object? json,
    Map<String, String> kopf = const {},
    Object? inhalt,
  }) async => api(
    Request(
      methode,
      Uri.parse('http://server$pfad'),
      headers: {
        'authorization': 'Bearer $token',
        if (json != null) 'content-type': 'application/json',
        ...kopf,
      },
      body: json == null ? inhalt : jsonEncode(json),
    ),
  );

  Future<Map<String, Object?>> jsonAus(Response r) async =>
      (jsonDecode(await r.readAsString()) as Map).cast<String, Object?>();

  Future<Map<String, Object?>> stand(String token) async =>
      jsonAus(await frag('GET', '/api/v1/nachlass', token: token));

  Future<String> ladeHoch(String token, String name) async {
    final bild = img.Image(width: 40, height: 30);
    img.fill(bild, color: img.ColorRgb8(40, 120, 200));
    final bytes = Uint8List.fromList(img.encodeJpg(bild));
    final tus = {'tus-resumable': '1.0.0'};
    final angelegt = await frag(
      'POST',
      '/api/v1/hochladen',
      token: token,
      kopf: {
        ...tus,
        'upload-length': '${bytes.length}',
        'upload-metadata': 'filename ${base64.encode(utf8.encode(name))}',
      },
    );
    final fertig = await frag(
      'PATCH',
      angelegt.headers['location']!,
      token: token,
      kopf: {
        ...tus,
        'content-type': 'application/offset+octet-stream',
        'upload-offset': '0',
      },
      inhalt: bytes,
    );
    return fertig.headers['pv-aufnahme']!;
  }

  Future<int> partnerAnzahl() async =>
      ((await jsonAus(
                await frag('GET', '/api/v1/partner', token: maxToken),
              ))['mitMir']!
              as List)
          .length;

  test('benennen, verlangen, nach der Frist Zugang', () async {
    final foto = await ladeHoch(erikaToken, 'oma.jpg');
    expect(
      (await frag(
        'PUT',
        '/api/v1/nachlass/${max.id}',
        token: erikaToken,
        json: {'frist': 14},
      )).statusCode,
      204,
    );
    final fuerMax = ((await stand(maxToken))['fuerMich']! as List)
        .cast<Map>()
        .single;
    expect(fuerMax['name'], 'erika');
    expect(fuerMax['frist'], 14);

    // Moritz ist kein Kontakt.
    expect(
      (await frag(
        'POST',
        '/api/v1/nachlass/von/${erika.id}/anfordern',
        token: moritzToken,
      )).statusCode,
      404,
    );

    final r = await frag(
      'POST',
      '/api/v1/nachlass/von/${erika.id}/anfordern',
      token: maxToken,
    );
    expect(r.statusCode, 200);
    expect(
      DateTime.parse((await jsonAus(r))['faellig']! as String).toLocal(),
      jetzt.add(const Duration(days: 14)),
    );
    final beiErika = ((await stand(erikaToken))['kontakte']! as List)
        .cast<Map>()
        .single;
    expect(beiErika['angefordert'], isNotNull);
    expect(await partnerAnzahl(), 0, reason: 'noch nicht');

    jetzt = jetzt.add(const Duration(days: 13));
    Nachlassablauf(konten).pruefe();
    expect(await partnerAnzahl(), 0);

    jetzt = jetzt.add(const Duration(days: 1, minutes: 1));
    Nachlassablauf(konten).pruefe();
    expect(await partnerAnzahl(), 1);
    expect(
      (await frag(
        'GET',
        '/api/v1/partner/von/${erika.id}/aufnahmen/$foto/original',
        token: maxToken,
      )).statusCode,
      200,
    );

    // Erika lebt und nimmt Max zurück: Der Zugang geht mit.
    expect(
      (await frag(
        'DELETE',
        '/api/v1/nachlass/${max.id}',
        token: erikaToken,
      )).statusCode,
      204,
    );
    expect(await partnerAnzahl(), 0);
  });

  test('widersprochen: kein Zugang, eine Woche Pause', () async {
    await frag(
      'PUT',
      '/api/v1/nachlass/${max.id}',
      token: erikaToken,
      json: {'frist': 7},
    );
    await frag(
      'POST',
      '/api/v1/nachlass/von/${erika.id}/anfordern',
      token: maxToken,
    );
    expect(
      (await frag(
        'POST',
        '/api/v1/nachlass/${max.id}/ablehnen',
        token: erikaToken,
      )).statusCode,
      204,
    );
    jetzt = jetzt.add(const Duration(days: 8));
    Nachlassablauf(konten).pruefe();
    expect(await partnerAnzahl(), 0);
    final e = ((await stand(maxToken))['fuerMich']! as List).cast<Map>().single;
    expect(e['angefordert'], isNull);
    expect(e['abgelehnt'], isNotNull);

    // Acht Tage nach dem Widerspruch darf Max wieder fragen; gleich danach
    // nicht.
    await frag(
      'POST',
      '/api/v1/nachlass/${max.id}/ablehnen',
      token: erikaToken,
    );
    expect(
      (await frag(
        'POST',
        '/api/v1/nachlass/von/${erika.id}/anfordern',
        token: maxToken,
      )).statusCode,
      200,
    );
    await frag(
      'POST',
      '/api/v1/nachlass/${max.id}/ablehnen',
      token: erikaToken,
    );
    expect(
      (await frag(
        'POST',
        '/api/v1/nachlass/von/${erika.id}/anfordern',
        token: maxToken,
      )).statusCode,
      409,
    );
  });

  test('eine eingeschränkte Freigabe gilt mit dem Zugang ganz – und danach '
      'wieder eingeschränkt', () async {
    await ladeHoch(erikaToken, 'a.jpg');
    await frag(
      'PUT',
      '/api/v1/partner/${max.id}',
      token: erikaToken,
      json: {'ab': '2100-01-01'},
    );
    Future<int> anzahl() async =>
        (((await jsonAus(
                      await frag('GET', '/api/v1/partner', token: maxToken),
                    ))['mitMir']!
                    as List)
                .cast<Map>()
                .single['anzahl']!
            as int);
    expect(await anzahl(), 0);
    await frag(
      'PUT',
      '/api/v1/nachlass/${max.id}',
      token: erikaToken,
      json: {'frist': 7},
    );
    await frag(
      'POST',
      '/api/v1/nachlass/von/${erika.id}/anfordern',
      token: maxToken,
    );
    jetzt = jetzt.add(const Duration(days: 8));
    expect(await anzahl(), 1, reason: 'fällig, beim Nachsehen freigegeben');
    await frag('DELETE', '/api/v1/nachlass/${max.id}', token: erikaToken);
    expect(await anzahl(), 0, reason: 'die alte Einschränkung gilt wieder');
  });

  test('Frist und Zahl der Kontakte sind begrenzt', () async {
    expect(
      (await frag(
        'PUT',
        '/api/v1/nachlass/${max.id}',
        token: erikaToken,
        json: {'frist': 1},
      )).statusCode,
      400,
    );
    expect(
      (await frag(
        'PUT',
        '/api/v1/nachlass/${erika.id}',
        token: erikaToken,
      )).statusCode,
      404,
    );
  });
}
