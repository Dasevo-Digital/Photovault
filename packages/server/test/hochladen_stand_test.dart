import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Nach dem letzten Stück, solange der Import läuft (#262).
///
/// Der Import legt die Datei unter ihrem Namen in einen eigenen Ordner;
/// die `.teil`-Datei gibt es dann nicht mehr. Bis 3.53 antworteten HEAD
/// und Status in dieser Zeit mit 500 – am Server beobachtet bei einer DNG
/// mit 88 MB, zwei Sekunden lang.
void main() {
  late Directory ordner;
  setUp(() => ordner = Directory.systemTemp.createTempSync('pv_tus_stand_'));
  tearDown(() => ordner.deleteSync(recursive: true));

  test(
    'HEAD und Status melden die volle Länge, während importiert wird',
    () async {
      final weiter = Completer<void>();
      final angekommen = Completer<void>();
      final h = Hochladen(
        Directory(p.join(ordner.path, 'eingang')),
        null,
        // Wie der Import: die Datei aus dem Eingang nehmen, dann dauern.
        abschluss: (datei, _) async {
          await datei.rename(p.join(ordner.path, 'woanders'));
          angekommen.complete();
          await weiter.future;
          return {'ausgang': 'imported'};
        },
      );
      const tus = {'tus-resumable': '1.0.0'};
      final angelegt = await h.anlegen(
        Request(
          'POST',
          Uri.parse('http://s/api/v1/hochladen'),
          headers: {
            ...tus,
            'upload-length': '5',
            'upload-metadata': 'pfad ${base64.encode(utf8.encode('a/b.jpg'))}',
          },
        ),
      );
      final id = p.basename(angelegt.headers['location']!);
      final patch = h.anhaengen(
        Request(
          'PATCH',
          Uri.parse('http://s/api/v1/hochladen/$id'),
          headers: {
            ...tus,
            'content-type': 'application/offset+octet-stream',
            'upload-offset': '0',
          },
          body: [1, 2, 3, 4, 5],
        ),
        id,
      );
      await angekommen.future;

      final kopf = await h.stand(
        Request(
          'HEAD',
          Uri.parse('http://s/api/v1/hochladen/$id'),
          headers: tus,
        ),
        id,
      );
      expect(kopf.statusCode, 200);
      expect(kopf.headers['upload-offset'], '5');
      final status = await h.status(
        Request('GET', Uri.parse('http://s/api/v1/hochladen/$id/status')),
        id,
      );
      expect(status.statusCode, 200);
      final j = jsonDecode(await status.readAsString()) as Map;
      expect(j['erhalten'], 5);
      expect(j['ergebnis'], isNull, reason: 'noch nicht fertig');

      weiter.complete();
      expect((await patch).headers['pv-ausgang'], 'imported');
    },
  );

  test('ein vorübergehender Importfehler heisst 503, und der Stand ist fort '
      '(#316)', () async {
    final h = Hochladen(
      Directory(p.join(ordner.path, 'eingang')),
      null,
      abschluss: (_, _) async => {
        'ausgang': 'failed',
        'fehler': 'Platte voll',
        'voruebergehend': true,
      },
    );
    const tus = {'tus-resumable': '1.0.0'};
    final angelegt = await h.anlegen(
      Request(
        'POST',
        Uri.parse('http://s/api/v1/hochladen'),
        headers: {
          ...tus,
          'upload-length': '3',
          'upload-metadata': 'pfad ${base64.encode(utf8.encode('a/b.jpg'))}',
        },
      ),
    );
    final id = p.basename(angelegt.headers['location']!);
    final r = await h.anhaengen(
      Request(
        'PATCH',
        Uri.parse('http://s/api/v1/hochladen/$id'),
        headers: {
          ...tus,
          'content-type': 'application/offset+octet-stream',
          'upload-offset': '0',
        },
        body: [1, 2, 3],
      ),
      id,
    );
    expect(r.statusCode, 503);
    final kopf = await h.stand(
      Request('HEAD', Uri.parse('http://s/api/v1/hochladen/$id'), headers: tus),
      id,
    );
    expect(kopf.statusCode, 404);
  });
}
