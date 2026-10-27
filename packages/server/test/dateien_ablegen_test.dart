import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Abgeleitete Dateien ablegen (Issue #109): ein Gerät bringt das Bild
/// einer Entwicklung zum Server – nur in die dafür vorgesehenen Ordner,
/// nur vollständig, und nie dorthin, wo Originale liegen.
void main() {
  late Directory ordner;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late Konto erika;
  late Handler api;
  late String token;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_ablegen_');
    sdb = Serverdatenbank.imSpeicher();
    konten = Kontodienst(
      sdb,
      Tresorschluessel(List.filled(32, 3)),
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

  Future<Response> lege(
    String pfad,
    List<int> bytes, {
    Map<String, String> kopf = const {},
    String? laenge,
  }) async => api(
    Request(
      'PUT',
      Uri.parse('http://server/api/v1/dateien/$pfad'),
      headers: {
        'authorization': 'Bearer $token',
        'content-type': 'application/octet-stream',
        'content-length': laenge ?? '${bytes.length}',
        ...kopf,
      },
      body: bytes,
    ),
  );

  Future<Directory> wurzel() async =>
      (await bibliotheken.fuer(erika.id)).bibliothek.pfade.root;

  test(
    'ein entwickeltes Bild landet im Ordner developed und ist abrufbar',
    () async {
      final bytes = utf8.encode('ein JPEG, sagen wir');
      final r = await lege('developed/a1.jpg', bytes);
      expect(r.statusCode, 204, reason: await r.readAsString());
      final datei = File('${(await wurzel()).path}/developed/a1.jpg');
      expect(datei.readAsBytesSync(), bytes);
      expect(File('${datei.path}.teil').existsSync(), isFalse);

      // Ein zweites Mal ersetzt das erste – eine neue Entwicklung.
      final neu = utf8.encode('ein anderes JPEG');
      expect((await lege('developed/a1.jpg', neu)).statusCode, 204);
      expect(datei.readAsBytesSync(), neu);

      final zurueck = await api(
        Request(
          'GET',
          Uri.parse('http://server/api/v1/dateien/developed/a1.jpg'),
          headers: {'authorization': 'Bearer $token'},
        ),
      );
      expect(zurueck.statusCode, 200);
      expect(await zurueck.read().expand((b) => b).toList(), neu);
    },
  );

  test(
    'nur Abgeleitetes, nur eine Ebene, nichts Verstecktes, kein Ausbruch',
    () async {
      for (final pfad in [
        'originals/a1.jpg',
        'thumbnails/a1.jpg',
        'previews/a1.jpg',
        'library.sqlite',
        'developed/../originals/a1.jpg',
        'developed/..%2Foriginals/a1.jpg',
        'developed/unter/a1.jpg',
        'developed/.a1.jpg',
        'developed',
        '%2Fetc%2Fpasswd',
        '..%2Fgeheim.txt',
      ]) {
        final r = await lege(pfad, [1, 2, 3]);
        expect(r.statusCode, anyOf(403, 404), reason: pfad);
      }
      final w = await wurzel();
      expect(
        Directory('${w.path}/originals').existsSync() &&
            File('${w.path}/originals/a1.jpg').existsSync(),
        isFalse,
      );
      expect(File('${ordner.path}/geheim.txt').existsSync(), isFalse);
    },
  );

  test('ohne Länge, zu gross oder abgebrochen: nichts bleibt liegen', () async {
    // Ohne Länge – ein Strom, dessen Ende niemand kennt.
    final ohneLaenge = await api(
      Request(
        'PUT',
        Uri.parse('http://server/api/v1/dateien/masks/m1.png'),
        headers: {'authorization': 'Bearer $token'},
        body: Stream.fromIterable([
          [1, 2, 3],
        ]),
      ),
    );
    expect(ohneLaenge.statusCode, 411);
    // Mit angekündigter Länge, aber als Strom – so kommt es vom Netz.
    Future<Response> strom(String laenge) async => api(
      Request(
        'PUT',
        Uri.parse('http://server/api/v1/dateien/masks/m1.png'),
        headers: {'authorization': 'Bearer $token', 'content-length': laenge},
        body: Stream.fromIterable([
          [1, 2, 3],
        ]),
      ),
    );
    expect((await strom('${hoechstensAbgeleitet + 1}')).statusCode, 413);
    // Weniger Bytes als angekündigt: der Rest kam nie.
    expect((await strom('10')).statusCode, 400);
    final ordnerMasken = Directory('${(await wurzel()).path}/masks');
    expect(
      ordnerMasken.existsSync() ? ordnerMasken.listSync() : const [],
      isEmpty,
    );
  });

  test(
    'ohne Anmeldung nicht, und aus dem Browser nur mit dem Kopf der Oberfläche',
    () async {
      final ohne = await api(
        Request(
          'PUT',
          Uri.parse('http://server/api/v1/dateien/developed/a1.jpg'),
          headers: {'content-length': '3'},
          body: [1, 2, 3],
        ),
      );
      expect(ohne.statusCode, 401);
      final cookie = await api(
        Request(
          'PUT',
          Uri.parse('http://server/api/v1/dateien/developed/a1.jpg'),
          headers: {'content-length': '3', 'cookie': 'pv_web=$token'},
          body: [1, 2, 3],
        ),
      );
      expect(cookie.statusCode, 403, reason: 'Cookie ohne X-PV-Web');
    },
  );

  for (final zweiterVollstaendig in [false, true]) {
    test(
      'parallele Schreiber sind getrennt, zweiter vollständig: $zweiterVollstaendig',
      () async {
        final a = StreamController<List<int>>(),
            b = StreamController<List<int>>();
        final liestA = Completer<void>(), liestB = Completer<void>();
        a.onListen = () => liestA.complete();
        b.onListen = () => liestB.complete();
        Future<Response> sende(Stream<List<int>> inhalt) async => api(
          Request(
            'PUT',
            Uri.parse('http://server/api/v1/dateien/developed/parallel.jpg'),
            headers: {'authorization': 'Bearer $token', 'content-length': '4'},
            body: inhalt,
          ),
        );
        final laufA = sende(a.stream);
        await liestA.future;
        a.add([1, 1]);
        final laufB = sende(b.stream);
        await liestB.future;
        b.add([2, 2]);
        final ziel = File('${(await wurzel()).path}/developed/parallel.jpg');
        if (!zweiterVollstaendig) {
          await b.close();
          expect((await laufB).statusCode, 400);
        }
        a.add([1, 1]);
        await a.close();
        expect((await laufA).statusCode, 204);
        expect(await ziel.readAsBytes(), [1, 1, 1, 1]);
        if (zweiterVollstaendig) {
          b.add([2, 2]);
          await b.close();
          expect((await laufB).statusCode, 204);
          expect(await ziel.readAsBytes(), [2, 2, 2, 2]);
        }
        expect(
          ziel.parent.listSync().whereType<File>().where(
            (f) => f.path.endsWith('.teil'),
          ),
          isEmpty,
        );
      },
    );
  }
}
