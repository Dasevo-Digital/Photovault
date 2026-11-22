// Gipfel, Hütten und Quellen am Rechner (#474): Verbunden fragt er nur den
// eigenen Server, ohne Server wie bisher Overpass.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/wanderobjekte.dart';
import 'package:photo_vault/services/wanderobjekte_am_rechner.dart';
import 'package:photo_vault/state/library_state.dart';

void main() {
  late AppDatabase db;

  // Die Netz-Attrappe für Overpass: zählt jede Anfrage und hätte einen
  // Gipfel – verbunden darf sie nie gefragt werden.
  late List<http.BaseRequest> anOverpass;
  late MockClient overpass;

  // Zur Laufzeit zusammengesetzt, damit keine Adresse im Test steht.
  final basis = Uri(scheme: 'http', host: 'server', path: '/');

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    anOverpass = [];
    overpass = MockClient((r) async {
      anOverpass.add(r);
      return http.Response(
        jsonEncode({
          'elements': [
            {
              'type': 'node',
              'id': 7,
              'lat': 51.80,
              'lon': 10.62,
              'tags': {'natural': 'peak', 'name': 'Von Overpass'},
            },
          ],
        }),
        200,
      );
    });
  });

  tearDown(() => db.close());

  LibraryState verbunden(MockClient server, {bool mitAbgleich = true}) {
    final lib = LibraryState()
      ..db = db
      ..verbindung = Verbindungsdatei(
        server: basis,
        konto: 'probe',
        geraet: 'Rechner',
        token: 'pv1_probe',
      );
    if (mitAbgleich) {
      lib.abgleich = Abgleich(
        db,
        Serververbindung(basis, 'pv1_probe', client: server),
      );
    }
    return lib;
  }

  Future<List<Wanderobjekt>> frage(
    LibraryState lib, {
    required void Function() serverLiefertNicht,
  }) => wanderobjekteAmRechner(
    lib,
    sued: 51.78,
    west: 10.60,
    nord: 51.82,
    ost: 10.65,
    serverLiefertNicht: serverLiefertNicht,
    netz: overpass,
  );

  test('verbunden kommen die Punkte vom Server, Overpass wird nie '
      'gefragt', () async {
    final anDenServer = <http.BaseRequest>[];
    final lib = verbunden(
      MockClient((r) async {
        anDenServer.add(r);
        return http.Response(
          jsonEncode({
            'punkte': [
              {
                'osmId': 42,
                'art': 'gipfel',
                'breite': 51.80,
                'laenge': 10.62,
                'name': 'Vom Server',
                'hoehe': 1141.2,
              },
              // Was ein neuerer Server kennt, und ein Punkt ohne Ort,
              // nehmen den Gipfel nicht mit.
              {'osmId': 43, 'art': 'unbekannt', 'breite': 51.8, 'laenge': 10.6},
              {'osmId': 44, 'art': 'quelle'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    var hinweise = 0;

    final punkte = await frage(lib, serverLiefertNicht: () => hinweise++);

    expect(anOverpass, isEmpty, reason: 'verbunden nie direkt an Overpass');
    expect(punkte.map((p) => (p.osmId, p.art, p.name, p.hoehe)), [
      (42, Wanderart.gipfel, 'Vom Server', 1141.2),
    ]);
    expect(hinweise, 0);
    // Derselbe Weg und dieselbe Anmeldung wie die übrigen Serveraufrufe.
    final r = anDenServer.single;
    expect(r.url.path, '/api/v1/wanderobjekte');
    expect(r.url.queryParameters, {
      'sued': '51.78000',
      'west': '10.60000',
      'nord': '51.82000',
      'ost': '10.65000',
    });
    expect(r.headers['authorization'], 'Bearer pv1_probe');
  });

  test('antwortet der Server nicht oder kennt den Weg nicht, gibt es einen '
      'Hinweis und keine Punkte – und keinen Rückfall auf Overpass', () async {
    final faelle = <String, LibraryState>{
      'nicht erreichbar': verbunden(
        MockClient((_) async => throw const SocketException('weg')),
      ),
      'älterer Server (404)': verbunden(
        MockClient((_) async => http.Response('Not Found', 404)),
      ),
      'Antwort ist kein JSON': verbunden(
        MockClient((_) async => http.Response('<html>Proxy</html>', 200)),
      ),
      'Abgleich noch nicht eingerichtet': verbunden(
        MockClient((_) async => fail('ohne Abgleich keine Anfrage')),
        mitAbgleich: false,
      ),
    };
    for (final MapEntry(key: fall, value: lib) in faelle.entries) {
      var hinweise = 0;
      final punkte = await frage(lib, serverLiefertNicht: () => hinweise++);
      expect(punkte, isEmpty, reason: fall);
      expect(hinweise, 1, reason: fall);
      expect(anOverpass, isEmpty, reason: '$fall: kein Rückfall auf Overpass');
    }
  });

  test('ohne Server wie bisher: von Overpass, dann aus der Bibliothek, ohne '
      'Hinweis', () async {
    final lib = LibraryState()..db = db;
    var hinweise = 0;

    final erst = await frage(lib, serverLiefertNicht: () => hinweise++);
    final dann = await frage(lib, serverLiefertNicht: () => hinweise++);

    expect(erst.map((p) => p.name), ['Von Overpass']);
    expect(dann.map((p) => p.name), ['Von Overpass']);
    expect(anOverpass, hasLength(1), reason: 'beim zweiten Mal gemerkt');
    expect(anOverpass.single.url, Uri.parse(overpassAdresse));
    expect(hinweise, 0);
  });
}
