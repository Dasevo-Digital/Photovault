import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:kern/services/wasserzeichen.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:photo_vault_server/src/fassungen_aufraeumen.dart';
import 'package:photo_vault_server/src/freigaben.dart' show Freigabedienst;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Ein Wasserzeichen je Link (#497): Der Server rechnet das Zeichen, das
/// das Gerät des Besitzers mitschickt, in Miniatur und Ansicht für Gäste
/// ein – nicht ins ausdrücklich erlaubte Original.
void main() {
  late Directory ordner;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late Konto erika;
  late Handler api;
  late String erikaToken;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_wasserzeichen_');
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
    erikaToken = konten.meldeAn(erika.id, 'Rechner', 'x').token;
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

  Future<Uint8List> bytesAus(Response r) async =>
      Uint8List.fromList(await r.read().expand((b) => b).toList());

  /// Ein blaues JPEG von 64 × 48 – klein genug, dass die Ansicht nicht
  /// verkleinert wird und die Ecke sich nachrechnen lässt.
  Future<(String, Uint8List)> ladeHoch(String name) async {
    final bild = img.Image(width: 64, height: 48);
    img.fill(bild, color: img.ColorRgb8(10, 120, 245));
    final bytes = Uint8List.fromList(img.encodeJpg(bild, quality: 95));
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
    return (fertig.headers['pv-aufnahme']!, bytes);
  }

  /// Ein deckend rotes Logo, doppelt so breit wie hoch.
  Uint8List rotesLogo({int breite = 40, int hoehe = 20}) {
    final logo = img.Image(width: breite, height: hoehe, numChannels: 4);
    img.fill(logo, color: img.ColorRgba8(230, 10, 10, 255));
    return Uint8List.fromList(img.encodePng(logo));
  }

  Map<String, Object?> zeichen({Uint8List? bild, String text = '© Erika'}) =>
      Wasserzeichen(
        art: Wasserzeichenart.text,
        text: text,
        bild: bild ?? rotesLogo(),
        groesse: 0.25,
        deckkraft: 1,
        rand: 0.03,
      ).alsJson();

  Future<Response> anlegen(Map<String, Object?> werte) => frag(
    'POST',
    '/api/v1/freigaben',
    token: erikaToken,
    kopf: {'content-type': 'application/json'},
    inhalt: jsonEncode(werte),
  );

  Future<Map<String, Object?>> teile(Map<String, Object?> werte) async {
    final r = await anlegen(werte);
    final text = await r.readAsString();
    expect(r.statusCode, 201, reason: text);
    return (jsonDecode(text) as Map).cast<String, Object?>();
  }

  String linkAus(Map<String, Object?> f) =>
      Uri.parse(f['link']! as String).pathSegments.last;

  Future<img.Image> bildVon(String link, String id, String art) async {
    final r = await frag('GET', '/api/v1/teilen/$link/$id/$art');
    expect(r.statusCode, 200, reason: art);
    return img.decodeJpg(await bytesAus(r))!;
  }

  bool rot(img.Pixel x) => x.r > 170 && x.g < 90 && x.b < 90;

  Future<Directory> geteilt() async => Directory(
    p.join(
      (await bibliotheken.fuer(erika.id)).bibliothek.ordner.path,
      'geteilt',
    ),
  );

  Future<List<String>> zwischengespeichert() async => [
    for (final e in (await geteilt()).listSync())
      if (e is File) p.basename(e.path),
  ]..sort();

  test('Ansicht und Miniatur tragen das Zeichen unten rechts, das erlaubte '
      'Original nicht', () async {
    final (a, roh) = await ladeHoch('a.jpg');
    final mit = await teile({
      'titel': 'Mit Zeichen',
      'ids': [a],
      'herunterladen': true,
      'wasserzeichen': zeichen(),
    });
    final ohne = await teile({
      'titel': 'Ohne',
      'ids': [a],
    });
    expect(mit['wasserzeichen'], isTrue);
    expect(mit['wasserzeichenText'], '© Erika');
    expect(ohne['wasserzeichen'], isFalse);
    expect(ohne.keys, isNot(contains('wasserzeichenText')));

    // 64 × 48: Rand 2 px, Zeichen 16 × 8 – also x 46…61, y 38…45.
    final ansicht = await bildVon(linkAus(mit), a, 'ansicht');
    expect(ansicht.width, 64);
    expect(rot(ansicht.getPixel(54, 42)), isTrue, reason: 'im Zeichen');
    expect(rot(ansicht.getPixel(10, 10)), isFalse, reason: 'oben links');
    expect(rot(ansicht.getPixel(54, 30)), isFalse, reason: 'über dem Zeichen');
    expect(rot(ansicht.getPixel(63, 47)), isFalse, reason: 'im Rand');

    final blank = await bildVon(linkAus(ohne), a, 'ansicht');
    expect(rot(blank.getPixel(54, 42)), isFalse, reason: 'Link ohne Zeichen');

    final miniatur = await bildVon(linkAus(mit), a, 'miniatur');
    final mx = (miniatur.width * 0.85).round();
    final my = (miniatur.height * 0.88).round();
    expect(rot(miniatur.getPixel(mx, my)), isTrue, reason: 'Miniatur');
    final miniOhne = await bildVon(linkAus(ohne), a, 'miniatur');
    expect(rot(miniOhne.getPixel(mx, my)), isFalse);

    // Ausdrücklich erlaubt, also Bit für Bit die hochgeladene Datei.
    final original = await frag(
      'GET',
      '/api/v1/teilen/${linkAus(mit)}/$a/original',
    );
    expect(original.statusCode, 200);
    expect(await bytesAus(original), roh);

    // Zwei Links, zwei Dateien: Das Zeichen des einen landet nicht im
    // Bild des anderen.
    final kennung = Wasserzeichen.ausJson(zeichen())!.kennung;
    expect(
      await zwischengespeichert(),
      unorderedEquals([
        '$a-a.jpg',
        '$a-m.jpg',
        '$a-a-$kennung.jpg',
        '$a-m-$kennung.jpg',
      ]),
    );
  });

  test(
    'ein Zeichen, das sich nicht einrechnen lässt, wird abgelehnt',
    () async {
      final (a, _) = await ladeHoch('a.jpg');
      for (final (grund, wert) in <(String, Object?)>[
        ('kein Objekt', 'unten rechts'),
        ('ohne Bild', {'art': 'text', 'text': '© Erika'}),
        (
          'kein PNG',
          zeichen(
            bild: Uint8List.fromList(
              img.encodeJpg(img.Image(width: 8, height: 8)),
            ),
          ),
        ),
        ('zu breit', zeichen(bild: rotesLogo(breite: 4097, hoehe: 1))),
        ('unbekannte Art', {...zeichen(), 'art': 'kreis'}),
        ('kein Base64', {...zeichen(), 'bild': '***'}),
      ]) {
        final r = await anlegen({
          'titel': 'X',
          'ids': [a],
          'wasserzeichen': wert,
        });
        expect(r.statusCode, 400, reason: grund);
        expect((await jsonAus(r))['fehler'], 'Wasserzeichen ungültig');
      }
      // Nichts davon wurde angelegt.
      final liste = await jsonAus(
        await frag('GET', '/api/v1/freigaben', token: erikaToken),
      );
      expect(liste['freigaben'], isEmpty);
    },
  );

  test('Löschen räumt die Bilder des Zeichens weg, sobald kein Link es mehr '
      'trägt', () async {
    final (a, _) = await ladeHoch('a.jpg');
    final eins = await teile({
      'titel': 'Eins',
      'ids': [a],
      'wasserzeichen': zeichen(),
    });
    final zwei = await teile({
      'titel': 'Zwei',
      'ids': [a],
      'wasserzeichen': zeichen(),
    });
    final ohne = await teile({
      'titel': 'Ohne',
      'ids': [a],
    });
    for (final f in [eins, ohne]) {
      await bildVon(linkAus(f), a, 'ansicht');
    }
    final kennung = Wasserzeichen.ausJson(zeichen())!.kennung;
    expect(await zwischengespeichert(), ['$a-a-$kennung.jpg', '$a-a.jpg']);

    Future<void> loesche(Map<String, Object?> f) async => expect(
      (await frag(
        'DELETE',
        '/api/v1/freigaben/${f['id']}',
        token: erikaToken,
      )).statusCode,
      200,
    );
    // Der zweite Link trägt dasselbe Zeichen: Die Datei bleibt.
    await loesche(eins);
    expect(await zwischengespeichert(), ['$a-a-$kennung.jpg', '$a-a.jpg']);
    await loesche(zwei);
    expect(await zwischengespeichert(), ['$a-a.jpg']);
  });

  test(
    'Aufräumen behält die Fassungen mit Zeichen lebender Aufnahmen',
    () async {
      final (a, _) = await ladeHoch('a.jpg');
      final f = await teile({
        'titel': 'Mit',
        'ids': [a],
        'wasserzeichen': zeichen(),
      });
      await bildVon(linkAus(f), a, 'ansicht');
      final d = await geteilt();
      final fremd = File(p.join(d.path, 'weg-a-0123456789ab.jpg'))
        ..writeAsBytesSync([1]);
      final b = (await bibliotheken.fuer(erika.id)).bibliothek;
      expect(await raeumeFassungenAuf(b), 1);
      expect(fremd.existsSync(), isFalse, reason: 'gibt es nicht mehr');
      final kennung = Wasserzeichen.ausJson(zeichen())!.kennung;
      expect(await zwischengespeichert(), ['$a-a-$kennung.jpg']);
    },
  );

  test('Serverdatenbank 14: bestehende Links bleiben ohne Zeichen', () async {
    final temp = await Directory.systemTemp.createTemp('pv_freigabe_14_');
    final datei = File('${temp.path}/server.sqlite');
    var bank = Serverdatenbank.oeffne(datei);
    try {
      bank.db.execute(
        "INSERT INTO konten (id, name, angelegt) VALUES ('k', 'eins', 1)",
      );
      final schluessel = Tresorschluessel(List.filled(32, 3));
      final neu = await Freigabedienst(
        bank,
        schluessel,
      ).lege(konto: 'k', titel: 'Alt', aufnahmen: ['x']);
      bank.db.execute('ALTER TABLE freigaben DROP COLUMN wasserzeichen');
      bank.db.execute('PRAGMA user_version = 14');
      bank.schliesse();

      bank = Serverdatenbank.oeffne(datei);
      final dienst = Freigabedienst(bank, schluessel);
      final alt = dienst.fuer(neu.link)!;
      expect(alt.titel, 'Alt');
      expect(alt.wasserzeichen, isNull);
      expect(alt.wasserzeichenKennung, isNull);
      expect(
        bank.db.select('PRAGMA user_version').single.columnAt(0),
        Serverdatenbank.schema,
      );
      // Danach lässt sich eines speichern.
      final w = Wasserzeichen.ausJson(zeichen())!;
      final mit = await dienst.lege(
        konto: 'k',
        titel: 'Neu',
        aufnahmen: ['x'],
        wasserzeichen: w,
      );
      expect(dienst.fuer(mit.link)!.wasserzeichenKennung, w.kennung);
    } finally {
      bank.schliesse();
      await temp.delete(recursive: true);
    }
  });
}
