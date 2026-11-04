import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Endgültig löschen und die Frist des Papierkorbs am Server (#296).
///
/// Bis 3.54 ging beides nur in der App ohne Server. Eine Bibliothek auf
/// dem Server behielt alles, was je in ihren Papierkorb kam, und die Frist
/// aus den Einstellungen galt dort nie.
void main() {
  late Directory ordner;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late Konto erika;
  late Handler api;
  late String token;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_papierkorb_');
    sdb = Serverdatenbank.imSpeicher();
    konten = Kontodienst(
      sdb,
      Tresorschluessel(List.filled(32, 5)),
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: false,
    );
    bibliotheken = Bibliotheken(
      wurzel: Directory('${ordner.path}/bibliotheken'),
      eingang: Directory('${ordner.path}/eingang'),
      ruhe: const Duration(hours: 1),
    );
    api = baueApi(konten: konten, bibliotheken: bibliotheken);
    erika = await konten.legeAn('erika', 'ein langes passwort');
    token = konten.meldeAn(erika.id, 'Rechner', 'x').token;
  });

  tearDown(() async {
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  Future<Response> frag(
    String methode,
    String pfad, {
    Map<String, String> kopf = const {},
    Object? inhalt,
  }) async => api(
    Request(
      methode,
      Uri.parse('http://server$pfad'),
      headers: {'authorization': 'Bearer $token', ...kopf},
      body: inhalt,
    ),
  );

  Future<Map<String, Object?>> jsonAus(Response r) async =>
      (jsonDecode(await r.readAsString()) as Map).cast<String, Object?>();

  Future<String> ladeHoch(String name, int farbe) async {
    final bild = img.Image(width: 48, height: 32);
    img.fill(bild, color: img.ColorRgb8(farbe, 120, 255 - farbe));
    final bytes = Uint8List.fromList(img.encodeJpg(bild));
    final tus = {'tus-resumable': '1.0.0'};
    final angelegt = await frag(
      'POST',
      '/api/v1/hochladen',
      kopf: {
        ...tus,
        'upload-length': '${bytes.length}',
        'upload-metadata': 'filename ${base64.encode(utf8.encode(name))}',
      },
    );
    final fertig = await frag(
      'PATCH',
      angelegt.headers['location']!,
      kopf: {
        ...tus,
        'content-type': 'application/offset+octet-stream',
        'upload-offset': '0',
      },
      inhalt: bytes,
    );
    expect(fertig.headers['pv-ausgang'], 'imported', reason: name);
    return fertig.headers['pv-aufnahme']!;
  }

  Future<void> befehl(String art, Map<String, Object?> w) async {
    final r = await frag(
      'POST',
      '/api/v1/befehle',
      kopf: {'content-type': 'application/json'},
      inhalt: jsonEncode({'art': art, 'werte': w}),
    );
    expect(r.statusCode, 200, reason: art);
  }

  Future<Response> leeren(Map<String, Object?> inhalt) => frag(
    'POST',
    '/api/v1/papierkorb/leeren',
    kopf: {'content-type': 'application/json'},
    inhalt: jsonEncode(inhalt),
  );

  Future<Bibliothek> bib() async =>
      (await bibliotheken.fuer(erika.id)).bibliothek;

  /// Die Dateien von [id], die es gibt – Original und Miniatur mindestens.
  Future<List<File>> dateien(String id) async {
    final b = await bib();
    final a = (await b.db.assetsByIds([id])).single;
    return [
      b.pfade.absolute(a.relativePath),
      if (a.thumbnailRelativePath case final t?) b.pfade.absolute(t),
    ];
  }

  test('der Server sagt, dass er es kann', () async {
    final z = await jsonAus(await frag('GET', '/api/v1/zustand'));
    expect((z['funktionen']! as Map)['papierkorb'], 1);
  });

  test('ausgewählte gehen mit ihren Dateien, alles andere bleibt', () async {
    final strand = await ladeHoch('strand.jpg', 10);
    final berg = await ladeHoch('berg.jpg', 90);
    final bleibt = await ladeHoch('bleibt.jpg', 200);
    await befehl('inDenPapierkorb', {
      'ids': [strand, berg],
    });
    final strandDateien = await dateien(strand);
    expect(strandDateien, hasLength(2));
    for (final f in strandDateien) {
      expect(f.existsSync(), isTrue, reason: f.path);
    }

    // Was nicht im Papierkorb liegt, geht auch dann nicht, wenn es in der
    // Liste steht.
    final r = await leeren({
      'ids': [strand, bleibt],
    });
    expect(r.statusCode, 200);
    expect((await jsonAus(r))['geloescht'], 1);

    final b = await bib();
    expect(await b.db.assetsByIds([strand]), isEmpty);
    for (final f in strandDateien) {
      expect(f.existsSync(), isFalse, reason: f.path);
    }
    expect((await b.db.assetsByIds([berg])).single.isTrashed, isTrue);
    expect((await b.db.assetsByIds([bleibt])).single.isTrashed, isFalse);
    for (final f in await dateien(bleibt)) {
      expect(f.existsSync(), isTrue, reason: f.path);
    }

    // Die Geräte erfahren es über das Protokoll.
    final mitgeschrieben = await b.db
        .customSelect(
          "SELECT 1 FROM pv_aenderungen WHERE tabelle = 'assets' "
          'AND schluessel = ?',
          variables: [
            Variable<String>(jsonEncode([strand])),
          ],
        )
        .get();
    expect(mitgeschrieben, isNotEmpty);

    // Und der Rest auf einmal.
    final alle = await leeren({'alle': true});
    expect((await jsonAus(alle))['geloescht'], 1);
    expect(await b.db.assetsByIds([berg]), isEmpty);
    expect(await b.db.papierkorb(), isEmpty);
  });

  test('ohne Angabe weist er ab', () async {
    expect((await leeren({})).statusCode, 400);
    expect(
      (await leeren({
        'ids': [1, 2],
      })).statusCode,
      400,
    );
  });

  test('ein Hinweis auf neue Beiträge geht mit der Aufnahme', () async {
    final beitrag = await ladeHoch('beitrag.jpg', 30);
    final max = await konten.legeAn('max', 'noch ein passwort');
    konten.albumteilungen.vermerkeBeitrag(
      besitzer: erika.id,
      aufnahme: beitrag,
      von: max.id,
      name: 'Max',
      album: 'urlaub',
    );
    expect(konten.albumteilungen.neueBeitraege(erika.id), hasLength(1));
    await befehl('inDenPapierkorb', {
      'ids': [beitrag],
    });
    await leeren({
      'ids': [beitrag],
    });
    expect(konten.albumteilungen.neueBeitraege(erika.id), isEmpty);
  });

  test('die Frist gilt am Server – nur wenn sie eingeschaltet ist', () async {
    final alt = await ladeHoch('alt.jpg', 50);
    final frisch = await ladeHoch('frisch.jpg', 150);
    await befehl('inDenPapierkorb', {
      'ids': [alt, frisch],
    });
    final b = await bib();
    // „alt“ kam vor 40 Tagen hinein.
    await (b.db.update(b.db.assets)..where((t) => t.id.equals(alt))).write(
      AssetsCompanion(
        trashedAt: Value(DateTime.now().subtract(const Duration(days: 40))),
      ),
    );
    final ablauf = Papierkorbablauf(konten: konten, bibliotheken: bibliotheken);

    // Aus, wie die Vorgabe: Es bleibt alles.
    await ablauf.pruefe();
    expect(await b.db.assetsByIds([alt]), hasLength(1));

    await befehl('papierkorbFristSetzen', {'an': true, 'tage': 30});
    await ablauf.pruefe();
    expect(await b.db.assetsByIds([alt]), isEmpty);
    expect((await b.db.assetsByIds([frisch])).single.isTrashed, isTrue);
    expect((await b.db.trashSettingsRow())!.lastPurgeAt, isNotNull);
  });
}
